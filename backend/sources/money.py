# -*- coding: utf-8 -*-
"""머니 수집: 금융위원회 지수시세정보(코스피·코스닥) + 일반상품시세(금·유가).

주의: 이 두 데이터는 출처표시·상업적 이용금지·변경금지(공공누리 4유형)라서
광고/유료 기능을 붙이면 다시 확인해야 함. 영업일 종가라 하루 늦게 올라옴.
환율·기준금리(ECOS 키 없음)와 예·적금(금융상품 한눈에 키 없음)은 스텁 그대로.

응답에 덮어쓰는 필드: hero(코스피 이번 달 일별 종가), stats(시장 지표 목록),
back_title / back(뒤집으면 보이는 지표), source.
"""

from __future__ import annotations

from datetime import date, datetime

import config
import jobs
from sources import _http


def _f(v) -> float:
    return float(str(v).replace(",", ""))


def _index(name: str, begin: str | None = None, rows: int = 40) -> list[dict]:
    params = {"resultType": "json", "numOfRows": rows, "pageNo": 1, "idxNm": name}
    if begin:
        params["beginBasDt"] = begin
    items = _http.items_of(_http.get_json(config.get_key("FSC_INDEX_BASE_URL") + "/getStockMarketIndex_V2", params))
    return sorted((i for i in items if i.get("idxNm") == name), key=lambda i: i["basDt"])


def _change(pct: float) -> str:
    return "flat" if abs(pct) < 0.005 else ("up" if pct > 0 else "down")


def _iso(basdt: str) -> str:
    return datetime.strptime(basdt, "%Y%m%d").date().isoformat()


def run() -> dict:
    today = date.today()
    month_start = today.replace(day=1).strftime("%Y%m%d")

    # 코스피: 이번 달 일별 종가(차트), 이번 달 데이터가 아직 없으면(월초·연휴) 덮어쓰지 않음
    kospi_all = _index("코스피", begin=None, rows=3)
    kospi_month = [i for i in _index("코스피", begin=month_start) if i["basDt"] >= month_start]
    kosdaq = _index("코스닥", begin=None, rows=2)

    out: dict = {"source": "금융위원회 지수시세정보 · 일반상품시세정보"}
    stats = []

    latest_kospi = (kospi_month or kospi_all)[-1] if (kospi_month or kospi_all) else None
    if latest_kospi:
        pct = _f(latest_kospi["fltRt"])
        if kospi_month:
            out["hero"] = {
                "theme": "money",
                "label": "코스피",
                "value": _f(latest_kospi["clpr"]),
                "unit": "pt",
                "change": _change(pct),
                "series": [{"date": _iso(i["basDt"]), "value": _f(i["clpr"])} for i in kospi_month],
                "source": "금융위원회 지수시세정보 (한국거래소 종가)",
            }
        stats.append(
            {"label": "코스피", "sub": f"{_iso(latest_kospi['basDt'])} 종가", "value": f"{_f(latest_kospi['clpr']):,.1f}", "change": _change(pct), "pct": round(abs(pct), 2)}
        )
    if kosdaq:
        k = sorted(kosdaq, key=lambda i: i["basDt"])[-1]
        pct = _f(k["fltRt"])
        stats.append({"label": "코스닥", "sub": f"{_iso(k['basDt'])} 종가", "value": f"{_f(k['clpr']):,.1f}", "change": _change(pct), "pct": round(abs(pct), 2)})

    # 금(1g 기준 가격) · 유가
    try:
        gold = _http.items_of(_http.get_json(config.get_key("FSC_COMMODITY_BASE_URL") + "/getGoldPriceInfo_V2", {"resultType": "json", "numOfRows": 5, "pageNo": 1}))
        g = next((i for i in sorted(gold, key=lambda i: i["basDt"], reverse=True) if "1kg" in i.get("itmsNm", "")), None)
        if g:
            pct = _f(g["fltRt"])
            stats.append({"label": "금", "sub": f"{_iso(g['basDt'])} · 1g", "value": f"{_f(g['clpr']):,.0f}원", "change": _change(pct), "pct": round(abs(pct), 2)})
    except Exception:
        pass
    try:
        oil = _http.items_of(_http.get_json(config.get_key("FSC_COMMODITY_BASE_URL") + "/getOilPriceInfo_V2", {"resultType": "json", "numOfRows": 12, "pageNo": 1}))
        for want in ("휘발유", "경유"):
            o = next((i for i in sorted(oil, key=lambda i: i["basDt"], reverse=True) if want in i.get("itmsNm", "")), None)
            if o:
                pct = _f(o["fltRt"])
                stats.append({"label": want, "sub": f"{_iso(o['basDt'])} · 리터", "value": f"{_f(o['clpr']):,.0f}원", "change": _change(pct), "pct": round(abs(pct), 2)})
    except Exception:
        pass

    if not stats:
        raise RuntimeError("지수·상품 시세 없음")
    out["stats"] = stats
    # 뒤집으면 보이는 면: 시장 지표 전체를 한 줄 요약으로
    out["back_title"] = "시장 지표"
    out["back"] = [{"title": s["label"], "meta": f"{s['value']} {'▲' if s['change'] == 'up' else '▼' if s['change'] == 'down' else '－'} {s['pct']}%"} for s in stats]
    return out


jobs.register(
    jobs.Job(
        name="money",
        run=run,
        env_keys=[_http.KEY_ENV, "FSC_INDEX_BASE_URL", "FSC_COMMODITY_BASE_URL"],
        interval_min=180,
    )
)
