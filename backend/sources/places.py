# -*- coding: utf-8 -*-
"""문화 탭 "나들이" 구역: 도서관 열람실 빈자리 · 캠핑장 · 반려동물 동반 · 웰니스 · 걷기길.

모두 공공데이터포털 이용허락범위 "제한 없음"(2026-10-13 신청서 표기; 쓰기 전에 포털에서 다시 확인할 것). 같은 인증키.
 - 도서관(지역정보개발원 전국 통합 공공도서관): /B551982/plr_v2  info_v2(도서관 234곳) + rlt_rdrm_info_v2(열람실별 남은 좌석, 갱신 시각 totDt)
   → 갱신이 4시간 넘게 지난 열람실은 "실시간 아님"으로 보고 남은 좌석에 안 셈(도서관마다 연동 상태가 달라 1월에 멈춘 곳도 있음).
 - 캠핑(관광공사 고캠핑): /B551011/GoCamping/basedList 전체(약 3,100곳), 운영 중인 곳만.
 - 반려동물(관광공사 반려동물 동반여행): areaBasedList2 + lDongRegnCd, 관광지·문화시설·레포츠·숙박·음식점.
 - 웰니스(관광공사): areaBasedList + langDivCd=KOR + lDongRegnCd (전국 170곳).
 - 걷기길(관광공사 두루누비): courseList 전체(약 140코스), sigun 글자로 지역 거름.
사진은 쓰지 않음(사진 저작권 구분을 확인하기 전까지). 항목 모양은 청약·대출과 같게 {id,name,sub,tag,span,detail[[라벨,값]],url,link_label}.
"""

from __future__ import annotations

import html
import re
from urllib.parse import quote

import requests

import config
import geo
from sources import _cache, _http, _kst, outing

LIB_BASE = "https://apis.data.go.kr/B551982/plr_v2"
CAMP_URL = "https://apis.data.go.kr/B551011/GoCamping/basedList"
PET_URL = "https://apis.data.go.kr/B551011/KorPetTourService2/areaBasedList2"
WELL_URL = "https://apis.data.go.kr/B551011/WellnessTursmService/areaBasedList"
TRAIL_URL = "https://apis.data.go.kr/B551011/Durunubi/courseList"

KINDS = ("library", "camp", "pet", "wellness", "trail")
CONTENT_TYPE = {"12": "관광지", "14": "문화시설", "28": "레포츠", "32": "숙박", "39": "음식점", "38": "쇼핑"}


def _clean(v) -> str:
    t = html.unescape(str(v or ""))
    t = re.sub(r"<br\s*/?>", " ", t, flags=re.I)
    t = re.sub(r"<[^>]+>", "", t)
    return re.sub(r"\s+", " ", t).strip()


def _tour() -> dict:
    return {
        "serviceKey": config.get_key(_http.KEY_ENV),
        "MobileOS": config.get_key("TOUR_API_MOBILE_OS"),
        "MobileApp": config.get_key("TOUR_API_MOBILE_APP"),
        "_type": "json",
    }


def _rows(body: dict) -> list[dict]:
    it = ((body.get("response") or {}).get("body") or {}).get("items")
    if not it:
        return []
    it = it.get("item") if isinstance(it, dict) else it
    return it if isinstance(it, list) else ([it] if it else [])


def _map(name: str) -> str:
    return "https://map.naver.com/p/search/" + quote(name)


def _pin(name: str, lat, lng, q: str | None = None) -> dict:
    """앱이 지도 앱(카카오맵·네이버지도·구글지도)별 링크를 만들 재료. 좌표가 한국 안이면 좌표 핀, 아니면 검색어(q, 없으면 이름)로.
    2026-10-16: 이름만 검색하면 흔하지 않은 이름은 엉뚱한 목록이 떠서 좌표가 있는 곳은 핀으로 보내고, 지도 앱은 사용자가 고름."""
    try:
        la, lo = float(lat), float(lng)
    except (TypeError, ValueError):
        la = lo = 0.0
    pin = {"name": name, "q": q or name}
    if 33 <= la <= 39 and 124 <= lo <= 132:
        pin.update({"lat": round(la, 6), "lng": round(lo, 6)})
    return pin


