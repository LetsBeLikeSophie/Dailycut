# -*- coding: utf-8 -*-
"""혜택 탭의 주거·금융 구역: 청약(한국부동산원 청약홈), 공공임대(국토부 마이홈포털 + LH 공고), 서민 대출(서민금융진흥원).

모두 공공데이터포털 이용허락범위 "제한 없음"(2026-10-13 포털 표기 확인, 상업 이용 가능). 같은 인증키로 호출.
 - 청약홈: api.odcloud.kr/api/ApplyhomeInfoDetailSvc/v1  (APT·무순위(잔여)·오피스텔/도시형·공공지원민간임대 4종)
 - 마이홈: apis.data.go.kr/1613000/HWSPR02/rsdtRcritNtcList  (brtcCode=시도 2자리, 전국 약 300건)
 - LH:    apis.data.go.kr/B552555/lhLeaseNoticeInfo1/lhLeaseNoticeInfo1 (주소 끝에 함수 이름을 한 번 더 붙여야 함)
 - 서민금융: apis.data.go.kr/B553701/LoanProductSearchingInfo/LoanProductSearchingInfo/getLoanProductSearchingInfo (XML, 약 320건)
작업이 목록을 줄여 저장해 두고(요청마다 외부 호출 안 함), 조회 때 오늘 날짜로 "접수 중/예정/마감"과 지역 필터를 계산함.
마이홈 목록엔 LH 공고가 이미 들어 있어서, LH 공고는 같은 공고번호(panId)가 마이홈에 없을 때만 보탬.
"""

from __future__ import annotations

import html
import re
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta

import requests

import config
import geo
import jobs
from sources import _http

APPLY_ENDPOINTS = (
    ("getAPTLttotPblancDetail", "아파트"),
    ("getRemndrLttotPblancDetail", "무순위·잔여"),
    ("getUrbtyOfctlLttotPblancDetail", "오피스텔·도시형"),
    ("getPblPvtRentLttotPblancDetail", "공공지원 민간임대"),
)
LH_URL = "https://apis.data.go.kr/B552555/lhLeaseNoticeInfo1/lhLeaseNoticeInfo1"
SMILE_URL = "https://apis.data.go.kr/B553701/LoanProductSearchingInfo/LoanProductSearchingInfo/getLoanProductSearchingInfo"


def _base(name: str) -> str:
    return config.get_key(name) or ""


def _u(v) -> str:
    """공공데이터에 가끔 글자 코드가 두 번 겹쳐 들어 있음(예: "&amp;#40;" → "&#40;") — 풀어서 "("로 만들고 공백을 정리."""
    t = str(v or "")
    for _ in range(2):
        t = html.unescape(t)
    return re.sub(r"\s+", " ", t).strip()


def _iso(s) -> str:
    """'20261019' · '2026-10-19' · '2026.10.19' → '2026-10-19'(못 읽으면 빈 문자열)."""
    d = re.sub(r"\D", "", str(s or ""))
    return f"{d[:4]}-{d[4:6]}-{d[6:8]}" if len(d) >= 8 else ""


def _md(iso: str) -> str:
    return f"{int(iso[5:7])}/{int(iso[8:10])}" if iso else ""


# ---------------- 수집 ----------------


def _apply_items(key: str, today: date) -> list[dict]:
    base = _base("APPLYHOME_BASE_URL")
    since = (today - timedelta(days=75)).isoformat()
    out: list[dict] = []
    for ep, kind in APPLY_ENDPOINTS:
        for page in range(1, 6):
            r = requests.get(f"{base}/{ep}", params={"serviceKey": key, "page": page, "perPage": 100, "cond[RCRIT_PBLANC_DE::GTE]": since}, timeout=40)
            if r.status_code != 200:
                raise RuntimeError(f"청약홈 {ep} {r.status_code}")
            rows = r.json().get("data") or []
            for d in rows:
                start, end = _iso(d.get("SUBSCRPT_RCEPT_BGNDE") or d.get("RCEPT_BGNDE")), _iso(d.get("SUBSCRPT_RCEPT_ENDDE") or d.get("RCEPT_ENDDE"))
                if not end or end < today.isoformat():
                    continue  # 접수가 끝난 공고는 저장하지 않음
                addr = (d.get("HSSPLY_ADRES") or "").strip()
                out.append(
                    {
                        "id": f"ap{d.get('HOUSE_MANAGE_NO')}{ep[3:6]}",
                        "name": _u(d.get("HOUSE_NM")),
                        "kind": kind,
                        "region": (d.get("SUBSCRPT_AREA_CODE_NM") or "").strip(),
                        "addr": _u(addr),
                        "start": start,
                        "end": end,
                        "announce": _iso(d.get("RCRIT_PBLANC_DE")),
                        "winners": _iso(d.get("PRZWNER_PRESNATN_DE")),
                        "contract": " ~ ".join(x for x in (_iso(d.get("CNTRCT_CNCLS_BGNDE")), _iso(d.get("CNTRCT_CNCLS_ENDDE"))) if x),
                        "households": d.get("TOT_SUPLY_HSHLDCO"),
                        "movein": (str(d.get("MVN_PREARNGE_YM") or "")[:4] + "." + str(d.get("MVN_PREARNGE_YM") or "")[4:6]) if d.get("MVN_PREARNGE_YM") else "",
                        "builder": _u(d.get("BSNS_MBY_NM")),
                        "phone": str(d.get("MDHS_TELNO") or "").strip(),
                        "url": d.get("PBLANC_URL") or d.get("HMPG_ADRES") or "",
                    }
                )
            if len(rows) < 100:
                break
    return out


