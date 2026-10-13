# -*- coding: utf-8 -*-
"""문화 탭 "이번 주말 한산한 곳": 한국관광공사 관광지 집중률 방문자 추이 예측 정보(공공데이터포털, 이용허락범위 제한 없음).

 - 엔드포인트: apis.data.go.kr/B551011/TatsCnctrRateService/tatsCnctrRatedList  (areaCd + signguCd 둘 다 필수, MobileOS·MobileApp 필요)
 - 시군구 코드(5자리)는 TourAPI `ldongCode2`(법정동코드)에서 받음: 시도 코드 2자리 + 시군구 3자리.
 - 값은 오늘부터 약 30일 뒤까지의 예측이고, 관광지별 "집중률"(0~100, 높을수록 몰림). 사람 수가 아니라 그 장소의 평소 방문 대비 지수로 보임
   (포털 활용가이드로 정의를 다시 확인할 것) → 화면엔 "그 관광지 기준 예상 집중도"라고 설명함.
 - 일 호출 한도 1,000이라, 지역을 고른 사용자 요청이 올 때 그 지역 시군구만 병렬로 받고 24시간 캐시함(서울 25곳을 병렬로 받아 약 5~8초 — 그래서 화면은 이 요청을 따로 불러 문화 탭 본문을 막지 않음).
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta

import requests

import config
import geo
import jobs
from sources import _cache, _http, _kst

CROWD_URL = "https://apis.data.go.kr/B551011/TatsCnctrRateService/tatsCnctrRatedList"


def _tour_params() -> dict:
    return {
        "serviceKey": config.get_key(_http.KEY_ENV),
        "MobileOS": config.get_key("TOUR_API_MOBILE_OS"),
        "MobileApp": config.get_key("TOUR_API_MOBILE_APP"),
        "_type": "json",
    }


def available() -> bool:
    return config.has_keys([_http.KEY_ENV, "TOUR_API_BASE_URL", "TOUR_API_MOBILE_OS", "TOUR_API_MOBILE_APP"])


def _items(body: dict) -> list[dict]:
    it = ((body.get("response") or {}).get("body") or {}).get("items")
    if not it or it == "":
        return []
    rows = it.get("item") if isinstance(it, dict) else it
    return rows if isinstance(rows, list) else ([rows] if rows else [])


def _ldong(regn: str | None) -> list[dict]:
    """regn 없음 → 시도 목록, 있음 → 그 시도의 시군구 목록. [{code, name}]"""
    params = {**_tour_params(), "numOfRows": 300, "pageNo": 1}
    if regn:
        params["lDongRegnCd"] = regn
    r = requests.get(config.get_key("TOUR_API_BASE_URL") + "/ldongCode2", params=params, timeout=30)
    r.raise_for_status()
    return [{"code": str(i["code"]), "name": i["name"]} for i in _items(r.json())]


def _kto_regions() -> list[dict]:
    return _cache.cached("outing_codes", "outing:regions", 10080, lambda: {"v": _ldong(None)})["v"]


def _kto_signgu(regn: str) -> list[dict]:
    return _cache.cached("outing_codes", f"outing:signgu:{regn}", 10080, lambda: {"v": _ldong(regn)})["v"]


def _fetch_signgu(area: str, signgu: str) -> list[dict]:
    """한 시군구의 관광지×30일 예측을 한 번에(numOfRows를 크게 주면 한 번에 옴: 종로구 3,390건 1.1초)."""
    r = requests.get(CROWD_URL, params={**_tour_params(), "numOfRows": 10000, "pageNo": 1, "areaCd": area, "signguCd": area + signgu}, timeout=40)
    if r.status_code != 200:
        return []
    try:
        return _items(r.json())
    except ValueError:
        return []  # 해당 시군구에 데이터가 없으면 JSON이 아닌 응답이 올 수 있음


def kto_area_code(sido: str | None) -> str:
    """앱의 시도 → 한국관광공사 법정동 시도 코드(광주·전남은 통합특별시 12). 못 찾으면 빈 문자열."""
    region = geo.region(sido)
    prefixes = tuple(region.get("prefixes") or (region["name"],))
    kto = next((k for k in _kto_regions() if any(p in k["name"] for p in prefixes)), None)
    return kto["code"] if kto else ""


def _targets(sido: str | None, sgg: str | None) -> tuple[str, list[dict]]:
    """앱 지역 → (한국관광공사 시도 코드, 불러올 시군구 목록)."""
    region = geo.region(sido)
    prefixes = tuple(region.get("prefixes") or (region["name"],))
    kto = next((k for k in _kto_regions() if any(p in k["name"] for p in prefixes)), None)
    if not kto:
        return "", []
    app_names = [s["name"] for s in geo.sigungu_list(region["code"])]
    want = [sgg] if sgg else app_names  # 시군구를 골랐으면 그곳만, 아니면 시도 전체

    def ok(name: str) -> bool:
        # "성남시 분당구"는 앱의 "성남시"/"분당구" 어느 쪽으로 골라도 맞게
        return any(name == w or name.startswith(w + " ") or name.endswith(" " + w) for w in want)

    return kto["code"], [s for s in _kto_signgu(kto["code"]) if ok(s["name"])]


def _build(sido: str | None, sgg: str | None) -> dict:
    area, signgu = _targets(sido, sgg)
    if not signgu:
        raise RuntimeError("집중률 지역 코드를 못 찾음")
    spots: dict[tuple[str, str], dict[str, float]] = {}
    with ThreadPoolExecutor(max_workers=10) as ex:
        for rows in ex.map(lambda s: _fetch_signgu(area, s["code"]), signgu):
            for x in rows:
                try:
                    spots.setdefault((x.get("signguNm") or "", x.get("tAtsNm") or ""), {})[x["baseYmd"]] = float(x["cnctrRate"])
                except (KeyError, ValueError, TypeError):
                    continue
    if not spots:
        raise RuntimeError("집중률 데이터 없음")
    return {"spots": [{"g": g, "n": n, "r": r} for (g, n), r in spots.items()], "at": datetime.now().isoformat(timespec="minutes")}


def get(sido: str | None, sgg: str | None = None) -> dict | None:
    if not available():
        return None
    region = geo.region(sido)
    key = f"outing3:{region['code']}:{sgg or '*'}"
    try:
        return _cache.cached("outing", key, 1440, lambda: _build(sido, sgg))
    except Exception:
        return None


def weekend_days(today: date) -> list[date]:
    """이번 주말: 일요일이면 오늘 하루, 아니면 이번 주 토·일."""
    if today.weekday() == 6:
        return [today]
    sat = today + timedelta(days=(5 - today.weekday()) % 7)
    return [sat, sat + timedelta(days=1)]


def weekend(sido: str | None, sgg: str | None, weekly: list[dict], limit: int = 12) -> dict:
    """토·일별 "예상 집중도가 낮은 관광지" 목록 + 그날 날씨(주간 날씨에서)."""
    data = get(sido, sgg)
    if not data:
        return {"live": False, "days": []}
    today = _kst.today()
    days = []
    for d in weekend_days(today):
        ymd = d.strftime("%Y%m%d")
        rows = [(s["r"][ymd], s["n"], s["g"]) for s in data["spots"] if ymd in s["r"]]
        if not rows:
            continue
        rows.sort()
        wd = next((w for w in weekly if w.get("date") == f"{d.month}/{d.day}"), None)
        days.append(
            {
                "date": d.isoformat(),
                "label": "월화수목금토일"[d.weekday()],
                "md": f"{d.month}/{d.day}",
                "avg": round(sum(r for r, _, _ in rows) / len(rows), 1),
                "weather": {"condition": wd["condition"], "high": wd["high"], "low": wd["low"], "pop": wd.get("pop")} if wd else None,
                "spots": [{"name": n, "sgg": g, "rate": round(r)} for r, n, g in rows[:limit]],
                "count": len(rows),
            }
        )
    if not days:
        return {"live": False, "days": []}
    return {"live": True, "days": days, "at": data["at"], "region": geo.place(sido, sgg)["label"]}


def _warm() -> dict:
    get("11", None)  # 기본 지역(서울)은 미리 데워 둠
    return {"ok": True}


jobs.register(jobs.Job(name="outing_warm", run=_warm, env_keys=[_http.KEY_ENV], interval_min=720))