def _in_region(text: str, region: dict) -> bool:
    prefixes = tuple(region.get("prefixes") or (region["name"],))
    return any(p in text for p in prefixes)


def _has(terms: list[str], *texts) -> bool:
    hay = " ".join(str(t or "") for t in texts)
    return any(t in hay for t in terms)


def _scope(rows: list, sgg: str | None, region: dict) -> tuple[list, str, str | None]:
    """시군구를 골랐고 그 시군구 항목이 있으면 그것만, 없으면 시도 전체(안내 글 포함). rows의 첫 칸은 0=그 시군구, 1=그 밖."""
    base = region["name"]
    if not sgg:
        return rows, base, None
    near = [r for r in rows if r[0] == 0]
    if near:
        return near, f"{base} {sgg}", None
    return rows, base, f"{sgg}에는 없어서 {base} 전체를 보여드려요."


def _item(id_: str, name: str, sub: str, tag: str, span: str, detail: list[tuple[str, str | None]], url: str, link_label: str, pin: dict | None = None) -> dict:
    return {
        "id": id_, "name": name, "sub": sub, "tag": tag, "span": span,
        "detail": [[k, str(v)] for k, v in detail if v not in (None, "", "0")],
        "url": url, "link_label": link_label, "pin": pin,
    }


# ---------------- 도서관 ----------------


def _lib_info() -> list[dict]:
    r = requests.get(LIB_BASE + "/info_v2", params={"serviceKey": config.get_key(_http.KEY_ENV), "pageNo": 1, "numOfRows": 400, "type": "json"}, timeout=40)
    r.raise_for_status()
    return (r.json().get("body") or {}).get("item") or []


def _lib_rooms() -> list[dict]:
    r = requests.get(LIB_BASE + "/rlt_rdrm_info_v2", params={"serviceKey": config.get_key(_http.KEY_ENV), "pageNo": 1, "numOfRows": 600, "type": "json"}, timeout=40)
    r.raise_for_status()
    return (r.json().get("body") or {}).get("item") or []


def _hhmm(t: str) -> str:
    t = re.sub(r"\D", "", t or "")
    return f"{t[:2]}:{t[2:4]}" if len(t) >= 4 else ""


def _fresh(tot_dt: str, hours: int = 4) -> bool:
    d = re.sub(r"\D", "", tot_dt or "")
    if len(d) < 12:
        return False
    from datetime import datetime, timedelta

    try:
        t = datetime.strptime(d[:12], "%Y%m%d%H%M")
    except ValueError:
        return False
    return _kst.now() - t <= timedelta(hours=hours)