def _myhome_items(key: str, today: date) -> list[dict]:
    base = _base("MYHOME_NOTICE_BASE_URL")
    out: list[dict] = []
    for page in range(1, 8):
        r = requests.get(f"{base}/rsdtRcritNtcList", params={"serviceKey": key, "pageNo": page, "numOfRows": 100}, timeout=40)
        if r.status_code != 200:
            raise RuntimeError(f"마이홈 {r.status_code}")
        body = (r.json().get("response") or {}).get("body") or {}
        rows = body.get("item") or []
        for d in rows:
            end = _iso(d.get("endDe"))
            if not end or end < today.isoformat():
                continue
            out.append(
                {
                    "id": f"mh{d.get('pblancId')}",
                    "name": _u(d.get("pblancNm")),
                    "kind": " · ".join(x for x in (d.get("suplyTyNm"), d.get("houseTyNm")) if x),
                    "agency": (d.get("suplyInsttNm") or "").strip(),
                    "region": (d.get("brtcNm") or "").strip(),
                    "sgg": (d.get("signguNm") or "").strip(),
                    "start": _iso(d.get("beginDe")),
                    "end": end,
                    "announce": _iso(d.get("rcritPblancDe")),
                    "winners": _iso(d.get("przwnerPresnatnDe")),
                    "households": d.get("sumSuplyCo") or d.get("suplyHoCo") or None,
                    "phone": _u(d.get("refrnc")),
                    "url": d.get("pcUrl") or d.get("url") or "",
                    "src_url": d.get("url") or "",
                }
            )
        if len(rows) < 100:
            break
    return out


def _lh_items(key: str, today: date, have_pan_ids: set[str]) -> list[dict]:
    out: list[dict] = []
    for page in range(1, 6):
        r = requests.get(
            LH_URL,
            params={"serviceKey": key, "PG_SZ": 100, "PAGE": page, "PAN_ST_DT": (today - timedelta(days=60)).strftime("%Y%m%d"), "PAN_ED_DT": (today + timedelta(days=30)).strftime("%Y%m%d")},
            timeout=40,
        )
        if r.status_code != 200:
            raise RuntimeError(f"LH {r.status_code}")
        data = r.json()
        rows = next((b.get("dsList") for b in data if isinstance(b, dict) and "dsList" in b), None) or []
        for d in rows:
            pan = str(d.get("PAN_ID") or "")
            end = _iso(d.get("CLSG_DT"))
            if not pan or pan in have_pan_ids or d.get("PAN_SS") not in ("공고중", "접수중") or (end and end < today.isoformat()):
                continue
            out.append(
                {
                    "id": f"lh{pan}",
                    "name": _u(d.get("PAN_NM")),
                    "kind": " · ".join(x for x in (d.get("UPP_AIS_TP_NM"), d.get("AIS_TP_CD_NM")) if x),
                    "agency": "LH",
                    "region": (d.get("CNP_CD_NM") or "").strip(),
                    "sgg": "",
                    "start": "",
                    "end": end,
                    "announce": _iso(d.get("PAN_NT_ST_DT")),
                    "winners": "",
                    "households": None,
                    "phone": "LH 콜센터 1600-1004",
                    "url": d.get("DTL_URL") or "",
                    "src_url": d.get("DTL_URL") or "",
                }
            )
        if len(rows) < 100:
            break
    return out


def run_housing() -> dict:
    key = config.get_key(_http.KEY_ENV)
    today = date.today()
    apply = _apply_items(key, today)
    rent = _myhome_items(key, today)
    have = {m.group(1) for it in rent for m in [re.search(r"panId=(\d+)", it.get("src_url") or "")] if m}
    try:
        rent += _lh_items(key, today, have)
    except Exception:
        pass  # LH가 실패해도 마이홈 목록은 그대로 씀
    if not apply and not rent:
        raise RuntimeError("청약·임대 공고 없음")
    return {"apply": apply, "rent": rent, "housing_at": datetime.now().isoformat(timespec="minutes")}


