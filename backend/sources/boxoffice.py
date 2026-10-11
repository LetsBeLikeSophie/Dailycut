# -*- coding: utf-8 -*-
"""문화 탭 영화: 영화진흥위원회(KOBIS) 오픈API (영화관입장권통합전산망, 출처표시).

키: KOBIS_KEY (.env). 하루 3,000건 한도 — 박스오피스는 3시간마다 12번(기간 3 × 구분 4), 지역별·상세는 요청 때 캐시해서 부름.

백그라운드 작업(boxoffice)이 응답에 덮어쓰는 필드:
  box_office           일별 전체 TOP 10 (예전 화면 호환: rank/title/meta)
  box_office_sets      "daily|weekly|weekend" × "all|kr|foreign|indie" → 항목 목록
                       항목: rank, code, title, audi(그 기간 관객), acc(누적), scrn(스크린 수), show(상영 횟수),
                             share(매출 점유율 %), sales(매출), open(개봉일), inten(순위 변동), new(신규), meta
  box_office_ranges    기간 표시 문구(예: 일별 "10/10", 주간 "9/28~10/4")
  box_office_date      일별 기준일
  new_releases         최근 7일 안에 개봉한 영화(박스오피스에 든 것만 — 개봉예정 목록은 성인물이 섞여서 일부러 안 씀)
  hero                 예전 화면용 1위 요약
요청 때 부르는 함수: region_items(시도코드) — 지역별 일별 TOP 10, detail(영화코드) — 영화 상세.
"""

from __future__ import annotations

import re
from datetime import date, timedelta

import requests

import config
import geo
import jobs
from sources import _cache

BASE = "http://www.kobis.or.kr/kobisopenapi/webservice/rest/"

# 앱의 시도(이름) → KOBIS 지역 코드(공통코드 0105000000)
WIDE_AREA = {
    "서울": "0105001", "경기": "0105002", "강원": "0105003", "충북": "0105004", "충남": "0105005", "경북": "0105006",
    "경남": "0105007", "전북": "0105008", "전남": "0105009", "제주": "0105010", "부산": "0105011", "대구": "0105012",
    "대전": "0105013", "울산": "0105014", "인천": "0105015", "광주": "0105016", "세종": "0105017",
}
FILTERS = {"all": {}, "kr": {"repNationCd": "K"}, "foreign": {"repNationCd": "F"}, "indie": {"multiMovieYn": "Y"}}


def _man(n: int) -> str:
    """관객 수 → "13.9만" / "2,884만" / "8,200"(1만 미만은 그대로)"""
    if n >= 10000:
        v = n / 10000
        return f"{v:,.1f}만" if v < 100 else f"{v:,.0f}만"
    return f"{n:,}"


def _get(path: str, **params) -> dict:
    r = requests.get(BASE + path, params={"key": config.get_key("KOBIS_KEY"), **params}, timeout=20)
    r.raise_for_status()
    return r.json()


def _item(m: dict, when: str) -> dict:
    inten = int(m.get("rankInten") or 0)
    new = m.get("rankOldAndNew") == "NEW"
    tag = " · 신규" if new else (f" · ▲{inten}" if inten > 0 else (f" · ▼{-inten}" if inten < 0 else ""))
    audi, acc = int(m["audiCnt"]), int(m["audiAcc"])
    return {
        "rank": int(m["rank"]),
        "code": m["movieCd"],
        "title": m["movieNm"],
        "audi": audi,
        "acc": acc,
        "scrn": int(m.get("scrnCnt") or 0),
        "show": int(m.get("showCnt") or 0),
        "share": float(m.get("salesShare") or 0),
        "sales": int(m.get("salesAmt") or 0),
        "open": m.get("openDt") or "",
        "inten": inten,
        "new": new,
        "meta": f"{when} {_man(audi)}명 · 누적 {_man(acc)}명{tag}",
    }


def _list(period: str, flt: str, day: date) -> tuple[list[dict], str]:
    """(항목 목록, 기간 문구). period: daily|weekly|weekend. 집계가 아직 없으면 빈 목록."""
    extra = FILTERS[flt]
    if period == "daily":
        res = _get("boxoffice/searchDailyBoxOfficeList.json", targetDt=day.strftime("%Y%m%d"), **extra).get("boxOfficeResult") or {}
        rows = res.get("dailyBoxOfficeList") or []
        label = f"{day.month}/{day.day}"
        when = "어제" if day == date.today() - timedelta(days=1) else label
    else:
        week_day = date.today() - timedelta(days=7)
        res = _get("boxoffice/searchWeeklyBoxOfficeList.json", targetDt=week_day.strftime("%Y%m%d"), weekGb="0" if period == "weekly" else "1", **extra).get("boxOfficeResult") or {}
        rows = res.get("weeklyBoxOfficeList") or []
        m = re.match(r"(\d{4})(\d{2})(\d{2})~(\d{4})(\d{2})(\d{2})", str(res.get("showRange") or ""))
        label = f"{int(m.group(2))}/{int(m.group(3))}~{int(m.group(5))}/{int(m.group(6))}" if m else ""
        when = "주간" if period == "weekly" else "주말"
    return [_item(x, when) for x in rows[:10]], label


