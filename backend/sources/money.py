# -*- coding: utf-8 -*-
"""머니 수집: 금융위원회 지수시세정보(코스피·코스닥) + 일반상품시세(금·유가).

주의: 이 두 데이터는 출처표시·상업적 이용금지·변경금지(공공누리 4유형)라서
광고/유료 기능을 붙이면 다시 확인해야 함. 영업일 종가라 하루 늦게 올라옴.
환율·기준금리(ECOS 키 없음)와 예·적금(금융상품 한눈에 키 없음)은 스텁 그대로.

응답에 덮어쓰는 필드: hero(코스피 이번 달 일별 종가), stats(시장 지표 목록),
back_title / back(뒤집으면 보이는 지표), source.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta

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


HISTORY_YEARS = 5


def _paged(url: str, params: dict) -> list[dict]:
    out, page = [], 1
    while page <= 6:
        body = _http.get_json(url, {**params, "numOfRows": 1000, "pageNo": page})
        out += _http.items_of(body)
        if page * 1000 >= int(body.get("totalCount") or 0):
            break
        page += 1
    return out


def _down(rows: list[dict]) -> list[dict]:
    """최근 400일은 일별 그대로, 그보다 오래된 건 주마다 마지막 영업일만 남겨 용량을 줄임(5년치도 600점 안팎)."""
    cut = (date.today() - timedelta(days=400)).strftime("%Y%m%d")
    old, weekly = [i for i in rows if i["basDt"] < cut], {}
    for i in old:
        d = datetime.strptime(i["basDt"], "%Y%m%d").date()
        weekly[d.isocalendar()[:2]] = i  # 같은 주의 뒤 값이 앞 값을 덮어씀(rows는 날짜 오름차순)
    return sorted(weekly.values(), key=lambda i: i["basDt"]) + [i for i in rows if i["basDt"] >= cut]


def _begin() -> str:
    return (date.today() - timedelta(days=365 * HISTORY_YEARS + 10)).strftime("%Y%m%d")


def _series(rows: list[dict], key: str = "clpr") -> list[dict]:
    return [{"date": _iso(i["basDt"]), "value": _f(i[key])} for i in rows]


def _chart_item(label: str, rows: list[dict], unit: str, decimals: int, sub: str, note: str) -> dict | None:
    """칩으로 고르는 차트 한 개. rows는 basDt 오름차순."""
    if not rows:
        return None
    last = rows[-1]
    pct = _f(last.get("fltRt", 0))
    return {
        "label": label,
        "value": _f(last["clpr"]),
        "unit": unit,
        "decimals": decimals,
        "change": _change(pct),
        "pct": round(abs(pct), 2),
        "sub": sub,
        "note": note,
        "when": "마지막 거래일엔",
        "series": _series(rows),
    }


def run() -> dict:
    today = date.today()
    month_start = today.replace(day=1).strftime("%Y%m%d")

    # 코스피: 이번 달 일별 종가(차트), 이번 달 데이터가 아직 없으면(월초·연휴) 덮어쓰지 않음
    kospi_all = _index("코스피", begin=None, rows=3)
    kospi_month = [i for i in _index("코스피", begin=month_start) if i["basDt"] >= month_start]
    kosdaq = _index("코스닥", begin=None, rows=2)
    kosdaq_month = [i for i in _index("코스닥", begin=month_start) if i["basDt"] >= month_start]
    charts: dict[str, dict] = {}
    gold_month: list[dict] = []

    out: dict = {"source": "금융위원회 지수시세정보 · 일반상품시세정보"}
    k_item = _chart_item("코스피", kospi_month or kospi_all[-1:], "pt", 1, "한국거래소 종가", "영업일 기준이라 하루 늦게 올라와요")
    if k_item:
        charts["코스피"] = k_item
    q_item = _chart_item("코스닥", kosdaq_month or kosdaq[-1:], "pt", 1, "한국거래소 종가", "영업일 기준이라 하루 늦게 올라와요")
    if q_item:
        charts["코스닥"] = q_item
    # 기간 칩(1개월~5년)을 위한 긴 이력. 실패하면 위의 이번 달 시리즈로 둠.
    for label, name in (("코스피", "코스피"), ("코스닥", "코스닥")):
        try:
            rows = sorted(
                (i for i in _paged(config.get_key("FSC_INDEX_BASE_URL") + "/getStockMarketIndex_V2", {"resultType": "json", "idxNm": name, "beginBasDt": _begin()}) if i.get("idxNm") == name),
                key=lambda i: i["basDt"],
            )
            if len(rows) > 5 and label in charts:
                charts[label]["series"] = _series(_down(rows))
        except Exception:
            pass
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
        gold = _http.items_of(
            _http.get_json(
                config.get_key("FSC_COMMODITY_BASE_URL") + "/getGoldPriceInfo_V2",
                {"resultType": "json", "numOfRows": 60, "pageNo": 1, "beginBasDt": month_start},
            )
        )
        gold_month = sorted((i for i in gold if "1kg" in i.get("itmsNm", "") and i["basDt"] >= month_start), key=lambda i: i["basDt"])
        g = next((i for i in sorted(gold, key=lambda i: i["basDt"], reverse=True) if "1kg" in i.get("itmsNm", "")), None)
        try:
            grows = sorted(
                (i for i in _paged(config.get_key("FSC_COMMODITY_BASE_URL") + "/getGoldPriceInfo_V2", {"resultType": "json", "beginBasDt": _begin()}) if "1kg" in i.get("itmsNm", "")),
                key=lambda i: i["basDt"],
            )
            if len(grows) > 5 and gold_month:
                gold_month = grows
        except Exception:
            pass
        if gold_month:
            gi = _chart_item("금", gold_month if len(gold_month) < 100 else _down(gold_month), "원/g", 0, "KRX 금시장 1kg 종가 · 1g 가격", "영업일 기준이라 하루 늦게 올라와요")
            if gi:
                charts["금"] = gi
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

    # 소비자물가지수(KOSIS, 전국 총지수) — 최근 25개월을 받아 최근 13개월의 전년 동월 대비 상승률 계열을 만듦
    try:
        body = _http.get_json(
            config.get_key("KOSIS_BASE_URL") + "/getStatisticsData",
            {"orgId": "101", "tblId": "DT_1J22003", "prdSe": "M", "newEstPrdCnt": 12 * HISTORY_YEARS + 13, "numOfRows": 100, "pageNo": 1, "itmId": "T+", "objL1": "T10", "format": "json"},
        )
        rows = sorted(_http.items_of(body), key=lambda r: r["PRD_DE"])
        if len(rows) >= 13:
            cur, prev = rows[-1], rows[-13]
            yoy = (_f(cur["DT"]) / _f(prev["DT"]) - 1) * 100
            ym = f"{cur['PRD_DE'][:4]}.{cur['PRD_DE'][4:]}"
            stats.append({"label": "소비자물가", "sub": f"{ym} · 전년 동월 대비", "value": f"{yoy:+.1f}%", "change": _change(yoy), "pct": None})
            cpi_series = []
            for k in range(12, len(rows)):
                if k - 12 < 0:
                    continue
                v = (_f(rows[k]["DT"]) / _f(rows[k - 12]["DT"]) - 1) * 100
                d = rows[k]["PRD_DE"]
                cpi_series.append({"date": f"{d[:4]}-{d[4:]}-01", "value": round(v, 2)})
            if len(rows) == 13:  # 25개월을 못 받았으면 한 점만
                cpi_series = [{"date": f"{cur['PRD_DE'][:4]}-{cur['PRD_DE'][4:]}-01", "value": round(yoy, 2)}]
            charts["물가"] = {
                "label": "물가",
                "value": round(yoy, 1),
                "unit": "%",
                "decimals": 1,
                "change": _change(yoy),
                "pct": None,
                "sub": f"{ym} 소비자물가 상승률(통계청) · 전년 동월 대비",
                "note": "월 1회 발표라 지난달까지만 있어요",
                "monthly": True,
                "when": "1년 전보다",
                "series": cpi_series,
            }
    except Exception:
        pass

    if not stats:
        raise RuntimeError("지수·상품 시세 없음")
    out["stats"] = stats
    # 칩으로 고르는 차트(코스피·코스닥·금·물가) — 화면은 이걸로 큰 숫자+추이를 그림
    order = ["코스피", "코스닥", "금", "물가"]
    out["chart_items"] = [charts[k] for k in order if k in charts]
    # 뒤집으면 보이는 면: 시장 지표 전체를 한 줄 요약으로
    out["back_title"] = "시장 지표"
    out["back"] = [
        {"title": s["label"], "meta": f"{s['value']} {'▲' if s['change'] == 'up' else '▼' if s['change'] == 'down' else '－'}" + (f" {s['pct']}%" if s.get("pct") is not None else "")}
        for s in stats
    ]
    return out


jobs.register(
    jobs.Job(
        name="money",
        run=run,
        env_keys=[_http.KEY_ENV, "FSC_INDEX_BASE_URL", "FSC_COMMODITY_BASE_URL"],  # KOSIS_BASE_URL은 있으면 소비자물가도 붙임
        interval_min=180,
    )
)
