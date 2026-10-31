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

import re
import requests
from concurrent.futures import ThreadPoolExecutor, wait

import config
import geo
from sources import _cache, _http, _kst, outing

LIB_BASE = "https://apis.data.go.kr/B551982/plr_v2"
CAMP_URL = "https://apis.data.go.kr/B551011/GoCamping/basedList"
PET_URL = "https://apis.data.go.kr/B551011/KorPetTourService2/areaBasedList2"
PET_DETAIL_URL = "https://apis.data.go.kr/B551011/KorPetTourService2/detailPetTour2"
WELL_URL = "https://apis.data.go.kr/B551011/WellnessTursmService/areaBasedList"
TRAIL_URL = "https://apis.data.go.kr/B551011/Durunubi/courseList"
CLTR_URL = "https://apis.data.go.kr/B553457/rgnCltrFcltExmnv1"  # 한국문화정보원 전국문화기반시설총람(박물관 clifMsmv1·미술관 clifArglv1)

KINDS = ("library", "camp", "pet", "wellness", "trail", "museum", "hall")
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


_PET_POOL = ThreadPoolExecutor(max_workers=8)  # 응답을 돌려준 뒤에도 남은 상세를 계속 받음


def pet_level(text: str | None, kind_hint: str = "") -> dict | None:
    """"동반 가능 동물" 문구를 앱이 아이콘으로 보일 단계로 줄임(2026-10-16). level:
    small 소형견만 · mid 중·소형견(대형견 제외) · all 모든 크기 · guide 안내견·보조견만 · no 동반 불가 · other 조건 있음 · ok 동반 가능(크기 안내 없음).
    문구가 비어 있으면 None(아이콘을 안 붙임). 원문은 상세 시트에 그대로 보임."""
    raw = (text or "").strip()
    t = re.sub(r"\s+", "", raw)
    if not t:
        return None
    if "안내견" in t or "보조견" in t:
        return {"level": "guide", "label": "안내견·보조견만"}
    if t in ("불가", "불가능", "동반불가") or t.startswith("동반불가"):
        return {"level": "no", "label": "동반 불가"}
    if "대형견" in t and "제외" in t:
        return {"level": "mid", "label": "중·소형견"}
    if "소형견" in t or re.search(r"\d+(\.\d+)?kg(이하|미만)", t, re.I):
        return {"level": "small", "label": "소형견만"}
    if "전견종" in t or "전견동" in t or "모든견" in t or "크기제한없" in t:
        return {"level": "all", "label": "모든 크기"}
    if "고양이" in t:
        return {"level": "all", "label": "개·고양이"}
    return {"level": "other", "label": "조건 있음"}


def _pet_detail(cid: str) -> dict | None:
    """반려동물 동반여행 한 곳의 상세(동반 유형·가능 동물·필요 사항). 장소마다 한 번 받아 7일 보관(바뀔 일이 드묾). 실패하면 None."""

    def load() -> dict:
        r = requests.get(PET_DETAIL_URL, params={**_tour(), "contentId": cid}, timeout=20)
        r.raise_for_status()
        rows = _rows(r.json())
        return {"d": rows[0] if rows else None}

    try:
        return _cache.cached("pet_detail", f"petd:{cid}", 7 * 24 * 60, load)["d"]
    except Exception:
        return None


def _in_region(text: str, region: dict) -> bool:
    prefixes = tuple(region.get("prefixes") or (region["name"],))
    return any(p in text for p in prefixes)


def _has(terms: list[str], *texts) -> bool:
    hay = " ".join(str(t or "") for t in texts)
    return any(t in hay for t in terms)


