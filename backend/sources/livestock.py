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
    # 2026-10-17: 장보기 시세 목록의 작은 그래프(최근 2주)를 위해 지난 14일 값도 채움 — 이미 기록한 날은 건너뛰고, 주말·휴일처럼
    # 집계가 없는 날은 매 실행 때 다시 시도(호출은 하루 최대 28번 안팎). 오늘 목록에 있는 부위·등급만 기록.
    wanted = {h["item"] for h in hist}
    have = store.price_days(SOURCE)
    for kind, kname in KINDS:
        for back in range(1, 15):
            d = used_day - timedelta(days=back)
            if d.isoformat() in have:
                continue
            try:
                past = _fetch(kind, d)
            except Exception:
                continue
            for it in past:
                if it.get("standYmd") == "평년" or not it.get("ntslPrc"):
                    continue
                grade = "" if it["grdNm"] in ("구분없음", "") else f" {it['grdNm']}"
                label = f"{kname} {it['itemNm']}{grade}"
                if label in wanted:
                    hist.append({"item": label, "day": d.isoformat(), "price": int(float(it["ntslPrc"])), "unit": "100g"})
    store.record_prices(SOURCE, hist)
    return {
        "livestock": rows_out,
        "livestock_date": used_day.isoformat(),
        "livestock_source": "축산물품질평가원 축산물유통정보(소비자가격)",
    }


jobs.register(jobs.Job(name="livestock", run=run, env_keys=[_http.KEY_ENV, "EKAPE_LIVESTOCK_BASE_URL"], interval_min=360))


def catalog_rows() -> list[dict]:
    """장보기 시세 목록(채소·과일·수산…)에 "정육"으로 섞어 넣을 행(2026-10-17). 모양은 aT 품목 행과 같고, 상세 시트용 detail·label을 더 가짐.
    작은 그래프(series)는 지난 14일 기록이 3개 이상 쌓였을 때만."""
    live = jobs.get_live("livestock")
    if not live or not live.get("livestock"):
        return []
    try:
        since = (date.fromisoformat(live["livestock_date"]) - timedelta(days=14)).isoformat()
    except (KeyError, ValueError):
        since = ""
    out = []
    for r in live["livestock"]:
        d = r.get("detail") or {}
        if not d.get("price"):
            continue
        row = {
            "name": r["label"],
            "label": r["label"],
            "category": "정육",
            "sub": r.get("sub") or "100g",
            "price": d["price"],
            "week_ago": d.get("week"),
            "pct": d.get("week_pct"),
            "change": r["change"],
            "season": None,
            "in_season": None,
            "guide": None,
            "detail": d,
        }
        pts = store.price_series(SOURCE, r["label"], since) if since else []
        if len(pts) >= 3:
            row["series"] = [round(p) for _, p in pts[-8:]]
        out.append(row)
    return out


def chart_items(month_start: str) -> dict:
    """내 장바구니(생활 맨 위 지수·차트)에 정육도 담을 수 있게, aT 품목의 chart_items와 같은 모양으로 만든 소·돼지 부위별 값(2026-10-17).
    키는 화면에 보이는 이름(예: "돼지 삼겹살"), 단위는 원/100g. 이번 달 흐름은 price_history(축산물)에서."""
    live = jobs.get_live("livestock")
    out = {}
    for r in (live or {}).get("livestock", []):
        d = r.get("detail") or {}
        if not d.get("price"):
            continue
        out[r["label"]] = {
            "unit": "원/100g",
            "price": d["price"],
            "week_ago": d.get("week"),
            "series": [{"date": day, "price": round(p)} for day, p in store.price_series(SOURCE, r["label"], month_start)],
        }
    return out