def _text(el: ET.Element, tag: str) -> str:
    v = _u(el.findtext(tag))
    return "" if v in ("-", "없음") else v


def run_loans() -> dict:
    key = config.get_key(_http.KEY_ENV)
    r = requests.get(SMILE_URL, params={"serviceKey": key, "pageNo": 1, "numOfRows": 500}, timeout=40)
    if r.status_code != 200:
        raise RuntimeError(f"서민금융 {r.status_code}")
    root = ET.fromstring(r.text)
    out: list[dict] = []
    for it in root.findall(".//item"):
        name = _text(it, "finprdnm")
        if not name:
            continue
        limit = _text(it, "lnlmt")
        out.append(
            {
                "id": f"ln{_text(it, 'seq')}",
                "name": name,
                "usage": _text(it, "usge"),
                "target": _text(it, "trgt"),
                "target_detail": _text(it, "suprtgtdtlcond"),
                "org": _text(it, "ofrinstnm") or _text(it, "grninst"),
                "handler": _text(it, "hdlinstdtlvw") or _text(it, "hdlinst"),
                "rate": _text(it, "irt"),
                "rate_kind": _text(it, "irtCtg"),
                "limit": int(limit) if limit.isdigit() else None,  # 만원
                "term": _text(it, "maxtotlntrm"),
                "repay": _text(it, "rdptmthd"),
                "how": _text(it, "jnmthd"),
                "phone": _text(it, "cnpl") or _text(it, "rfrccnpl"),
                "url": _text(it, "rltsite"),
                "area": _text(it, "rsdAreaPamtEqltIstm"),
                "note": _text(it, "etcrefsbjc"),
            }
        )
    if not out:
        raise RuntimeError("서민금융 상품 없음")
    return {"loans": out, "loans_at": datetime.now().isoformat(timespec="minutes")}


jobs.register(jobs.Job(name="housing", run=run_housing, env_keys=[_http.KEY_ENV], interval_min=180))
jobs.register(jobs.Job(name="loans", run=run_loans, env_keys=[_http.KEY_ENV], interval_min=1440))


# ---------------- 조회 ----------------

_mem: dict = {}


def _live(job: str, field: str) -> list[dict]:
    got = jobs.get_live(job) or {}
    return got.get(field) or []


def _state(start: str, end: str, today: date) -> tuple[int, str, str]:
    """(정렬 묶음, 꼬리표, 기간 글). 0=접수 중, 1=접수 예정."""
    t = today.isoformat()
    span = f"{_md(start)}~{_md(end)}" if start and end and start != end else (_md(end) or _md(start))
    if start and start > t:
        n = (date.fromisoformat(start) - today).days
        return 1, ("내일 접수" if n == 1 else f"{n}일 뒤 접수"), span
    n = (date.fromisoformat(end) - today).days if end else None
    if n is None:
        return 0, "공고 중", span
    return 0, ("오늘 마감" if n == 0 else f"접수 중 · {n}일 남음"), span


def _detail_rows(rows: list[tuple[str, str | int | None]]) -> list[list[str]]:
    return [[k, str(v)] for k, v in rows if v not in (None, "", 0)]


