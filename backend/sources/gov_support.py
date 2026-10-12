# -*- coding: utf-8 -*-
"""머니 탭 "정부 지원·혜택": 행정안전부 「대한민국 공공서비스(혜택) 정보」(보조금24 데이터, 공공데이터포털 15113968).

엔드포인트: https://api.odcloud.kr/api/gov24/v3/serviceList (page, perPage, serviceKey)
 - 활용신청(자동 승인)을 한 키만 호출됨. 신청 전엔 401 "등록되지 않은 인증키" → 수집 실패로 기록되고 화면엔 아무것도 안 나옴(예시 데이터 없음).
 - 응답 필드 이름은 한글(서비스ID·서비스명·지원내용·지원대상·신청방법·신청기한·소관기관명·소관기관유형·서비스분야·조회수·상세조회URL…).
   실제 응답을 아직 못 봐서(키 승인 전) 필드 이름은 여러 후보를 받아들이게 짜 둠 — 승인 뒤 첫 응답으로 확인할 것.
 - 전체(약 1만 건)를 12시간마다 받아 줄여서 저장하고, 요청에서는 지역·구분으로 걸러 위쪽 몇 개만 줌(요청마다 외부 호출 안 함).
이용: 기본은 "지역(시도·시군구)"만으로 거름. 사용자가 원하면 나이·성별·소득구간·해당 특성을 골라 더 좁힐 수 있는데,
그 조건은 요청 본문(POST)으로만 받아 그 자리에서 거르고 저장·로그하지 않음(서버 접속 로그에도 안 남게 GET 쿼리를 안 씀).

지원조건(`/supportConditions`, 서비스 전체에 연령·성별·소득·대상특성 표시) — 코드 뜻은 서비스명 키워드와 대조해 확인함(2026-10-12):
 JA0101 남 / JA0102 여 / JA0110·JA0111 연령 하한·상한 / JA0201~0205 기준중위소득 구간(50%↓·75%↓·100%↓·200%↓·200%↑)
 JA03xx 대상특성: 0301 예비·신혼부부 0302 임신 0303 출산·입양 0313 농업인 0314 어업인 0315 축산업인 0316 임업인
   0317 초등생 0318 중학생 0319 고등학생 0320 대학생 0322 해당사항 없음 0326 근로자 0327 구직자 0328 장애인 0329 국가보훈 0330 질병·질환
 (JA04xx 가구유형·JA11xx/12xx/21xx/22xx 사업체 조건은 뜻이 확인되지 않아 쓰지 않음)
"""

from __future__ import annotations

import re
import time
from datetime import date, datetime

import requests

import config
import geo
import jobs
from sources import _http

_BASE = config.get_key("GOV24_BENEFIT_BASE_URL") or "https://api.odcloud.kr/api/gov24/v3"
URL = _BASE + "/serviceList"
COND_URL = _BASE + "/supportConditions"
PER_PAGE = 1000
MAX_PAGES = 15

# 한글 필드 이름 후보(앞쪽이 우선)
F = {
    "id": ("서비스ID", "서비스아이디", "svcId"),
    "name": ("서비스명", "svcNm"),
    "summary": ("서비스목적요약", "서비스목적", "svcPurposeSumm"),
    "support": ("지원내용", "supportCn"),
    "target": ("지원대상", "supportTarget"),
    "method": ("신청방법", "applyMthd"),
    "deadline": ("신청기한", "applyDeadline"),
    "org": ("소관기관명", "organizationName"),
    "orgtype": ("소관기관유형", "organizationType"),
    "phone": ("전화문의", "contact"),
    "url": ("상세조회URL", "detailUrl"),
    "field": ("서비스분야", "serviceField"),
    "views": ("조회수", "viewCount"),
    "kind": ("지원유형", "supportType"),
}


def _g(d: dict, key: str) -> str:
    for k in F[key]:
        v = d.get(k)
        if v not in (None, ""):
            return str(v).strip()
    return ""


def _clip(s: str, n: int) -> str:
    s = re.sub(r"\s+", " ", s or "").strip()
    return s if len(s) <= n else s[: n - 1] + "…"


def _expired(deadline: str) -> bool:
    """신청기한 문구에 지난 날짜만 있으면 만료로 봄(상시·미기재는 유효)."""
    dates = re.findall(r"(20\d{2})[.\-/ ]*(\d{1,2})[.\-/ ]*(\d{1,2})", deadline or "")
    if not dates:
        return False
    y, m, d = (int(x) for x in dates[-1])
    try:
        return date(y, m, d) < date.today()
    except ValueError:
        return False