def run() -> dict:
    # 어제 집계가 아직 안 올라왔으면(새벽) 그제로
    day = date.today() - timedelta(days=1)
    probe, _ = _list("daily", "all", day)
    if not probe:
        day -= timedelta(days=1)

    sets: dict[str, list[dict]] = {}
    ranges: dict[str, str] = {}
    for period in ("daily", "weekly", "weekend"):
        for flt in FILTERS:
            try:
                items, label = _list(period, flt, day)
            except Exception:
                items, label = [], ""
            sets[f"{period}|{flt}"] = items
            if label:
                ranges[period] = label
    daily = sets.get("daily|all") or []
    if not daily:
        raise RuntimeError("박스오피스 없음")

    # 최근 7일 안에 개봉한 영화(일별·주간·한국·외국 목록을 합쳐 중복 제거)
    since = (date.today() - timedelta(days=7)).strftime("%Y-%m-%d")
    seen: dict[str, dict] = {}
    for key in ("daily|all", "weekly|all", "daily|kr", "daily|foreign", "daily|indie"):
        for it in sets.get(key, []):
            if it["open"] and it["open"] >= since and it["code"] not in seen:
                seen[it["code"]] = it
    new_releases = sorted(seen.values(), key=lambda x: x["open"], reverse=True)[:8]

    top = daily[0]
    when = "어제" if day == date.today() - timedelta(days=1) else f"{day.month}/{day.day}"
    return {
        "box_office": [{"rank": it["rank"], "title": it["title"], "meta": it["meta"], "code": it["code"]} for it in daily],
        "box_office_sets": sets,
        "box_office_ranges": ranges,
        "box_office_date": day.isoformat(),
        "new_releases": new_releases,
        "hero": {
            "theme": "culture",
            "label": f"{when} 박스오피스 1위",
            "title": top["title"],
            "poster": None,
            "rank": 1,
            "stat_label": "누적 관객",
            "stat": f"{_man(top['acc'])}명",
            "source": "영화진흥위원회 영화관입장권통합전산망",
        },
    }


def region_items(sido_code: str | None) -> dict | None:
    """선택한 시도의 일별 박스오피스 TOP 10(3시간 캐시). 키가 없거나 실패하면 None."""
    if not config.get_key("KOBIS_KEY"):
        return None
    name = geo.region(sido_code)["name"]
    wide = WIDE_AREA.get(name)
    if not wide:
        return None

    def fetch() -> dict:
        for back in (1, 2):
            day = date.today() - timedelta(days=back)
            res = _get("boxoffice/searchDailyBoxOfficeList.json", targetDt=day.strftime("%Y%m%d"), wideAreaCd=wide).get("boxOfficeResult") or {}
            rows = res.get("dailyBoxOfficeList") or []
            if rows:
                when = "어제" if back == 1 else f"{day.month}/{day.day}"
                return {"name": name, "items": [_item(x, when) for x in rows[:10]]}
        return {"name": name, "items": []}

    try:
        out = _cache.cached("kobis_region", f"kobis_region:{wide}", 180, fetch)
    except Exception:
        return None
    return out if out.get("items") else None


def detail(code: str) -> dict:
    """영화 상세(감독·출연·장르·상영시간·등급·제작국). 7일 캐시."""
    if not re.fullmatch(r"\d{6,10}", code or "") or not config.get_key("KOBIS_KEY"):
        return {"found": False}

    def fetch() -> dict:
        i = (_get("movie/searchMovieInfo.json", movieCd=code).get("movieInfoResult") or {}).get("movieInfo") or {}
        if not i:
            return {"found": False}
        open_dt = i.get("openDt") or ""
        return {
            "found": True,
            "code": code,
            "title": i.get("movieNm") or "",
            "title_en": i.get("movieNmEn") or "",
            "runtime": int(i["showTm"]) if str(i.get("showTm") or "").isdigit() else None,
            "open": f"{open_dt[:4]}-{open_dt[4:6]}-{open_dt[6:8]}" if len(open_dt) == 8 else "",
            "genres": [g["genreNm"] for g in i.get("genres", [])],
            "directors": [d["peopleNm"] for d in i.get("directors", [])][:3],
            "actors": [a["peopleNm"] for a in i.get("actors", [])][:6],
            "grade": next((a["watchGradeNm"] for a in i.get("audits", []) if a.get("watchGradeNm")), ""),
            "nations": [n["nationNm"] for n in i.get("nations", [])],
            "source": "영화진흥위원회 영화관입장권통합전산망",
        }

    try:
        return _cache.cached("kobis_movie", f"kobis_movie:{code}", 7 * 24 * 60, fetch)
    except Exception:
        return {"found": False}


jobs.register(jobs.Job(name="boxoffice", run=run, env_keys=["KOBIS_KEY"], interval_min=180))
