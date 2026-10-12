# -*- coding: utf-8 -*-
"""생활 탭 축산물 시세: 축산물품질평가원(KAPE) 축산물유통정보 — 일자별 축산물소비자가격(소·돼지 부위별, 100g당).

호출: {EKAPE_LIVESTOCK_BASE_URL}/grade/consumerPriceDaily?standYmd=YYYYMMDD&judgeKind=4301(소)|4304(돼지)
 - 응답 item은 그날 값과 "평년"(같은 부위의 평년 평균) 두 묶음이 섞여 와서(standYmd가 날짜 / "평년") 나눠서 씀.
 - 계란·닭은 이 API에 소비자가격이 없음(검수확인정보만) → 지금은 소·돼지만. 오리·계란은 다른 출처가 필요.
 - 경로는 공공데이터포털 API 상세 화면(oprtinSeqNo)에서 확인함(2026-10-12). 일 1,000건 한도 → 6시간마다 2번.

응답에 덮어쓰는 필드: livestock(목록), livestock_date(기준일), livestock_source.
"""

from __future__ import annotations

from datetime import date, timedelta

import config
import jobs
import store
from sources import _http

SOURCE = "ekape_consumer"
KINDS = (("4304", "돼지"), ("4301", "소"))
# 부위 표시 순서(자주 사는 것부터)
ORDER = {"돼지": ["삼겹살", "목심", "앞다리", "갈비"], "소": ["등심", "안심", "양지", "갈비", "설도"]}


def _fetch(kind: str, day: date) -> list[dict]:
    return _http.get_xml_items(
        config.get_key("EKAPE_LIVESTOCK_BASE_URL") + "/grade/consumerPriceDaily",
        {"standYmd": day.strftime("%Y%m%d"), "judgeKind": kind},
    )


def run() -> dict:
    rows_out: list[dict] = []
    used_day: date | None = None
    hist: list[dict] = []
    for kind, kname in KINDS:
        items: list[dict] = []
        for back in range(1, 5):  # 어제 집계가 아직 없으면 그제…(최대 4일 전)
            day = date.today() - timedelta(days=back)
            items = _fetch(kind, day)
            if items:
                used_day = used_day or day
                break
        today_rows = [i for i in items if i.get("standYmd") != "평년"]
        # 지난주 같은 요일 값(전주 대비용) — 없으면 비교 없이 표시
        try:
            prev_items = _fetch(kind, used_day - timedelta(days=7)) if used_day else []
        except Exception:
            prev_items = []
        prev = {(i["itemNm"], i["grdNm"]): int(float(i["ntslPrc"])) for i in prev_items if i.get("standYmd") != "평년" and i.get("ntslPrc")}
        normal = {(i["itemNm"], i["grdNm"]): i for i in items if i.get("standYmd") == "평년"}
        part_rank = {p: n for n, p in enumerate(ORDER[kname])}
        for it in sorted(today_rows, key=lambda i: (part_rank.get(i["itemNm"], 99), i["grdNm"] != "1+등급")):
            price = int(float(it["ntslPrc"]))
            base = normal.get((it["itemNm"], it["grdNm"]))
            norm = int(float(base["ntslPrc"])) if base and base.get("ntslPrc") else None
            norm_pct = round((price - norm) / norm * 100, 1) if norm else None
            week = prev.get((it["itemNm"], it["grdNm"]))
            pct = round((price - week) / week * 100, 1) if week else None  # 행에는 지난주 대비만 보이고, 평년 대비는 상세 시트에
            grade = "" if it["grdNm"] in ("구분없음", "") else f" {it['grdNm']}"
            label = f"{kname} {it['itemNm']}{grade}"
            rows_out.append(
                {
                    "label": label,
                    "sub": "100g",
                    "value": f"{price:,}원",
                    "change": "flat" if pct is None or abs(pct) < 0.5 else ("up" if pct > 0 else "down"),
                    "pct": abs(pct) if pct is not None else None,
                    # 상세 시트용
                    "detail": {
                        "price": price,
                        "week": week,
                        "week_pct": pct,
                        "normal": norm,
                        "normal_pct": norm_pct,
                        "min": int(float(it["minPrc"])) if it.get("minPrc") else None,
                        "max": int(float(it["maxPrc"])) if it.get("maxPrc") else None,
                        "kind": kname,
                        "part": it["itemNm"],
                        "grade": "" if it["grdNm"] in ("구분없음", "") else it["grdNm"],
                    },
                }
            )
            hist.append({"item": label, "day": day.isoformat(), "price": price, "unit": "100g"})
    if not rows_out or used_day is None:
        raise RuntimeError("축산물 소비자가격 없음")
    store.record_prices(SOURCE, hist)
    return {
        "livestock": rows_out,
        "livestock_date": used_day.isoformat(),
        "livestock_source": "축산물품질평가원 축산물유통정보(소비자가격)",
    }


jobs.register(jobs.Job(name="livestock", run=run, env_keys=[_http.KEY_ENV, "EKAPE_LIVESTOCK_BASE_URL"], interval_min=360))