TRAITS = {  # 화면에서 고르는 이름 → 지원조건 코드
    "newlywed": "JA0301", "pregnant": "JA0302", "birth": "JA0303", "farmer": "JA0313", "fisher": "JA0314",
    "livestock": "JA0315", "forest": "JA0316", "elem": "JA0317", "middle": "JA0318", "high": "JA0319",
    "univ": "JA0320", "worker": "JA0326", "jobseeker": "JA0327", "disabled": "JA0328", "veteran": "JA0329", "illness": "JA0330",
}
_NONE_TRAIT = "JA0322"


def _fetch_conditions(key: str) -> dict[str, dict]:
    """서비스ID → 줄인 조건 {a:[하한,상한], g:'mf'의 부분, i:'12345'의 부분, t:[대상특성 코드]}. 실패하면 빈 dict(조건 필터만 못 씀)."""
    out: dict[str, dict] = {}
    try:
        for page in range(1, MAX_PAGES + 1):
            r = requests.get(COND_URL, params={"page": page, "perPage": PER_PAGE, "serviceKey": key}, timeout=40)
            if r.status_code != 200:
                break
            rows = r.json().get("data") or []
            for d in rows:
                sid = str(d.get("서비스ID") or "")
                if not sid:
                    continue
                lo, hi = d.get("JA0110"), d.get("JA0111")
                out[sid] = {
                    "a": [lo if isinstance(lo, int) else None, hi if isinstance(hi, int) else None],
                    "g": ("m" if d.get("JA0101") == "Y" else "") + ("f" if d.get("JA0102") == "Y" else ""),
                    "i": "".join(str(n) for n in range(1, 6) if d.get(f"JA020{n}") == "Y"),
                    "t": [c for c in (*TRAITS.values(), _NONE_TRAIT) if d.get(c) == "Y"],
                }
            if len(rows) < PER_PAGE:
                break
    except Exception:
        return {}
    return out


def run() -> dict:
    key = config.get_key(_http.KEY_ENV)
    conds = _fetch_conditions(key)
    items: list[dict] = []
    total = None
    for page in range(1, MAX_PAGES + 1):
        r = requests.get(URL, params={"page": page, "perPage": PER_PAGE, "serviceKey": key}, timeout=40)
        if r.status_code != 200:
            raise RuntimeError(f"공공서비스 API {r.status_code}")  # 키 미승인이면 401 — 메시지에 키가 안 들어가게 짧게
        body = r.json()
        rows = body.get("data") or []
        total = body.get("totalCount", total)
        for d in rows:
            deadline = _g(d, "deadline")
            if _expired(deadline):
                continue
            items.append(
                {
                    "id": _g(d, "id"),
                    "name": _g(d, "name"),
                    "summary": _clip(_g(d, "summary"), 140),
                    "support": _clip(_g(d, "support"), 400),
                    "target": _clip(_g(d, "target"), 300),
                    "method": _clip(_g(d, "method"), 200),
                    "deadline": _clip(deadline, 80),
                    "org": _g(d, "org"),
                    "orgtype": _g(d, "orgtype"),
                    "phone": _clip(_g(d, "phone"), 60),
                    "url": _g(d, "url"),
                    "field": _g(d, "field"),
                    "kind": _g(d, "kind"),
                    "views": int(float(_g(d, "views") or 0)),
                    "c": conds.get(_g(d, "id")),
                }
            )
        if len(rows) < PER_PAGE or (total is not None and page * PER_PAGE >= int(total)):
            break
    items = [i for i in items if i["name"]]
    if not items:
        raise RuntimeError("공공서비스 없음")
    return {"support_all": items, "support_total": len(items), "support_at": datetime.now().isoformat(timespec="minutes")}


_mem: dict = {"at": None, "items": [], "checked": 0.0}


def _items() -> list[dict]:
    """전체 목록(약 6MB)을 요청마다 다시 읽지 않게 메모리에 두고 5분에 한 번만 새로 확인함."""
    now = time.time()
    if now - _mem["checked"] > 300 or not _mem["items"]:  # 비어 있으면(아직 수집 전) 매번 다시 확인
        _mem["checked"] = now
        live = jobs.get_live("gov_support") or {}
        if live.get("support_at") != _mem["at"]:
            _mem["at"], _mem["items"] = live.get("support_at"), live.get("support_all") or []
    return _mem["items"]


def _matches(c: dict | None, prof: dict) -> bool:
    """조건 정보가 없으면(c 없음) 걸러내지 않음. 사용자가 입력한 항목만 비교하고, 서비스 쪽이 비어 있으면 제한 없음으로 봄."""
    if not c:
        return True
    age = prof.get("age")
    if isinstance(age, int):
        lo, hi = c["a"]
        if (lo is not None and age < lo) or (hi is not None and age > hi):
            return False
    g = prof.get("gender")
    if g in ("m", "f") and c["g"] and g not in c["g"]:
        return False
    inc = prof.get("income")
    if isinstance(inc, int) and 1 <= inc <= 5 and c["i"] and str(inc) not in c["i"]:
        return False
    t = c["t"]
    if t and _NONE_TRAIT not in t:  # 특정 대상(농업인·학생 등)만 받는 서비스: 내가 고른 특성 중 하나라도 겹쳐야 함
        mine = {TRAITS[k] for k in (prof.get("traits") or []) if k in TRAITS}
        if not (mine & set(t)):
            return False
    return True


