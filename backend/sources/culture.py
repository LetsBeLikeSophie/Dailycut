# -*- coding: utf-8 -*-
"""문화 수집: 한국관광공사 TourAPI(곧 열리는 축제) + 한국문화정보원(진행 중인 전시·공연).

사용자 위치 기준으로 가까운 순으로 보여줌. 두 API 모두 행사 좌표를 주기 때문에
전국 목록을 받아 거리(km)로 정렬함 — 시도 코드나 지오코더가 필요 없음.
박스오피스(KOBIS)와 음악 순위(Spotify·YouTube)는 키가 없어서 스텁 그대로.
응답에 덮어쓰는 필드: festivals, performances.
"""

from __future__ import annotations

from datetime import datetime, timedelta

import html

import config
import geo
from sources import _cache, _http


def available() -> bool:
    return config.has_keys([_http.KEY_ENV, "TOUR_API_BASE_URL", "TOUR_API_MOBILE_OS", "TOUR_API_MOBILE_APP", "KCISA_CULTURE_BASE_URL"])


def _md(s: str) -> str:
    d = datetime.strptime(s, "%Y%m%d")
    return f"{d.month}.{d.day}"


def _km(lat: float, lon: float, ylat: str | None, xlon: str | None) -> float | None:
    try:
        return geo.haversine_km((lat, lon), (float(ylat), float(xlon)))
    except (TypeError, ValueError):
        return None


def _dist_label(km: float | None) -> str:
    if km is None:
        return ""
    return "1km 이내" if km < 1 else f"{km:.0f}km"


def _festivals(lat: float, lon: float, today: datetime) -> list[dict]:
    base = config.get_key("TOUR_API_BASE_URL")
    # 시작일이 한 달 전인 행사까지 가져와서 "지금 진행 중이거나 곧 시작하는 것"만 남김
    body = _http.get_json(
        base + "/searchFestival2",
        {
            "MobileOS": config.get_key("TOUR_API_MOBILE_OS"),
            "MobileApp": config.get_key("TOUR_API_MOBILE_APP"),
            "_type": "json",
            "eventStartDate": (today - timedelta(days=30)).strftime("%Y%m%d"),
            "numOfRows": 400,
            "pageNo": 1,
        },
    )
    t0 = today.strftime("%Y%m%d")
    t1 = (today + timedelta(days=9)).strftime("%Y%m%d")

    def span(r: dict) -> int:
        return (datetime.strptime(r["eventenddate"], "%Y%m%d") - datetime.strptime(r["eventstartdate"], "%Y%m%d")).days

    # 연중(1.1~12.31) 상시 행사는 "곧 열리는 축제"가 아니라서 45일 넘는 건 뺌
    rows = [
        r
        for r in _http.items_of(body)
        if r.get("eventenddate", "") >= t0 and r.get("eventstartdate", "") <= t1 and span(r) <= 45
    ]
    for r in rows:
        r["_km"] = _km(lat, lon, r.get("mapy"), r.get("mapx"))
    rows.sort(key=lambda r: (r["_km"] is None, r["_km"] or 0, r["eventstartdate"]))
    out = []
    for r in rows[:6]:
        place = " ".join((r.get("addr1") or "").split()[:2])
        bits = [f"{_md(r['eventstartdate'])}~{_md(r['eventenddate'])}", _dist_label(r["_km"]), place]
        out.append({"title": html.unescape(r["title"]), "meta": " · ".join(b for b in bits if b)})
    return out


def _performances(lat: float, lon: float, today: datetime) -> list[dict]:
    base = config.get_key("KCISA_CULTURE_BASE_URL")
    rows = _http.get_xml_items(
        base + "/period2",
        {
            "from": today.strftime("%Y%m%d"),
            "to": (today + timedelta(days=7)).strftime("%Y%m%d"),
            "cPage": 1,
            "rows": 100,
            # 사용자 주변(약 ±0.25도 ≈ 25km) 상자. 상자 안에 행사가 적으면 전국에서 가까운 순으로 보충됨.
            "gpsxfrom": round(lon - 0.25, 4),
            "gpsyfrom": round(lat - 0.25, 4),
            "gpsxto": round(lon + 0.25, 4),
            "gpsyto": round(lat + 0.25, 4),
        },
    )
    for r in rows:
        r["_km"] = _km(lat, lon, r.get("gpsY"), r.get("gpsX"))
    rows.sort(key=lambda r: (r["_km"] is None, r["_km"] or 0))
    out, seen = [], set()
    for r in rows:
        r["title"] = html.unescape(r["title"])
        if r["title"] in seen:
            continue
        seen.add(r["title"])
        bits = [r.get("place", ""), f"~{_md(r['endDate'])}", _dist_label(r["_km"])]
        out.append({"title": html.unescape(r["title"]), "meta": " · ".join(b for b in bits if b)})
        if len(out) == 6:
            break
    return out


def fetch(lat: float, lon: float) -> dict:
    today = datetime.now()
    out = {}
    errors = []
    for key, fn in (("festivals", _festivals), ("performances", _performances)):
        try:
            out[key] = fn(lat, lon, today)
        except Exception as e:
            errors.append(f"{key}: {e}")
    if not out:
        raise RuntimeError("; ".join(errors))
    return out


def get(lat: float, lon: float) -> dict | None:
    """위치별(약 10km 칸) 캐시된 문화 정보. 키/수집 실패 시 None → 스텁."""
    if not available():
        return None
    try:
        return _cache.cached("culture", f"culture:{round(lat, 1)}:{round(lon, 1)}", 60, lambda: fetch(lat, lon))
    except Exception:
        return None
