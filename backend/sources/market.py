# -*- coding: utf-8 -*-
"""생활(장바구니 물가) 수집: 농수산식품유통공사 최근일자 도·소매 가격 + 제철/고르는 법 편집 정보.

한 번 호출로 품목별 "조사일 / 1일 전 / 1주 전 / 1개월 전 / 1년 전" 평균 가격이 오고, 일자별
과거 값(perDay)은 데이터가 비어 있어서 못 씀. 그래서 매 실행마다 조사일·1일 전·1주 전 값을
price_history에 저장해서 이번 달 추이를 쌓아감(서버를 켠 날부터 점이 늘어남). KAMIS 키가 오면
과거 일별 이력으로 채울 예정.

응답에 덮어쓰는 필드:
- catalog: 전 품목(채소·과일·수산·축산·곡물) 가격 + 지난주 대비 + 제철 여부(편집 데이터)
- basket: "장바구니 지수"(대표 8품목의 지난주 대비 평균 변화, 지난주=100) + 이번 달 지수 추이
- chart_items: 장바구니 품목별 이번 달 가격 추이(화면에서 칩으로 골라 보는 용)
- guide: 제철 시기·고르는 법·보관법·사진(편집 정보, data/produce_guide.json·produce_images.json)
- season_now: 이번 달 제철 품목 이름들
- price_trend / items: 예전 화면 호환용(배추 중심)
"""

from __future__ import annotations

import json
from datetime import datetime, timedelta
from functools import lru_cache
from pathlib import Path

import config
import jobs
import store
from sources import _http

SOURCE = "at_recent"
DATA = Path(__file__).resolve().parent.parent / "data"
HERO = "배추"
# 장바구니 지수를 이루는 대표 품목(자주 사는 채소·과일). 지난주 가격 대비 평균 변화로 계산함.
BASKET = ["배추", "무", "양파", "당근", "감자", "오이", "사과", "배"]
CATEGORY = {"채소류": "채소", "과일류": "과일", "수산물": "수산", "축산물": "축산", "식량작물": "곡물·감자류", "특용작물": "곡물·감자류"}
CATEGORY_ORDER = ["채소", "과일", "수산", "축산", "곡물·감자류"]
ALIAS = {"깐마늘(국산)": "마늘"}  # aT 품목 이름 → 가이드 이름
IMAGE_KEY = {"물오징어": "오징어"}  # 가이드 이름 → 사진 파일 이름(사진은 일반 이름으로 저장함)


@lru_cache(maxsize=1)
def _guide() -> dict:
    p = DATA / "produce_guide.json"
    return json.loads(p.read_text(encoding="utf-8")).get("items", {}) if p.exists() else {}


@lru_cache(maxsize=1)
def _images() -> dict:
    p = DATA / "produce_images.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


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
    by_name: dict[str, list[dict]] = {}
    for r in rows:
        if r.get("se_cd") == "01" and _f(r.get("exmn_dd_prc")):
            by_name.setdefault(r["item_nm"], []).append(r)
    out: dict[str, dict] = {}
    for name, sel in by_name.items():

        def avg(field: str, sel=sel) -> float | None:
            vals = [_f(r.get(field)) for r in sel]
            vals = [v for v in vals if v]
            return sum(vals) / len(vals) if vals else None

        def adjusted(field: str, sel=sel) -> float | None:
            """과거 값은 품종마다 있고 없고가 달라서(예: 세척 당근엔 1주 전 값이 없음),
            과거 값이 있는 품종끼리의 변화율을 구해 전체 평균 가격에 적용함."""
            pairs = [(_f(r.get("exmn_dd_prc")), _f(r.get(field))) for r in sel]
            pairs = [(n, v) for n, v in pairs if n and v]
            if not pairs:
                return None
            return avg("exmn_dd_prc") * (sum(v for _, v in pairs) / sum(n for n, _ in pairs))

        unit = sel[0].get("unit") or ""
        size = sel[0].get("unit_sz") or "1"
        out[name] = {
            "day": datetime.strptime(sel[0]["exmn_ymd"], "%Y%m%d").date(),
            "now": avg("exmn_dd_prc"),
            "d1": adjusted("dd1_bfr_prc"),
            "w1": adjusted("ww1_bfr_prc"),
            "unit": f"{size if size != '1' else ''}{unit}",
            "category": CATEGORY.get(sel[0].get("ctgry_nm"), "기타"),
        }
    return out


def _sub(unit: str) -> str:
    return f"1{unit}" if not unit[:1].isdigit() else unit


def _guide_key(name: str) -> str | None:
    key = ALIAS.get(name, name)
    return key if key in _guide() else None