def _fit(c: dict | None, prof: dict) -> int:
    """조건에 맞는 것들 중 "나를 콕 집은" 정도 — 좁게 겨냥한 서비스(내 특성·나이대·성별 전용)일수록 높게. 정렬에만 씀."""
    if not c:
        return 0
    n = 0
    lo, hi = c["a"]
    if isinstance(prof.get("age"), int) and lo is not None and hi is not None and hi - lo <= 30:
        n += 2
    elif isinstance(prof.get("age"), int) and lo is not None and hi is not None and hi - lo <= 60:
        n += 1
    if prof.get("gender") in ("m", "f") and len(c["g"]) == 1:
        n += 1
    if prof.get("income") and 0 < len(c["i"]) <= 2:
        n += 1
    t = c["t"]
    if t and _NONE_TRAIT not in t and len(t) <= 3:
        n += 3
    return n


def _clean_profile(p: dict | None) -> dict | None:
    if not p:
        return None
    age = p.get("age")
    prof = {
        "age": age if isinstance(age, int) and 0 <= age <= 120 else None,
        "gender": p.get("gender") if p.get("gender") in ("m", "f") else None,
        "income": p.get("income") if isinstance(p.get("income"), int) and 1 <= p["income"] <= 5 else None,
        "traits": [k for k in (p.get("traits") or []) if k in TRAITS],
    }
    return prof if any(prof.values()) else None


def query(sido: str | None, sgg: str | None, scope: str = "all", field: str | None = None, limit: int = 30, profile: dict | None = None) -> dict:
    """지역(시도·시군구)과 구분으로 거른 지원 서비스. scope: all | local(우리 지역) | central(중앙부처).
    수집이 안 됐으면(키 미승인 등) live=False, items=[] — 화면은 섹션을 숨김."""
    allitems = _items()
    if not allitems:
        return {"live": False, "items": [], "fields": []}
    region = geo.region(sido)
    prefixes = tuple(region.get("prefixes") or (region["name"],))

    sgg_names = _all_sgg(region["code"])

    def is_local(i: dict) -> bool:
        org = i["org"]
        if not any(p in org for p in prefixes):
            return False
        if not sgg or sgg in org:
            return True
        return not any(s in org for s in sgg_names)  # 다른 시군구 기관이 아니면 시도 단위 기관

    def is_central(i: dict) -> bool:
        return "중앙" in i["orgtype"] or (not any(p in i["org"] for p in _ALL_SIDO) and "지자체" not in i["orgtype"])

    local = [i for i in allitems if is_local(i)]
    local_ids = {id(i) for i in local}
    central = [i for i in allitems if id(i) not in local_ids and is_central(i)]
    pool = {"local": local, "central": central}.get(scope, local + central)
    if field:
        pool = [i for i in pool if field in i["field"]]
    prof = _clean_profile(profile)
    unfiltered = len(pool)
    if prof:
        pool = [i for i in pool if _matches(i.get("c"), prof)]
    # 우리 시군구 → 우리 시도 → 중앙부처 순, 같은 묶음 안에서는 조회수 순
    def tier(i: dict) -> int:
        if id(i) not in local_ids:
            return 2
        return 0 if sgg and sgg in i["org"] else 1

    if prof:
        pool = sorted(pool, key=lambda i: (tier(i), -_fit(i.get("c"), prof), -i["views"]))
    else:
        pool = sorted(pool, key=lambda i: (tier(i), -i["views"]))
    fields: dict[str, int] = {}
    for i in local + central:
        for f in re.split(r"[,·/]", i["field"]):
            f = f.strip()
            if f:
                fields[f] = fields.get(f, 0) + 1
    top_fields = [f for f, _ in sorted(fields.items(), key=lambda kv: -kv[1])[:8]]
    return {
        "live": True,
        "total": len(pool),
        "unfiltered_total": unfiltered,
        "filtered": bool(prof),
        "local_count": len(local),
        "items": [{k: v for k, v in i.items() if k != "c"} for i in pool[:limit]],
        "fields": top_fields,
        "region": region["name"] + (f" {sgg}" if sgg else ""),
    }


_ALL_SIDO = ("서울", "부산", "대구", "인천", "광주", "대전", "울산", "세종", "경기", "강원", "충북", "충남", "충청", "전북", "전남", "전라", "경북", "경남", "경상", "제주")


def _all_sgg(code: str) -> list[str]:
    return [s["name"] for s in geo.sigungu_list(code)]


jobs.register(jobs.Job(name="gov_support", run=run, env_keys=[_http.KEY_ENV], interval_min=720))