def library(sido: str | None, sgg: str | None) -> dict:
    info = _cache.cached("places", "places:lib:info", 1440, lambda: {"v": _lib_info()})["v"]
    rooms = _cache.cached("places", "places:lib:rooms", 10, lambda: {"v": _lib_rooms()})["v"]
    region = geo.region(sido)
    # 도서관 번호(PLR001…)는 지자체마다 겹쳐서(광진·강북이 모두 PLR001) 지자체 코드 + 이름으로 짝지음
    by_lib: dict[tuple[str, str], list[dict]] = {}
    for r in rooms:
        by_lib.setdefault((r.get("stdgCd") or "", _clean(r.get("pblibNm"))), []).append(r)
    wd = _kst.today().weekday()
    terms = geo.sgg_terms(sido, sgg)
    out = []
    for lib in info:
        if not _in_region(lib.get("ctpvNm") or "", region):
            continue
        rs = by_lib.get((lib.get("stdgCd") or "", _clean(lib.get("pblibNm"))), [])
        fresh = [r for r in rs if _fresh(r.get("totDt", ""))]
        remain = sum(int(r["rmndSeatCnt"]) for r in fresh if str(r.get("rmndSeatCnt", "")).isdigit())
        total = sum(int(r["tseatCnt"]) for r in fresh if str(r.get("tseatCnt", "")).isdigit())
        a, b = (lib.get("wkdyOperBgngTm"), lib.get("wkdyOperEndTm")) if wd < 5 else (lib.get("wknd" + "OperBgngTm"), lib.get("wkndOperEndTm"))
        opens = f"{_hhmm(a)}~{_hhmm(b)}" if _hhmm(a) and _hhmm(b) else ""
        hm = _kst.now().strftime("%H:%M")
        closed_now = bool(opens) and not (_hhmm(a) <= hm < _hhmm(b))  # 운영 시간 밖이면 남은 좌석 대신 "운영 종료"
        room_lines = "\n".join(
            f"{r.get('rdrmNm') or '열람실'}" + (f" · {r['bldgFlrExpln']}" if r.get("bldgFlrExpln") else "") + (f" — {r['rmndSeatCnt']}/{r['tseatCnt']}석 남음" if _fresh(r.get("totDt", "")) else " — 실시간 정보 없음")
            for r in rs[:8]
        )
        near = _has(terms, lib.get("sggNm"), lib.get("pblibRoadNmAddr"))
        item = _item(
            f"lb{lib.get('stdgCd')}{lib['pblibId']}",
            _clean(lib.get("pblibNm")),
            " · ".join(x for x in (lib.get("sggNm"), lib.get("pblibTypeNm")) if x),
            ("운영 종료" if closed_now else (f"{remain}석 남음" if fresh else "")),
            ("오늘 " + opens) if opens else "",
            [
                ("열람실", room_lines or None),
                ("남은 좌석", f"{remain}/{total}석 (갱신 4시간 안의 열람실만 합산)" if fresh else "실시간 정보가 연결돼 있지 않거나 오래됐어요"),
                ("운영 시간", f"평일 {_hhmm(lib.get('wkdyOperBgngTm'))}~{_hhmm(lib.get('wkdyOperEndTm'))} · 주말 {_hhmm(lib.get('wkndOperBgngTm'))}~{_hhmm(lib.get('wkndOperEndTm'))}" if _hhmm(lib.get("wkdyOperBgngTm")) else None),
                ("휴관", _clean(lib.get("clsrInfoExpln"))),
                ("주소", _clean(lib.get("pblibRoadNmAddr"))),
                ("전화", lib.get("pblibTelno")),
            ],
            lib.get("siteUrlAddr") or "",
            "도서관 누리집",
            _pin(_clean(lib.get("pblibNm")), lib.get("lat"), lib.get("lot"), _clean(lib.get("pblibRoadNmAddr")) or None),
        )
        out.append((0 if near else 1, 0 if fresh else 1, -remain, item["name"], item))
    out.sort(key=lambda t: t[:4])
    out, label, scope_note = _scope(out, sgg, region)
    return {"live": True, "total": len(out), "items": [t[4] for t in out], "region": label, "scope_note": scope_note, "note": "열람실 남은 좌석은 도서관이 보내 주는 값이고, 갱신이 오래된 곳은 빼고 보여요."}


# ---------------- 캠핑 ----------------


def _camps() -> list[dict]:
    out: list[dict] = []
    for page in range(1, 6):
        r = requests.get(CAMP_URL, params={**_tour(), "numOfRows": 1000, "pageNo": page}, timeout=60)
        r.raise_for_status()
        rows = _rows(r.json())
        out += [x for x in rows if x.get("manageSttus") == "운영"]
        if len(rows) < 1000:
            break
    return out


