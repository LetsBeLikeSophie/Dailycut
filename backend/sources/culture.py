# -*- coding: utf-8 -*-
"""문화 수집: 한국관광공사 TourAPI(축제·행사) + 한국문화정보원(전시·공연).

두 API 모두 전국 목록을 한 번에 받아(2시간 캐시) 고른 지역(시군구 → 없으면 시도)에 맞게 거름.
- events: 이번 달~다음 2주 행사 전부(달력용). {id, kind, title, start, end, place, sigungu, local, image}
- festivals / performances: 곧 열리는 축제·진행 중인 전시·공연 6곳씩(목록용, 예전 모양 + id)
- culture_scope: 어느 범위로 채웠는지(화면 꼬리표용)
- detail(id): 눌렀을 때 보여줄 상세(기간·장소·요금·설명 등). id는 "k:<문화정보원 seq>" 또는 "t:<관광공사 contentid>".
박스오피스(KOBIS)와 음악 순위(Spotify·YouTube)는 키가 없어서 스텁 그대로.
"""

from __future__ import annotations

import html
import re
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta

import config
import geo
import jobs
import store
from sources import _cache, _http

IMAGE_HOSTS = ("tong.visitkorea.or.kr",)  # 사진을 대신 받아 전달하는 호스트(api.py의 /proxy/image)


def available() -> bool:
    return config.has_keys([_http.KEY_ENV, "TOUR_API_BASE_URL", "TOUR_API_MOBILE_OS", "TOUR_API_MOBILE_APP", "KCISA_CULTURE_BASE_URL"])


def _md(s: str) -> str:
    d = datetime.strptime(s, "%Y%m%d")
    return f"{d.month}.{d.day}"


def _iso(s: str) -> str:
    return datetime.strptime(s, "%Y%m%d").date().isoformat()


def _plain(text: str | None) -> str:
    """HTML(이중으로 이스케이프된 것 포함)을 평문으로. 문단은 줄바꿈으로 남김."""
    t = html.unescape(html.unescape(text or ""))
    t = re.sub(r"<\s*(br|/p|/div|/li)\s*/?>", "\n", t, flags=re.I)
    t = re.sub(r"<[^>]+>", "", t)
    t = html.unescape(t).replace("\xa0", " ")
    t = re.sub(r"[ \t]+", " ", t)
    return re.sub(r"\n\s*\n+", "\n\n", t).strip()


# ---------------- 전국 목록(캐시) ----------------

def _tour_all(today: datetime) -> list[dict]:
    """관광공사 축제·행사. 두 달 전부터 시작한 행사까지 받아 두고, 연중 상시(60일 넘는) 행사는 뺌."""

    def load() -> dict:
        body = _http.get_json(
            config.get_key("TOUR_API_BASE_URL") + "/searchFestival2",
            {
                "MobileOS": config.get_key("TOUR_API_MOBILE_OS"),
                "MobileApp": config.get_key("TOUR_API_MOBILE_APP"),
                "_type": "json",
                "eventStartDate": (today - timedelta(days=60)).strftime("%Y%m%d"),
                "numOfRows": 600,
                "pageNo": 1,
            },
        )
        rows = []
        for r in _http.items_of(body):
            try:
                span = (datetime.strptime(r["eventenddate"], "%Y%m%d") - datetime.strptime(r["eventstartdate"], "%Y%m%d")).days
            except (KeyError, ValueError):
                continue
            if span <= 60:
                rows.append(r)
        return {"rows": rows}

    return _cache.cached("culture", f"culture:tour:{today.strftime('%Y%m%d')}", 120, load)["rows"]