def _scope(rows: list, sgg: str | None, region: dict) -> tuple[list, str, str | None]:
    """시군구를 골랐으면 그 시군구 항목만, 없으면 **비워서** 돌려줌(2026-10-16: 상위 시도 전체로 채우던 걸 뺌 — 앱이
    "다른 지역으로 찾아보세요"를 안내). 시도만 골랐으면 시도 전체. rows의 첫 칸은 0=그 시군구, 1=그 밖. 셋째 값은 앱이 쓸 안내(없으면 None)."""
    base = region["name"]
    if not sgg:
        return rows, base, None
    near = [r for r in rows if r[0] == 0]
    if near:
        return near, f"{base} {sgg}", None
    return [], f"{base} {sgg}", f"{sgg}에는 등록된 곳이 없어요."


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
    info = _cache.cached("places", "places:lib:info", 1440, lambda: {"v": _lib_info()}, shared=True)["v"]
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
    camps = _cache.cached("places", "places:camps", 1440, lambda: {"v": _camps()}, shared=True)["v"]
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
        pet_badge = {"level": "small", "label": "소형견만"} if pet == "가능(소형견)" else ({"level": "ok", "label": "동반 가능"} if pet == "가능" else None)
        item = _item(
            f"cp{c['contentId']}",
            _clean(c.get("facltNm")),
            " · ".join(x for x in (c.get("sigunguNm"), _clean(c.get("induty")).split(",")[0], _clean(c.get("lctCl"))) if x),
            "",
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
        if pet_badge:
            item["pet"] = pet_badge
        out.append((0 if near else 1, item["name"], item))
    out.sort(key=lambda t: t[:2])
    out, label, scope_note = _scope(out, sgg, region)
    return {"live": True, "total": len(out), "items": [t[2] for t in out[:150]], "region": label, "scope_note": scope_note, "note": "운영 중인 캠핑장만이에요. 예약·운영 여부는 누리집에서 꼭 확인해 주세요. 강아지 그림은 반려동물 동반 가능 표시예요(작은 한 마리는 소형견만, 회색은 크기 안내 없이 동반 가능)."}


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
    rows = _cache.cached("places", f"places:pet:{area}", 1440, lambda: {"v": _pet(area)}, shared=True)["v"]
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
    items = [t[3] for t in out[:150]]
    # 크기 구분은 상세 조회에만 있어서 장소마다 한 번 받아 7일 보관함. 처음 여는 지역이 오래 걸리지 않게 2.5초 안에 받은 것만
    # 이번 응답에 싣고, 나머지는 뒤에서 계속 받아 둠(다음에 열면 더 채워짐). 서울은 places_warm이 미리 받아 둠.
    ready: dict[str, dict | None] = {}
    futs = {}
    for it in items:
        cid = it["id"][2:]
        hit = _cache.peek(f"petd:{cid}", 7 * 24 * 60)  # 이미 받아 둔 건 바로(기다리지 않음)
        if hit is not None:
            ready[cid] = hit.get("d")
        else:
            futs[cid] = _PET_POOL.submit(_pet_detail, cid)
    wait(list(futs.values()), timeout=2.5)
    for cid, f in futs.items():
        if f.done():
            ready[cid] = f.result()
    details = [ready.get(it["id"][2:]) for it in items]
    for it, d in zip(items, details):
        if not d:
            continue
        it["pet"] = pet_level(d.get("acmpyPsblCpam")) or ({"level": "no", "label": "동반 불가"} if "불가" in (d.get("acmpyTypeCd") or "") else None)
        extra = [
            ("동반 유형", _clean(d.get("acmpyTypeCd"))),
            ("동반 가능 동물", _clean(d.get("acmpyPsblCpam"))),
            ("필요 사항", _clean(d.get("acmpyNeedMtr"))),
            ("참고", _clean(d.get("etcAcmpyInfo"))[:200]),
        ]
        it["detail"] += [[k, str(v)] for k, v in extra if v]
    return {"live": True, "total": len(out), "items": items, "region": label, "scope_note": scope_note, "note": "강아지 그림은 함께 갈 수 있는 크기예요: 작은 한 마리는 소형견만, 중간 한 마리는 중·소형견, 세 마리는 모든 크기. 회색은 안내견만이거나 조건이 따로 있는 곳이에요. 동반 가능 여부와 조건은 방문 전에 시설에 꼭 확인해 주세요."}


def _wellness(area: str) -> list[dict]:
    r = requests.get(WELL_URL, params={**_tour(), "langDivCd": "KOR", "lDongRegnCd": area, "numOfRows": 300, "pageNo": 1}, timeout=40)
    r.raise_for_status()
    return _rows(r.json())


def wellness(sido: str | None, sgg: str | None) -> dict:
    area = _tour_area(sido)
    rows = _cache.cached("places", f"places:well:{area}", 1440, lambda: {"v": _wellness(area)}, shared=True)["v"]
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


# ---------------- 박물관·미술관 ----------------
# 2026-10-31: 한국문화정보원 전국문화기반시설총람(지역문화통합정보시스템, 공공누리 1유형 = 출처표시, 상업 이용 가능 — 포털 15125097에서 확인).
#  - 발간연도(pblshYr)가 필수라서 가장 최근 연도를 위에서부터 찾음(2026-10 기준 2024 발간 = 2023년 조사). 시군구 코드를 안 주면 전국이 오고(박물관 약 1,000곳), 하루 한 번 전체를 받아 둠.
#  - 좌표·운영 시간은 없음 → 지도는 "주소"로 검색하는 링크. 연 개관일수·관람객은 총람 조사값이라 "○○년 조사"라고 밝힘.
#  - 키는 다른 소스와 같은 공공데이터포털 인증키. (처음엔 옛 주소 cultureartspaces/museum으로 불러서 키 미등록 오류가 났었음.)

# kind → [(오퍼레이션, 화면 구분 이름, 이름 필드, 설립·운영 필드, 주소 필드)]. 지방문화원·문화의집·지역문화재단·국립/공공도서관은 기관 통계 위주라(도서관은 열람실 실시간 좌석을
# 지역정보개발원에서 따로 받음) 방문자용 목록에서는 뺌.
_CLTR_KINDS = {
    "museum": [("clifMsmv1", "박물관", "msmNm", "fndnMnbdNm", "instAddr"), ("clifArglv1", "미술관", "arglNm", "fndnMnbdNm", "instAddr")],
    "hall": [
        ("clifClcnv1", "문예회관", "clcnNm", "clcnErctMnbdNm", "instAddr"),
        ("clifLvclCntrv1", "생활문화센터", "lvclCntrNm", "lvclCntrOperMthdNm", "instAddr"),
        ("clifLtrm1", "문학관", "ltrmNm", "ntpbSprtnNm", "addr"),
    ],
}
_CLTR_NOTE = {
    "museum": "한국문화정보원 전국문화기반시설총람(지역문화통합정보시스템)의 박물관·미술관이에요. 운영 시간·휴관일은 누리집에서 확인해 주세요.",
    "hall": "한국문화정보원 전국문화기반시설총람(지역문화통합정보시스템)의 문예회관·생활문화센터·문학관이에요. 공연·프로그램과 운영 시간은 누리집에서 확인해 주세요.",
}


def _cltr_pages(op: str, year: int) -> list[dict]:
    rows: list[dict] = []
    for page in range(1, 6):
        r = requests.get(
            f"{CLTR_URL}/{op}",
            params={"serviceKey": config.get_key(_http.KEY_ENV), "pageNo": page, "numOfRows": 1000, "resultType": "json", "pblshYr": year},
            timeout=60,
        )
        r.raise_for_status()
        body = (r.json().get("response") or {}).get("body") or {}
        data = body.get("data") or []
        rows.extend(data)
        if page * 1000 >= int(body.get("totalCount") or 0) or not data:
            break
    return rows


def _cltr_all(kind: str) -> list[dict]:
    year = _kst.today().year
    for y in range(year, year - 5, -1):
        out: list[dict] = []
        for op, label, name_key, who_key, addr_key in _CLTR_KINDS[kind]:
            for x in _cltr_pages(op, y):
                x["_label"], x["_name"], x["_who"], x["_addr"] = label, x.get(name_key), x.get(who_key), x.get(addr_key)
                out.append(x)
        if out:
            return out
    return []


def _cltr(kind: str, sido: str | None, sgg: str | None) -> dict:
    rows = _cache.cached("places", f"places:cltr2:{kind}", 1440, lambda: {"v": _cltr_all(kind)}, shared=True)["v"]
    region = geo.region(sido)
    terms = geo.sgg_terms(sido, sgg)
    out = []
    for x in rows:
        addr = _clean(x.get("_addr"))
        name = _clean(x.get("_name"))
        if not name or not _in_region(addr[:14], region):
            continue
        near = _has(terms, addr)
        label = x["_label"]
        who = _clean(x.get("_who"))
        grade = _clean(x.get("msmGradSprtnNm") or x.get("arglGradSprtnNm"))
        days, visitors = x.get("fyerOpngNmdy"), x.get("fyerVwngNope") or x.get("fyerVstNope")
        yr = _clean(x.get("crtrYr"))  # 총람의 조사 기준 연도(발간연도의 전년)
        site = _clean(x.get("hmpgAddr"))
        url = ("" if not site else site if site.startswith("http") else "https://" + site)
        item = _item(
            f"cl{x.get('instId')}{label}", name, " · ".join(p for p in (label, addr) if p), who if kind == "museum" else label, "",
            [("구분", f"{label}{' · ' + grade if grade else ''}"), ("설립·운영", who), ("주소", addr), ("전화", _clean(x.get("telnoCn"))),
             ("소장 자료", _clean(x.get("clctnDataKndCn"))[:200]),
             ("연 개관일수", f"{days}일({yr}년 조사)" if days else None),
             ("연 관람객", f"{int(visitors):,}명({yr}년 조사)" if isinstance(visitors, int) and visitors else None)],
            url, "누리집 열기" if url else "", _pin(name, None, None, f"{name} {addr}".strip()),
        )
        out.append((0 if near else 1, item["name"], item))
    out.sort(key=lambda t: t[:2])
    out, region_label, scope_note = _scope(out, sgg, region)
    return {"live": True, "total": len(out), "items": [t[2] for t in out], "region": region_label, "scope_note": scope_note, "note": _CLTR_NOTE[kind]}


def museum(sido: str | None, sgg: str | None) -> dict:
    return _cltr("museum", sido, sgg)


def hall(sido: str | None, sgg: str | None) -> dict:
    return _cltr("hall", sido, sgg)


def query(kind: str, sido: str | None, sgg: str | None) -> dict:
    fn = {"library": library, "camp": camp, "pet": pet, "wellness": wellness, "trail": trail, "museum": museum, "hall": hall}.get(kind)
    if not fn:
        return {"live": False, "items": []}
    try:
        return fn(sido, sgg)
    except Exception:
        return {"live": False, "items": []}


def _warm() -> dict:
    """사용자가 처음 열 때 기다리지 않게 하루 한 번 큰 목록(도서관·캠핑·걷기길, 서울의 반려동물·웰니스)을 미리 받아 둠."""
    for fn in (lambda: library("11", None), lambda: camp("11", None), lambda: trail("11", None), lambda: pet("11", None), lambda: wellness("11", None), lambda: museum("11", None), lambda: hall("11", None)):
        try:
            fn()
        except Exception:
            pass
    return {"ok": True}


import jobs  # noqa: E402

jobs.register(jobs.Job(name="places_warm", run=_warm, env_keys=[_http.KEY_ENV], interval_min=720))
