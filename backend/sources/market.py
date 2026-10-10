# -*- coding: utf-8 -*-
"""생활(장바구니 물가) 수집: 농수산식품유통공사 최근일자 도·소매 가격.

한 번 호출로 품목별 "조사일 / 1일 전 / 1주 전 / 1개월 전 / 1년 전" 평균 가격이
오고, 일자별 과거 값(perDay)은 최근 날짜가 비어 있어서 못 씀. 그래서 매 실행마다
조사일·1일 전·1주 전 값을 price_history에 저장해서 이번 달 추이를 쌓아감 —
서버를 켜둔 날부터 점이 늘어남(첫날은 점 3개).

응답에 덮어쓰는 필드: price_trend(배추 대표), items(채소 시세 목록), source.
축산물·생필품·제철·전통시장은 이 소스로 못 채워서 스텁이 그대로 남음.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta

import config
import jobs
import store
from sources import _http

SOURCE = "at_recent"
# 대표 품목(이 순서대로 목록에 나옴). 첫 번째가 큰 숫자/차트의 주인공.
ITEMS = ["배추", "무", "양파", "당근", "고구마", "사과"]
HERO = "배추"


def _f(v) -> float | None:
    try:
        return float(v) if v not in (None, "") else None
    except ValueError:
        return None


def _fetch_all() -> list[dict]:
    base = config.get_key("AT_PRICE_RECENT_BASE_URL")
    rows, page = [], 1
    while True:
        body = _http.get_json(base + "/price", {"returnType": "json", "pageNo": page, "numOfRows": 100})
        rows += _http.items_of(body)
        if page * 100 >= int(body.get("totalCount") or 0) or page >= 10:
            return rows
        page += 1


def _collect(rows: list[dict]) -> dict[str, dict]:
    """품목별로 소매·상품 등급 품종들의 평균을 냄(품종마다 가격 차이가 커서)."""
    out: dict[str, dict] = {}
    for name in ITEMS:
        sel = [r for r in rows if r.get("item_nm") == name and r.get("se_cd") == "01" and _f(r.get("exmn_dd_prc"))]
        if not sel:
            continue

        def avg(field: str) -> float | None:
            vals = [_f(r.get(field)) for r in sel]
            vals = [v for v in vals if v]
            return sum(vals) / len(vals) if vals else None

        def adjusted(field: str) -> float | None:
            """과거 값은 품종마다 있고 없고가 달라서(예: 세척 당근엔 1주 전 값이 없음),
            과거 값이 있는 품종끼리의 변화율을 구해 전체 평균 가격에 적용함."""
            pairs = [(_f(r.get("exmn_dd_prc")), _f(r.get(field))) for r in sel]
            pairs = [(n, v) for n, v in pairs if n and v]
            if not pairs:
                return None
            return avg("exmn_dd_prc") * (sum(v for _, v in pairs) / sum(n for n, _ in pairs))

        day = datetime.strptime(sel[0]["exmn_ymd"], "%Y%m%d").date()
        unit = sel[0].get("unit") or ""
        size = sel[0].get("unit_sz") or "1"
        out[name] = {
            "day": day,
            "now": avg("exmn_dd_prc"),
            "d1": adjusted("dd1_bfr_prc"),
            "w1": adjusted("ww1_bfr_prc"),
            "unit": f"{size if size != '1' else ''}{unit}",
        }
    return out


def _row(name: str, c: dict) -> dict:
    now, w1 = c["now"], c["w1"]
    pct = round((now - w1) / w1 * 100, 1) if w1 else 0.0
    change = "flat" if abs(pct) < 0.5 else ("up" if pct > 0 else "down")
    since = (c["day"] - timedelta(days=14)).isoformat()
    pts = store.price_series(SOURCE, name, since)
    row = {
        "label": name,
        "sub": f"1{c['unit']}" if not c["unit"][:1].isdigit() else c["unit"],
        "value": f"{round(now):,}원",
        "change": change,
        "pct": pct,
    }
    if len(pts) >= 3:
        row["series"] = [p for _, p in pts[-8:]]
    return row


def run() -> dict:
    rows = _fetch_all()
    data = _collect(rows)
    if HERO not in data:
        raise RuntimeError(f"{HERO} 가격 없음")

    # 가격 이력 저장(조사일, 1일 전, 1주 전)
    hist = []
    for name, c in data.items():
        for key, delta in (("now", 0), ("d1", 1), ("w1", 7)):
            if c.get(key):
                hist.append({"item": name, "day": (c["day"] - timedelta(days=delta)).isoformat(), "price": c[key], "unit": c["unit"]})
    store.record_prices(SOURCE, hist)

    h = data[HERO]
    month_start = h["day"].replace(day=1).isoformat()
    series = [{"date": d, "price": round(p)} for d, p in store.price_series(SOURCE, HERO, month_start)]
    w1 = h["w1"] or h["now"]
    return {
        "source": "한국농수산식품유통공사 · 소매가(상품 등급 평균)",
        "price_trend": {
            "item": HERO,
            "unit": f"원/{h['unit'] or '개'}",
            "series": series,
            "latest": {"date": h["day"].isoformat(), "price": round(h["now"])},
            "week_ago": round(w1),
            "change_pct": round((h["now"] - w1) / w1 * 100, 1),
        },
        "items": [_row(n, data[n]) for n in ITEMS if n in data],
    }


jobs.register(jobs.Job(name="market", run=run, env_keys=[_http.KEY_ENV, "AT_PRICE_RECENT_BASE_URL"], interval_min=180))