def _kcisa_all(today: datetime) -> list[dict]:
    """한국문화정보원 이번 달 1일 ~ 45일 뒤 전시·공연 전국 목록. 시도 필터 파라미터가 먹지 않아서 전부 받아 코드에서 거름.
    한 번에 100건(numOfrows, 소문자 r 주의)씩 10여 번 호출이라 2시간 캐시해서 모든 지역이 함께 씀."""
    base = config.get_key("KCISA_CULTURE_BASE_URL")
    start = today.replace(day=1)

    def load() -> dict:
        rows, page = [], 1
        while page <= 25:
            r = _http.get(
                base + "/period2",
                {"from": start.strftime("%Y%m%d"), "to": (today + timedelta(days=45)).strftime("%Y%m%d"), "cPage": page, "numOfrows": 100},
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


# ---------------- 정리 ----------------

def _event_tour(r: dict, place: dict) -> dict | None:
    code = geo.sido_of_address(r.get("addr1"))
    if code != place["code"]:
        return None
    parts = (r.get("addr1") or "").split()
    sigungu = parts[1] if len(parts) > 1 else ""
    return {
        "id": f"t:{r['contentid']}",
        "kind": "축제",
        "title": html.unescape(r["title"]),
        "start": _iso(r["eventstartdate"]),
        "end": _iso(r["eventenddate"]),
        "place": (r.get("addr2") or "").strip() or " ".join(parts[:3]),
        "sigungu": sigungu,
        "local": bool(place["names"]) and sigungu in place["names"],
        "image": r.get("firstimage") if r.get("cpyrhtDivCd") == "Type1" else None,
    }


def _event_kcisa(r: dict, place: dict) -> dict | None:
    if r.get("area") != place["air"]:  # 한국문화정보원도 "서울/부산/경기…" 짧은 시도명
        return None
    try:
        start, end = _iso(r["startDate"]), _iso(r["endDate"])
    except (KeyError, ValueError):
        return None
    sigungu = r.get("sigungu", "")
    return {
        "id": f"k:{r['seq']}",
        "kind": r.get("realmName") or r.get("serviceName") or "전시·공연",
        "title": html.unescape(r["title"]),
        "start": start,
        "end": end,
        "place": r.get("place", ""),
        "sigungu": sigungu,
        "local": bool(place["names"]) and sigungu in place["names"],
        "image": None,  # 문화포털 사진은 저작권 구분이 없어 광고(상업 이용) 대비로 쓰지 않음(2026-10-13)
    }


def _build(code: str, sgg: str | None) -> dict:
    place = geo.place(code, sgg)
    today = datetime.now()
    month_start = today.replace(day=1).date().isoformat()
    window_end = (today + timedelta(days=45)).date().isoformat()
    out: dict = {}
    events: list[dict] = []
    errors = []
    try:
        events += [e for e in (_event_tour(r, place) for r in _tour_all(today)) if e]
    except Exception as e:
        errors.append(f"tour: {e}")
    try:
        seen = set()
        for r in _kcisa_all(today):
            e = _event_kcisa(r, place)
            if e and e["id"] not in seen:
                seen.add(e["id"])
                events.append(e)
    except Exception as e:
        errors.append(f"kcisa: {e}")
    if not events:
        raise RuntimeError("; ".join(errors) or "행사 없음")

    events = [e for e in events if e["end"] >= month_start and e["start"] <= window_end]
    events.sort(key=lambda e: (not e["local"], e["start"], e["title"]))
    out["events"] = events[:300]

    t0, t_fest, t_perf = today.date().isoformat(), (today + timedelta(days=9)).date().isoformat(), (today + timedelta(days=7)).date().isoformat()

    def short(e: dict) -> dict:
        bits = [f"{e['start'][5:].replace('-', '.').lstrip('0')}~{e['end'][5:].replace('-', '.').lstrip('0')}", e["sigungu"]] if e["kind"] == "축제" else [
            e["place"], f"~{e['end'][5:].replace('-', '.').lstrip('0')}", e["sigungu"]
        ]
        return {"id": e["id"], "title": e["title"], "meta": " · ".join(b for b in bits if b), "local": e["local"]}

    fest = [e for e in events if e["kind"] == "축제" and e["end"] >= t0 and e["start"] <= t_fest and (e["end"] != e["start"] or True)]
    perf = [e for e in events if e["kind"] != "축제" and e["end"] >= t0 and e["start"] <= t_perf]
    out["festivals"] = [short(e) for e in fest[:6]]
    out["performances"] = [short(e) for e in perf[:6]]
    out["culture_scope"] = {
        "label": place["label"],
        "sgg": place["sgg"],
        "sido": place["sido"],
        "festivals": {"local": sum(1 for r in out["festivals"] if r["local"]), "total": len(out["festivals"])},
        "performances": {"local": sum(1 for r in out["performances"] if r["local"]), "total": len(out["performances"])},
        "events": {"local": sum(1 for e in out["events"] if e["local"]), "total": len(out["events"])},
    }
    return out


def peek(code: str, sgg: str | None = None) -> dict | None:
    """캐시에 이미 있는 값만(만료됐어도) 돌려줌 — 없으면 새로 만들지 않고 None. 투데이처럼 빨라야 하는 곳용
    (get()은 캐시가 없거나 1시간이 지나면 행사 수집으로 20~30초 걸림)."""
    if not available():
        return None
    pl = geo.place(code, sgg)
    hit = store.load_cache(f"cr2:{pl['key']}")
    return hit[0] if hit else None


def get(code: str, sgg: str | None = None) -> dict | None:
    """지역별 캐시된 문화 정보(달력 행사 + 목록). 키/수집 실패 시 None → 스텁."""
    if not available():
        return None
    pl = geo.place(code, sgg)
    try:
        return _cache.cached("culture_region", f"cr2:{pl['key']}", 60, lambda: _build(pl["code"], pl["sgg"]))
    except Exception:
        return None


# ---------------- 상세 ----------------

def detail(event_id: str) -> dict:
    """행사 상세. 실패하면 found=False."""
    if not available() or ":" not in event_id:
        return {"found": False}
    kind, _, key = event_id.partition(":")

    def load() -> dict:
        if kind == "k":
            r = _http.get(config.get_key("KCISA_CULTURE_BASE_URL") + "/detail2", {"seq": key})
            root = ET.fromstring(r.content)
            items = [{c.tag: (c.text or "").strip() for c in it} for it in root.iter("item")]
            if not items:
                return {"found": False}
            d = items[0]
            return {
                "found": True,
                "title": html.unescape(d.get("title", "")),
                "period": f"{_iso(d['startDate'])} ~ {_iso(d['endDate'])}" if d.get("startDate") and d.get("endDate") else None,
                "place": d.get("place") or None,
                "address": " ".join(x for x in (d.get("area"), d.get("sigungu")) if x) or None,
                "price": d.get("price") or None,
                "text": _plain(d.get("contents1")) or None,
                "homepage": d.get("url") or d.get("placeUrl") or None,
                "tel": d.get("phone") or None,
                "image": None,  # 위와 같은 이유
                "credit": "문화포털(한국문화정보원)",
            }
        if kind == "t":
            base = config.get_key("TOUR_API_BASE_URL")
            common = {
                "MobileOS": config.get_key("TOUR_API_MOBILE_OS"),
                "MobileApp": config.get_key("TOUR_API_MOBILE_APP"),
                "_type": "json",
                "contentId": key,
            }
            c = (_http.items_of(_http.get_json(base + "/detailCommon2", common)) or [{}])[0]
            i = (_http.items_of(_http.get_json(base + "/detailIntro2", {**common, "contentTypeId": c.get("contenttypeid", "15")})) or [{}])[0]
            hp = re.search(r'href=["\']([^"\']+)', c.get("homepage") or "")
            period = None
            if i.get("eventstartdate") and i.get("eventenddate"):
                period = f"{_iso(i['eventstartdate'])} ~ {_iso(i['eventenddate'])}"
            text = "\n\n".join(x for x in (_plain(c.get("overview")), _plain(i.get("program")) and "프로그램\n" + _plain(i.get("program"))) if x)
            return {
                "found": True,
                "title": html.unescape(c.get("title", "")),
                "period": period,
                "place": i.get("eventplace") or None,
                "address": " ".join(x for x in (c.get("addr1"), c.get("addr2")) if x) or None,
                "price": i.get("usetimefestival") or None,
                "time": i.get("playtime") or None,
                "text": text or None,
                "homepage": hp.group(1) if hp else (c.get("homepage") if (c.get("homepage") or "").startswith("http") else None),
                "tel": c.get("tel") or i.get("sponsor1tel") or None,
                "image": c.get("firstimage") if c.get("cpyrhtDivCd") == "Type1" else None,
                "credit": "한국관광공사 TourAPI",
            }
        return {"found": False}

    try:
        return _cache.cached("culture_detail", f"cd:{event_id}", 60 * 24, load)
    except Exception:
        return {"found": False}


def warm() -> dict:
    """전국 행사 목록(관광공사 + 문화정보원 10여 쪽)을 미리 받아 캐시에 채움 — 지역별 요청이 처음 와도 기다리지 않게.
    목록 캐시(2시간)보다 짧은 100분마다 다시 채움."""
    today = datetime.now()
    return {"tour": len(_tour_all(today)), "kcisa": len(_kcisa_all(today))}


jobs.register(
    jobs.Job(
        name="culture_warm",
        run=warm,
        env_keys=[_http.KEY_ENV, "TOUR_API_BASE_URL", "TOUR_API_MOBILE_OS", "TOUR_API_MOBILE_APP", "KCISA_CULTURE_BASE_URL"],
        interval_min=100,
    )
)
