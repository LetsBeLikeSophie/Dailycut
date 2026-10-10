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
import xml.etree.ElementTree as ET

import config
import geo
from sources import _cache, _http


def available() -> bool:
    return config.has_keys([_http.KEY_ENV, "TOUR_API_BASE_URL", "TOUR_API_MOBILE_OS", "TOUR_API_MOBILE_APP", "KCISA_CULTURE_BASE_URL"])


def _md(s: str) -> str:
    d = datetime.strptime(s, "%Y%m%d")
    return f"{d.month}.{d.day}"


def _festivals(place: dict, today: datetime) -> list[dict]:
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
    # 시도 단위: 주소가 이 시도로 시작하는 행사만, 곧 시작하는/진행 중인 순서로
    rows = [r for r in rows if geo.sido_of_address(r.get("addr1")) == place["code"]]

    def sgg_of(r: dict) -> str:
        parts = (r.get("addr1") or "").split()
        return parts[1] if len(parts) > 1 else ""

    # 고른 시군구의 행사를 먼저, 그다음 같은 시도의 나머지(시작일 순)
    mine = lambda r: bool(place["names"]) and sgg_of(r) in place["names"]
    rows.sort(key=lambda r: (not mine(r), r["eventstartdate"], r["title"]))
    out = []
    for r in rows[:6]:
        bits = [f"{_md(r['eventstartdate'])}~{_md(r['eventenddate'])}", sgg_of(r)]
        out.append({"title": html.unescape(r["title"]), "meta": " · ".join(b for b in bits if b), "local": mine(r)})
    return out


def _kcisa_all(today: datetime) -> list[dict]:
    """한국문화정보원 향후 7일 전시·공연 전국 목록(시도 필터 파라미터가 먹지 않아서 전부 받아 코드에서 거름).
    한 번에 100건(numOfrows, 소문자 r 주의)씩 받아 4~5번 호출이라 2시간 캐시해서 시도 17곳이 함께 씀."""
    base = config.get_key("KCISA_CULTURE_BASE_URL")

    def load() -> dict:
        rows, page, total = [], 1, None
        while page <= 12:
            r = _http.get(
                base + "/period2",
                {"from": today.strftime("%Y%m%d"), "to": (today + timedelta(days=7)).strftime("%Y%m%d"), "cPage": page, "numOfrows": 100},
            )
            root = ET.fromstring(r.content)
            code = root.findtext(".//resultCode")
            if code not in (None, "00"):
                raise RuntimeError(f"API 오류 {code}")
            total = int(root.findtext(".//totalCount") or 0)
            rows += [{c.tag: (c.text or "").strip() for c in it} for it in root.iter("item")]
            if page * 100 >= total:
                break
            page += 1
        return {"rows": rows}

    return _cache.cached("culture", f"culture:kcisa:{today.strftime('%Y%m%d')}", 120, load)["rows"]


def _performances(place: dict, today: datetime) -> list[dict]:
    out, seen = [], set()
    rows_all = [r for r in _kcisa_all(today) if r.get("area") == place["air"]]
    # 고른 시군구의 행사를 먼저, 그다음 같은 시도의 나머지
    rows_all.sort(key=lambda r: not (bool(place["names"]) and r.get("sigungu") in place["names"]))
    for r in rows_all:
        if False:  # 한국문화정보원도 "서울/부산/경기…" 짧은 시도명
            continue
        title = html.unescape(r["title"])
        if title in seen:
            continue
        seen.add(title)
        bits = [r.get("place", ""), f"~{_md(r['endDate'])}", r.get("sigungu", "")]
        out.append(
            {
                "title": title,
                "meta": " · ".join(b for b in bits if b),
                "local": bool(place["names"]) and r.get("sigungu") in place["names"],
            }
        )
        if len(out) == 6:
            break
    return out


def fetch(code: str, sgg: str | None = None) -> dict:
    region = geo.place(code, sgg)
    today = datetime.now()
    out = {}
    errors = []
    for key, fn in (("festivals", _festivals), ("performances", _performances)):
        try:
            out[key] = fn(region, today)
        except Exception as e:
            errors.append(f"{key}: {e}")
    if not out:
        raise RuntimeError("; ".join(errors))
    return out


def get(code: str, sgg: str | None = None) -> dict | None:
    """지역별 캐시된 문화 정보. 키/수집 실패 시 None → 스텁."""
    if not available():
        return None
    pl = geo.place(code, sgg)
    try:
        out = _cache.cached("culture", f"culture:{pl['key']}", 60, lambda: fetch(pl["code"], pl["sgg"]))
    except Exception:
        return None
    # 화면 안내: 고른 시군구에 몇 곳 있고 나머지는 시도에서 채웠는지
    notes = {}
    for key in ("festivals", "performances"):
        rows = out.get(key) or []
        notes[key] = {"local": sum(1 for r in rows if r.get("local")), "total": len(rows)}
    return {**out, "culture_scope": {"label": pl["label"], "sgg": pl["sgg"], "sido": pl["sido"], **notes}}
