# -*- coding: utf-8 -*-
"""머니 탭 "정부 지원·혜택": 행정안전부 「대한민국 공공서비스(혜택) 정보」(보조금24 데이터, 공공데이터포털 15113968).

엔드포인트: https://api.odcloud.kr/api/gov24/v3/serviceList (page, perPage, serviceKey)
 - 활용신청(자동 승인)을 한 키만 호출됨. 신청 전엔 401 "등록되지 않은 인증키" → 수집 실패로 기록되고 화면엔 아무것도 안 나옴(예시 데이터 없음).
 - 응답 필드 이름은 한글(서비스ID·서비스명·지원내용·지원대상·신청방법·신청기한·소관기관명·소관기관유형·서비스분야·조회수·상세조회URL…).
   실제 응답을 아직 못 봐서(키 승인 전) 필드 이름은 여러 후보를 받아들이게 짜 둠 — 승인 뒤 첫 응답으로 확인할 것.
 - 전체(약 1만 건)를 12시간마다 받아 줄여서 저장하고, 요청에서는 지역·구분으로 걸러 위쪽 몇 개만 줌(요청마다 외부 호출 안 함).
이용: 개인정보 없이 "지역(시도·시군구)"만으로 거름. 개인 조건(나이·소득)은 받지 않음.
"""

from __future__ import annotations

import re
from datetime import date, datetime

import requests

import config
import geo
import jobs
from sources import _http

URL = "https://api.odcloud.kr/api/gov24/v3/serviceList"
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


def run() -> dict:
    key = config.get_key(_http.KEY_ENV)
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
                }
            )
        if len(rows) < PER_PAGE or (total is not None and page * PER_PAGE >= int(total)):
            break
    items = [i for i in items if i["name"]]
    if not items:
        raise RuntimeError("공공서비스 없음")
    return {"support_all": items, "support_total": len(items), "support_at": datetime.now().isoformat(timespec="minutes")}


_mem: dict = {"at": None, "items": []}


def _items() -> list[dict]:
    live = jobs.get_live("gov_support") or {}
    if live.get("support_at") != _mem["at"]:
        _mem["at"], _mem["items"] = live.get("support_at"), live.get("support_all") or []
    return _mem["items"]


def query(sido: str | None, sgg: str | None, scope: str = "all", field: str | None = None, limit: int = 30) -> dict:
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
    # 우리 지역 서비스를 먼저, 그 안에서는 조회수 순
    pool = sorted(pool, key=lambda i: (0 if id(i) in local_ids else 1, -i["views"]))
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
        "local_count": len(local),
        "items": pool[:limit],
        "fields": top_fields,
        "region": region["name"] + (f" {sgg}" if sgg else ""),
    }


_ALL_SIDO = ("서울", "부산", "대구", "인천", "광주", "대전", "울산", "세종", "경기", "강원", "충북", "충남", "충청", "전북", "전남", "전라", "경북", "경남", "경상", "제주")


def _all_sgg(code: str) -> list[str]:
    return [s["name"] for s in geo.sigungu_list(code)]


jobs.register(jobs.Job(name="gov_support", run=run, env_keys=[_http.KEY_ENV], interval_min=720))