def housing(kind: str, sido: str | None, sgg: str | None, limit: int = 60) -> dict:
    """kind: apply(청약) | rent(공공임대). 선택한 시도 공고만(시군구가 주소에 있으면 위로)."""
    field = "apply" if kind == "apply" else "rent"
    items = _live("housing", field)
    if not items:
        return {"live": False, "items": []}
    today = date.today()
    region = geo.region(sido)
    prefixes = tuple(region.get("prefixes") or (region["name"],))

    def in_region(it: dict) -> bool:
        r = it.get("region") or ""
        return r == region["name"] or any(p in r for p in prefixes)

    rows = []
    for it in items:
        if not in_region(it) or (it["end"] and it["end"] < today.isoformat()):
            continue
        group, tag, span = _state(it.get("start", ""), it.get("end", ""), today)
        near = bool(sgg and (sgg in (it.get("addr") or "") or sgg in (it.get("sgg") or "") or sgg in it["name"]))
        if kind == "apply":
            sub = " · ".join(x for x in (it["kind"], it["addr"].split(" ", 2)[1] if it["addr"].count(" ") >= 1 else it["region"], f"{it['households']}세대" if it.get("households") else "") if x)
            detail = _detail_rows([
                ("접수 기간", f"{it['start']} ~ {it['end']}" if it["start"] else it["end"]),
                ("당첨자 발표", it.get("winners")), ("계약 기간", it.get("contract")), ("공고일", it.get("announce")),
                ("위치", it.get("addr")), ("공급 세대", it.get("households")), ("입주 예정", it.get("movein")),
                ("사업 주체", it.get("builder")), ("분양 문의", it.get("phone")),
            ])
            link_label = "청약홈에서 자세히 보기"
        else:
            where = " ".join(x for x in (it.get("region"), it.get("sgg")) if x)
            sub = " · ".join(x for x in (it.get("agency"), it["kind"], where) if x)
            detail = _detail_rows([
                ("접수 기간", f"{it['start']} ~ {it['end']}" if it["start"] else (f"~ {it['end']}" if it["end"] else None)),
                ("당첨자 발표", it.get("winners")), ("공고일", it.get("announce")), ("공급 기관", it.get("agency")),
                ("지역", where), ("공급 호수", it.get("households")), ("문의", it.get("phone")),
            ])
            link_label = "공고 자세히 보기"
        # 접수 중(0)은 마감 가까운 순, 접수 예정(1)은 시작 가까운 순 — "곧 마감" 공고가 위로 오게
        rows.append((0 if near else 1, group, (it.get("end") if group == 0 else it.get("start")) or "9999", {
            "id": it["id"], "name": it["name"], "sub": sub, "tag": tag, "span": span, "detail": detail, "url": it.get("url") or "", "link_label": link_label,
        }))
    rows.sort(key=lambda r: (r[1], r[0], r[2]))
    out = [r[3] for r in rows]
    return {"live": True, "total": len(out), "items": out[:limit], "region": region["name"] + (f" {sgg}" if sgg else "")}


def _usage_group(it: dict) -> str:
    u = it["usage"]
    for g in ("학자금", "주거", "생계"):
        if g in u:
            return g
    return "사업"


def _rate_text(it: dict) -> str:
    r = (it["rate"] or "").replace(" ", "")
    if not r:
        return ""
    if not re.search(r"\d", r):  # "특정금리"·"은행별상이" 같은 글은 숫자 서식을 씌우지 않음
        return f"{it['rate_kind']} {r}".strip()
    if r.startswith("~"):
        txt = f"연 {r[1:]}% 이하"
    elif r.endswith("~"):
        txt = f"연 {r[:-1]}%부터"
    else:
        txt = f"연 {r}%"
    return f"{it['rate_kind']} {txt}".strip()


def loans(usage: str | None = None, sido: str | None = None, limit: int = 80) -> dict:
    """서민금융 대출상품. 내 지역(전국 공통 + 내 시도 상품)만, usage는 생계·주거·학자금·사업(쉼표로 여러 개 = 하나라도 맞으면)."""
    items = _live("loans", "loans")
    if not items:
        return {"live": False, "items": []}
    region = geo.region(sido)
    prefixes = tuple(region.get("prefixes") or (region["name"],))

    def in_area(it: dict) -> bool:
        a = it["area"]
        return a in ("", "전국") or any(p in a for p in prefixes)

    pool = [it for it in items if in_area(it)]
    groups = {it["id"]: _usage_group(it) for it in pool}
    chips = [g for g in ("생계", "주거", "학자금", "사업") if any(v == g for v in groups.values())]
    picked = {u.strip() for u in (usage or "").split(",") if u.strip()}
    if picked:
        pool = [it for it in pool if groups[it["id"]] in picked]
    pool.sort(key=lambda it: (groups[it["id"]] == "사업", it["name"]))
    out = []
    for it in pool[:limit]:
        rate = _rate_text(it)
        out.append(
            {
                "id": it["id"],
                "name": it["name"],
                "sub": " · ".join(x for x in (it["org"], it["usage"], it["target"]) if x),
                "tag": f"최대 {it['limit']:,}만원" if it["limit"] else "",
                "span": rate if len(rate) <= 26 else rate[:25] + "…",  # 목록용으로 줄임(전체는 상세에)
                "detail": _detail_rows([
                    ("금리", rate), ("한도", f"최대 {it['limit']:,}만원" if it["limit"] else None), ("기간", it["term"]), ("상환 방식", it["repay"]),
                    ("용도", it["usage"]), ("대상", it["target"]), ("지원 조건", it["target_detail"]), ("취급 기관", it["handler"]),
                    ("신청 방법", it["how"]), ("문의", it["phone"]), ("참고", it["note"]),
                ]),
                "url": it["url"],
                "link_label": "취급 기관 사이트",
            }
        )
    return {"live": True, "total": len(pool), "items": out, "usages": chips, "region": region["name"]}
