# -*- coding: utf-8 -*-
"""문화 탭 박스오피스: 영화진흥위원회(KOBIS) 일별 박스오피스 TOP 10(영화관입장권통합전산망, 출처표시).

키: KOBIS_KEY (.env). 하루 3,000건 한도라 3시간마다 1회만 부름.
응답에 덮어쓰는 필드: box_office(TOP 10), box_office_date(기준일), hero(레거시 화면용 1위 요약).
"""

from __future__ import annotations

from datetime import date, timedelta

import requests

import config
import jobs

URL = "http://www.kobis.or.kr/kobisopenapi/webservice/rest/boxoffice/searchDailyBoxOfficeList.json"


def _man(n: int) -> str:
    """관객 수 → "13.9만" / "2,884만" / "8,200"(1만 미만은 그대로)"""
    if n >= 10000:
        v = n / 10000
        return f"{v:,.1f}만" if v < 100 else f"{v:,.0f}만"
    return f"{n:,}"


def _fetch(day: date) -> list[dict]:
    r = requests.get(URL, params={"key": config.get_key("KOBIS_KEY"), "targetDt": day.strftime("%Y%m%d")}, timeout=20)
    r.raise_for_status()
    return (r.json().get("boxOfficeResult") or {}).get("dailyBoxOfficeList") or []


def run() -> dict:
    # 어제 집계가 아직 안 올라왔으면(새벽) 그제로
    for back in (1, 2):
        day = date.today() - timedelta(days=back)
        rows = _fetch(day)
        if rows:
            break
    else:
        raise RuntimeError("박스오피스 없음")

    when = "어제" if back == 1 else f"{day.month}/{day.day}"
    items = []
    for m in rows[:10]:
        inten = int(m.get("rankInten") or 0)
        tag = " · 신규" if m.get("rankOldAndNew") == "NEW" else (f" · ▲{inten}" if inten > 0 else (f" · ▼{-inten}" if inten < 0 else ""))
        items.append(
            {
                "rank": int(m["rank"]),
                "title": m["movieNm"],
                "meta": f"{when} {_man(int(m['audiCnt']))}명 · 누적 {_man(int(m['audiAcc']))}명{tag}",
            }
        )
    top = rows[0]
    return {
        "box_office": items,
        "box_office_date": day.isoformat(),
        "hero": {
            "theme": "culture",
            "label": f"{when} 박스오피스 1위",
            "title": top["movieNm"],
            "poster": None,
            "rank": 1,
            "stat_label": "누적 관객",
            "stat": f"{_man(int(top['audiAcc']))}명",
            "source": "영화진흥위원회 영화관입장권통합전산망",
        },
    }


jobs.register(jobs.Job(name="boxoffice", run=run, env_keys=["KOBIS_KEY"], interval_min=180))