def camp(sido: str | None, sgg: str | None) -> dict:
    camps = _cache.cached("places", "places:camps", 1440, lambda: {"v": _camps()})["v"]
    region = geo.region(sido)
    terms = geo.sgg_terms(sido, sgg)
    out = []
    for c in camps:
        if not _in_region(c.get("doNm") or "", region):
            continue
        sites = [
            f"{label} {c[k]}" for k, label in (("gnrlSiteCo", "일반"), ("autoSiteCo", "자동차"), ("glampSiteCo", "글램핑"), ("caravSiteCo", "카라반"), ("indvdlCaravSiteCo", "개인카라반")) if str(c.get(k) or "0") not in ("", "0")
        ]
        near = _has(terms, c.get("sigunguNm"), c.get("addr1"))
        pet = _clean(c.get("animalCmgCl"))
        item = _item(
            f"cp{c['contentId']}",
            _clean(c.get("facltNm")),
            " · ".join(x for x in (c.get("sigunguNm"), _clean(c.get("induty")).split(",")[0], _clean(c.get("lctCl"))) if x),
            f"반려동물 {pet}" if pet in ("가능", "가능(소형견)") else "",
            " · ".join(sites[:2]),
            [
                ("소개", _clean(c.get("lineIntro")) or _clean(c.get("intro"))[:160]),
                ("사이트", ", ".join(sites)),
                ("운영", " · ".join(x for x in (_clean(c.get("operPdCl")), _clean(c.get("operDeCl"))) if x)),
                ("반려동물", pet),
                ("부대시설", _clean(c.get("sbrsCl"))),
                ("주변 즐길 거리", _clean(c.get("posblFcltyCl"))),
                ("예약", _clean(c.get("resveCl"))),
                ("주소", _clean(c.get("addr1"))),
                ("전화", _clean(c.get("tel"))),
            ],
            c.get("resveUrl") or c.get("homepage") or "",
            "예약·누리집 보기",
            _pin(_clean(c.get("facltNm")), c.get("mapY"), c.get("mapX"), _clean(c.get("addr1")) or None),
        )
        out.append((0 if near else 1, item["name"], item))
    out.sort(key=lambda t: t[:2])
    out, label, scope_note = _scope(out, sgg, region)
    return {"live": True, "total": len(out), "items": [t[2] for t in out[:150]], "region": label, "scope_note": scope_note, "note": "운영 중인 캠핑장만이에요. 예약·운영 여부는 누리집에서 꼭 확인해 주세요."}


# ---------------- 반려동물 · 웰니스 ----------------


def _tour_area(sido: str | None) -> str:
    area = outing.kto_area_code(sido)
    if not area:
        raise RuntimeError("관광공사 지역 코드를 못 찾음")
    return area


def _pet(area: str) -> list[dict]:
    out: list[dict] = []
    for ct in ("12", "14", "28", "32", "39"):
        r = requests.get(PET_URL, params={**_tour(), "lDongRegnCd": area, "contentTypeId": ct, "numOfRows": 300, "pageNo": 1}, timeout=40)
        if r.status_code == 200:
            try:
                out += _rows(r.json())
            except ValueError:
                pass
    return out


def pet(sido: str | None, sgg: str | None) -> dict:
    area = _tour_area(sido)
    rows = _cache.cached("places", f"places:pet:{area}", 1440, lambda: {"v": _pet(area)})["v"]
    region = geo.region(sido)
    terms = geo.sgg_terms(sido, sgg)
    out = []
    for x in rows:
        addr = _clean(x.get("addr1"))
        if not _in_region(addr[:14], region):
            continue
        near = _has(terms, addr)
        kind = CONTENT_TYPE.get(str(x.get("contenttypeid")), "")
        item = _item(
            f"pt{x['contentid']}", _clean(x.get("title")), " · ".join(p for p in (kind, addr) if p), "", "",
            [("종류", kind), ("주소", addr), ("전화", _clean(x.get("tel")))], "", "", _pin(_clean(x.get("title")), x.get("mapy"), x.get("mapx"), addr or None),
        )
        out.append((0 if near else 1, kind != "관광지", item["name"], item))
    out.sort(key=lambda t: t[:3])
    out, label, scope_note = _scope(out, sgg, region)
    return {"live": True, "total": len(out), "items": [t[3] for t in out[:150]], "region": label, "scope_note": scope_note, "note": "반려동물 동반 가능 여부와 조건(크기·종류 제한 등)은 방문 전에 시설에 확인해 주세요."}


def _wellness(area: str) -> list[dict]:
    r = requests.get(WELL_URL, params={**_tour(), "langDivCd": "KOR", "lDongRegnCd": area, "numOfRows": 300, "pageNo": 1}, timeout=40)
    r.raise_for_status()
    return _rows(r.json())