def _catalog(data: dict[str, dict], month: int, day) -> list[dict]:
    out = []
    since = (day - timedelta(days=14)).isoformat()
    for name, c in data.items():
        now, w1 = c["now"], c["w1"]
        pct = round((now - w1) / w1 * 100, 1) if w1 else None
        change = "flat" if pct is None or abs(pct) < 0.5 else ("up" if pct > 0 else "down")
        gk = _guide_key(name)
        months = (_guide().get(gk) or {}).get("season") or None if gk else None
        pts = store.price_series(SOURCE, name, since)
        row = {
            "name": ALIAS.get(name, name),
            "category": c["category"],
            "sub": _sub(c["unit"]),
            "price": round(now),
            "week_ago": round(w1) if w1 else None,
            "pct": pct,
            "change": change,
            "season": months,
            "in_season": (month in months) if months else None,
            "guide": gk,
        }
        if len(pts) >= 3:
            row["series"] = [round(p) for _, p in pts[-8:]]
        out.append(row)
    # 카테고리 순서 → 제철인 것 먼저 → 이름순
    out.sort(key=lambda r: (CATEGORY_ORDER.index(r["category"]) if r["category"] in CATEGORY_ORDER else 99, not r["in_season"], r["name"]))
    return out


def _basket(data: dict[str, dict], month_start: str) -> dict | None:
    items = [n for n in BASKET if n in data and data[n]["w1"] and data[n]["now"]]
    if len(items) < 5:
        return None
    ratios = [data[n]["now"] / data[n]["w1"] for n in items]
    value = 100 * sum(ratios) / len(ratios)
    # 이번 달 지수 추이: 모든 품목 값이 있는 날짜마다 "(그날 가격 ÷ 지난주 가격) 평균"
    per_item = {n: dict(store.price_series(SOURCE, n, month_start)) for n in items}
    days = sorted(set.intersection(*[set(v) for v in per_item.values()])) if per_item else []
    series = [
        {"date": d, "value": round(100 * sum(per_item[n][d] / data[n]["w1"] for n in items) / len(items), 2)}
        for d in days
    ]
    return {
        "name": "장바구니 지수",
        "note": f"{'·'.join(items)} {len(items)}품목 평균 · 지난주=100",
        "items": items,
        "value": round(value, 1),
        "change_pct": round(value - 100, 1),
        "series": series,
    }


def run() -> dict:
    rows = _fetch_all()
    data = _collect(rows)
    if HERO not in data:
        raise RuntimeError(f"{HERO} 가격 없음")

    # 가격 이력 저장(조사일, 1일 전, 1주 전) — 전 품목
    hist = []
    for name, c in data.items():
        for key, delta in (("now", 0), ("d1", 1), ("w1", 7)):
            if c.get(key):
                hist.append({"item": name, "day": (c["day"] - timedelta(days=delta)).isoformat(), "price": c[key], "unit": c["unit"]})
    store.record_prices(SOURCE, hist)

    h = data[HERO]
    day = h["day"]
    month_start = day.replace(day=1).isoformat()
    month = datetime.now().month
    catalog = _catalog(data, month, day)
    basket = _basket(data, month_start)

    chart_items = {}
    for n in BASKET:
        if n not in data:
            continue
        c = data[n]
        chart_items[n] = {
            "unit": f"원/{_sub(c['unit'])}",
            "price": round(c["now"]),
            "week_ago": round(c["w1"]) if c["w1"] else None,
            "series": [{"date": d, "price": round(p)} for d, p in store.price_series(SOURCE, n, month_start)],
        }

    guide = {}
    for gk, g in _guide().items():
        guide[gk] = {**g, "image": _images().get(IMAGE_KEY.get(gk, gk))}

    w1 = h["w1"] or h["now"]
    return {
        "source": "한국농수산식품유통공사 · 소매가(상품 등급 평균)",
        "as_of": day.isoformat(),
        "catalog": catalog,
        "basket": basket,
        "chart_items": chart_items,
        "guide": guide,
        "season_now": [r["name"] for r in catalog if r["in_season"]],
        # 예전 화면 호환
        "price_trend": {
            "item": HERO,
            "unit": f"원/{h['unit'] or '개'}",
            "series": [{"date": d, "price": round(p)} for d, p in store.price_series(SOURCE, HERO, month_start)],
            "latest": {"date": day.isoformat(), "price": round(h["now"])},
            "week_ago": round(w1),
            "change_pct": round((h["now"] - w1) / w1 * 100, 1),
        },
    }


jobs.register(jobs.Job(name="market", run=run, env_keys=[_http.KEY_ENV, "AT_PRICE_RECENT_BASE_URL"], interval_min=180))
