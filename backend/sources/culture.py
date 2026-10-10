# -*- coding: utf-8 -*-
"""문화 수집: 한국관광공사 TourAPI(주말 축제) + 한국문화정보원(진행 중인 공연).

박스오피스(KOBIS)와 음악 순위(Spotify·YouTube)는 키가 없어서 스텁 그대로.
응답에 덮어쓰는 필드: festivals, performances.
"""

from __future__ import annotations

from datetime import datetime, timedelta

import config
import jobs
from sources import _http


def _md(s: str) -> str:
    d = datetime.strptime(s, "%Y%m%d")
    return f"{d.month}.{d.day}"


def _festivals(today: datetime) -> list[dict]:
    base = config.get_key("TOUR_API_BASE_URL")
    # 시작일이 한 달 전인 행사까지 가져와서 "지금 진행 중이거나 곧 시작하는 것"만 남김
    body = _http.get_json(
        base + "/searchFestival2",
        {
            "MobileOS": config.get_key("TOUR_API_MOBILE_OS"),
            "MobileApp": config.get_key("TOUR_API_MOBILE_APP"),
            "_type": "json",
            "eventStartDate": (today - timedelta(days=30)).strftime("%Y%m%d"),
            "numOfRows": 300,
            "pageNo": 1,
        },
    )
    t0 = today.strftime("%Y%m%d")
    t1 = (today + timedelta(days=9)).strftime("%Y%m%d")
    def span(r: dict) -> int:
        return (datetime.strptime(r["eventenddate"], "%Y%m%d") - datetime.strptime(r["eventstartdate"], "%Y%m%d")).days

    # 연중(1.1~12.31) 상시 행사는 "이번 주말 축제"가 아니라서 45일 넘는 건 뺌
    rows = [
        r
        for r in _http.items_of(body)
        if r.get("eventenddate", "") >= t0 and r.get("eventstartdate", "") <= t1 and span(r) <= 45
    ]
    rows.sort(key=lambda r: (r["eventstartdate"], r["title"]))
    out = []
    for r in rows[:6]:
        place = " ".join((r.get("addr1") or "").split()[:2])
        out.append({"title": r["title"], "meta": f"{_md(r['eventstartdate'])}~{_md(r['eventenddate'])} · {place}".strip(" ·")})
    return out


def _performances(today: datetime) -> list[dict]:
    base = config.get_key("KCISA_CULTURE_BASE_URL")
    rows = _http.get_xml_items(
        base + "/period2",
        {"from": today.strftime("%Y%m%d"), "to": (today + timedelta(days=7)).strftime("%Y%m%d"), "cPage": 1, "rows": 60, "sido": "서울"},
    )
    rows = [r for r in rows if r.get("realmName") in ("공연", "연극", "음악", "무용", "뮤지컬", "전시")] or rows
    out, seen = [], set()
    for r in rows:
        if r["title"] in seen:
            continue
        seen.add(r["title"])
        out.append({"title": r["title"], "meta": f"{r.get('place', '')} · ~{_md(r['endDate'])}".strip(" ·")})
        if len(out) == 6:
            break
    return out


def run() -> dict:
    today = datetime.now()
    out = {}
    errors = []
    for key, fn in (("festivals", _festivals), ("performances", _performances)):
        try:
            out[key] = fn(today)
        except Exception as e:
            errors.append(f"{key}: {e}")
    if not out:
        raise RuntimeError("; ".join(errors))
    return out


jobs.register(
    jobs.Job(
        name="culture",
        run=run,
        env_keys=[_http.KEY_ENV, "TOUR_API_BASE_URL", "TOUR_API_MOBILE_OS", "TOUR_API_MOBILE_APP", "KCISA_CULTURE_BASE_URL"],
        interval_min=180,
    )
)