def wellness(sido: str | None, sgg: str | None) -> dict:
    area = _tour_area(sido)
    rows = _cache.cached("places", f"places:well:{area}", 1440, lambda: {"v": _wellness(area)})["v"]
    region = geo.region(sido)
    terms = geo.sgg_terms(sido, sgg)
    out = []
    for x in rows:
        addr = _clean(x.get("baseAddr"))
        if not _in_region(addr[:14], region):
            continue
        near = _has(terms, addr)
        kind = CONTENT_TYPE.get(str(x.get("contentTypeId")), "")
        item = _item(f"wl{x['contentId']}", _clean(x.get("title")), " · ".join(p for p in (kind, addr) if p), "", "", [("종류", kind), ("주소", addr)], "", "", _pin(_clean(x.get("title")), x.get("mapY"), x.get("mapX"), addr or None))
        out.append((0 if near else 1, item["name"], item))
    out.sort(key=lambda t: t[:2])
    out, label, scope_note = _scope(out, sgg, region)
    return {"live": True, "total": len(out), "items": [t[2] for t in out], "region": label, "scope_note": scope_note, "note": "한국관광공사가 선정한 웰니스 관광지예요(온천·스파·명상·자연치유 등)."}


# ---------------- 걷기길 ----------------


def _trails() -> list[dict]:
    r = requests.get(TRAIL_URL, params={**_tour(), "numOfRows": 500, "pageNo": 1}, timeout=60)
    r.raise_for_status()
    return _rows(r.json())


def trail(sido: str | None, sgg: str | None) -> dict:
    rows = _cache.cached("places", "places:trails", 1440, lambda: {"v": _trails()})["v"]
    region = geo.region(sido)
    terms = geo.sgg_terms(sido, sgg)
    out = []
    level = {"1": "쉬움", "2": "보통", "3": "어려움"}
    for x in rows:
        sigun = _clean(x.get("sigun"))
        if not _in_region(sigun, region):
            continue
        mins = int(x["crsTotlRqrmHour"]) if str(x.get("crsTotlRqrmHour") or "").isdigit() else 0
        dur = (f"{mins // 60}시간 " if mins >= 60 else "") + (f"{mins % 60}분" if mins % 60 else "") if mins else ""
        km = x.get("crsDstnc")
        near = _has(terms, sigun)
        item = _item(
            f"tr{x['crsIdx']}", _clean(x.get("crsKorNm")), " · ".join(p for p in (sigun, f"{km}km" if km else "", dur.strip()) if p), level.get(str(x.get("crsLevel")), ""), "",
            [("지역", sigun), ("거리", f"{km}km" if km else None), ("소요 시간", dur.strip()), ("난이도", level.get(str(x.get("crsLevel")))), ("형태", _clean(x.get("crsCycle"))),
             ("코스 소개", _clean(x.get("crsSummary"))[:300])],
            "", "", _pin(_clean(x.get("crsKorNm")), None, None, f"{sigun} {_clean(x.get('crsKorNm'))}".strip()),
        )
        out.append((0 if near else 1, item["name"], item))
    out.sort(key=lambda t: t[:2])
    out, label, scope_note = _scope(out, sgg, region)
    return {"live": True, "total": len(out), "items": [t[2] for t in out], "region": label, "scope_note": scope_note, "note": "한국관광공사 두루누비의 걷기길·자전거길 코스예요."}


def query(kind: str, sido: str | None, sgg: str | None) -> dict:
    fn = {"library": library, "camp": camp, "pet": pet, "wellness": wellness, "trail": trail}.get(kind)
    if not fn:
        return {"live": False, "items": []}
    try:
        return fn(sido, sgg)
    except Exception:
        return {"live": False, "items": []}


def _warm() -> dict:
    """사용자가 처음 열 때 기다리지 않게 하루 한 번 큰 목록(도서관·캠핑·걷기길, 서울의 반려동물·웰니스)을 미리 받아 둠."""
    for fn in (lambda: library("11", None), lambda: camp("11", None), lambda: trail("11", None), lambda: pet("11", None), lambda: wellness("11", None)):
        try:
            fn()
        except Exception:
            pass
    return {"ok": True}


import jobs  # noqa: E402

jobs.register(jobs.Job(name="places_warm", run=_warm, env_keys=[_http.KEY_ENV], interval_min=720))
