# -*- coding: utf-8 -*-
"""머니 수집(금융감독원 '금융상품 한눈에' 오픈API): 예·적금 금리, 대출 금리.

주식·금(sources/money.py)은 시세 쪽이고, 여기는 생활 금융 쪽 — 예금·적금 최고금리 순위,
주택담보대출·전세자금대출·신용대출 최저/평균 금리. 업권은 은행(020000)과 저축은행(030300).
금융회사가 분기·월 단위로 공시한 값이라 하루 한 번만 받아도 충분함(6시간 주기).
응답에 덮어쓰는 필드: deposits, savings, loans_mortgage, loans_rent, loans_credit, finance_source.
키는 FINLIFE_API_KEY(.env). 비상업적 이용으로 신청했으니 광고·유료 기능을 붙이면 약관을 다시 확인할 것.
"""

from __future__ import annotations

import time

import requests

import config
import jobs

BASE = "https://finlife.fss.or.kr/finlifeapi"
GROUPS = ("020000", "030300")  # 은행, 저축은행
GROUP_LABEL = {"020000": "은행", "030300": "저축은행"}


def _get(endpoint: str, group: str, page: int) -> dict:
    """키가 든 URL이 오류 메시지에 섞이지 않게 요청 예외를 짧은 문구로 바꾸고, 연결이 끊기면 한 번 재시도."""
    key = config.get_key("FINLIFE_API_KEY")
    if not key:
        raise RuntimeError("FINLIFE_API_KEY 없음")
    last = "요청 실패"
    for attempt in range(3):
        try:
            r = requests.get(f"{BASE}/{endpoint}.json", params={"auth": key, "topFinGrpNo": group, "pageNo": page}, timeout=20)
            if r.status_code != 200:
                raise RuntimeError(f"HTTP {r.status_code}")
            result = r.json().get("result", {})
            if result.get("err_cd") not in (None, "000"):
                raise RuntimeError(f"API 오류 {result.get('err_cd')} {result.get('err_msg')}")
            return result
        except requests.RequestException as e:
            last = f"요청 실패({type(e).__name__})"
            time.sleep(1.5)
    raise RuntimeError(last)


def _all(endpoint: str) -> tuple[list[dict], list[dict]]:
    """업권별로 모든 쪽을 받아 (상품 기본정보, 금리 옵션) 목록으로 합침. 업권 이름은 base에 붙임."""
    bases, options = [], []
    for g in GROUPS:
        page, max_page = 1, 1
        while page <= max_page and page <= 10:
            res = _get(endpoint, g, page)
            max_page = int(res.get("max_page_no") or 1)
            for b in res.get("baseList") or []:
                b["_group"] = GROUP_LABEL[g]
                bases.append(b)
            options += res.get("optionList") or []
            page += 1
    return bases, options


def _name(b: dict) -> str:
    return f"{b['kor_co_nm']} · {b['fin_prdt_nm']}"


SITE = "https://finlife.fss.or.kr"
LINKS = {
    "deposits": SITE + "/finlife/svings/fdrmDpst/list.do?menuNo=700002",
    "savings": SITE + "/finlife/svings/fdrmEnty/list.do?menuNo=700003",
    "loans_mortgage": SITE + "/finlife/ldng/houseMrtg/list.do?menuNo=700007",
    "loans_rent": SITE + "/finlife/ldng/lfstsFunds/list.do?menuNo=700008",
    "loans_credit": SITE + "/finlife/ldng/indvlCrdt/list.do?menuNo=700009",
}
JOIN_DENY = {"1": "제한 없음", "2": "서민 전용", "3": "일부 제한"}
CREDIT_GRADES = [  # 신용점수 구간별 금리(crdt_grad_N) 라벨
    ("crdt_grad_1", "900점 초과"), ("crdt_grad_4", "801~900점"), ("crdt_grad_5", "701~800점"), ("crdt_grad_6", "601~700점"),
    ("crdt_grad_10", "501~600점"), ("crdt_grad_11", "401~500점"), ("crdt_grad_12", "301~400점"), ("crdt_grad_13", "300점 이하"),
]


def _clean(v) -> str | None:
    t = str(v).strip() if v not in (None, "") else ""
    return t.replace("\\n", "\n") or None


def _info(pairs: list[tuple[str, object]]) -> list[dict]:
    return [{"label": k, "value": _clean(v)} for k, v in pairs if _clean(v)]


def _saving_rank(endpoint: str, key: str, term: str = "12", top: int = 5) -> list[dict]:
    """예금/적금: 해당 기간(개월) 옵션의 최고 우대금리 높은 순 + 상품 상세(우대조건, 기간별 금리 등)."""
    bases, options = _all(endpoint)
    by_key = {(b["fin_co_no"], b["fin_prdt_cd"]): b for b in bases}
    opts: dict[tuple, list[dict]] = {}
    for o in options:
        opts.setdefault((o["fin_co_no"], o["fin_prdt_cd"]), []).append(o)
    best: dict[tuple, dict] = {}
    for k, os_ in opts.items():
        for o in os_:
            if str(o.get("save_trm")) != term or o.get("intr_rate2") is None:
                continue
            if k in by_key and (k not in best or o["intr_rate2"] > best[k]["intr_rate2"]):
                best[k] = o
    ranked = sorted(best.items(), key=lambda kv: -kv[1]["intr_rate2"])[:top]
    out = []
    for i, (k, o) in enumerate(ranked, 1):
        b = by_key[k]
        base_rate = o.get("intr_rate")
        rates = sorted(
            (
                {
                    "label": f"{x['save_trm']}개월" + (f" · {x['rsrv_type_nm']}" if x.get("rsrv_type_nm") else "") + (f" · {x.get('intr_rate_type_nm', '')}" if x.get("intr_rate_type_nm") else ""),
                    "value": (
                        f"{x['intr_rate2']:.2f}%"
                        if x.get("intr_rate") in (None, x.get("intr_rate2"))
                        else f"기본 {x['intr_rate']:.2f}% → 최고 {x['intr_rate2']:.2f}%"
                    )
                    if x.get("intr_rate2") is not None
                    else "-",
                    "_t": int(x["save_trm"]) if str(x.get("save_trm", "")).isdigit() else 99,
                }
                for x in opts.get(k, [])
            ),
            key=lambda r: r["_t"],
        )
        for r in rates:
            r.pop("_t")
        meta = f"최고 연 {o['intr_rate2']:.2f}%" + (f" (기본 {base_rate:.2f}%)" if base_rate not in (None, o["intr_rate2"]) else "")
        out.append(
            {
                "rank": i,
                "company": b["kor_co_nm"],
                "product": b["fin_prdt_nm"],
                "group": b["_group"],
                "title": _name(b),
                "meta": f"{meta} · {term}개월",
                "value": f"{o['intr_rate2']:.2f}%",
                "value_sub": f"기본 {base_rate:.2f}%" if base_rate not in (None, o["intr_rate2"]) else "우대 없음",
                "term": f"{term}개월",
                "info": _info(
                    [
                        ("업권", b["_group"]),
                        ("가입 방법", b.get("join_way")),
                        ("가입 대상", b.get("join_member") or JOIN_DENY.get(str(b.get("join_deny")))),
                        ("최고 한도", f"{b['max_limit']:,}원" if isinstance(b.get("max_limit"), (int, float)) else b.get("max_limit")),
                        ("만기 후 이자율", b.get("mtrt_int")),
                        ("우대 조건", b.get("spcl_cnd")),
                        ("기타", b.get("etc_note")),
                        ("공시 기준월", b.get("dcls_month") or o.get("dcls_month")),
                    ]
                ),
                "rates": rates,
                "link": LINKS[key],
            }
        )
    return out


def _loan_rank(endpoint: str, key: str, field: str, label: str, top: int = 5, min_rate: float = 2.0) -> list[dict]:
    """대출: 최저금리(또는 평균금리) 낮은 순. 상품마다 가장 낮은 값을 대표로 + 상품 상세."""
    bases, options = _all(endpoint)
    by_key = {(b["fin_co_no"], b["fin_prdt_cd"]): b for b in bases}
    opts: dict[tuple, list[dict]] = {}
    for o in options:
        opts.setdefault((o["fin_co_no"], o["fin_prdt_cd"]), []).append(o)
    best: dict[tuple, float] = {}
    for k, os_ in opts.items():
        for o in os_:
            v = o.get(field)
            # 낮은 값(1~2%대)은 금리가 아니라 가산/미적용 값인 경우가 있어 min_rate 미만은 제외
            if v and v >= min_rate and k in by_key and (k not in best or v < best[k]):
                best[k] = v
    ranked = sorted(best.items(), key=lambda kv: kv[1])[:top]
    out = []
    for i, (k, v) in enumerate(ranked, 1):
        b = by_key[k]
        rates = []
        for o in opts.get(k, []):
            if key == "loans_credit":
                grades = [{"label": lab, "value": f"{o[col]:.2f}%"} for col, lab in CREDIT_GRADES if o.get(col)]
                if grades:
                    rates = grades
                    break
            else:
                lo, hi = o.get("lend_rate_min"), o.get("lend_rate_max")
                rates.append(
                    {
                        "label": " · ".join(x for x in (o.get("mrtg_type_nm"), o.get("rpay_type_nm"), o.get("lend_rate_type_nm")) if x) or "금리",
                        "value": f"{lo:.2f}~{hi:.2f}%" if lo and hi else (f"{lo:.2f}%" if lo else "-"),
                    }
                )
        out.append(
            {
                "rank": i,
                "company": b["kor_co_nm"],
                "product": b["fin_prdt_nm"],
                "group": b["_group"],
                "title": _name(b),
                "meta": f"{label} 연 {v:.2f}%",
                "value": f"{v:.2f}%",
                "value_sub": label,
                "term": None,
                "info": _info(
                    [
                        ("업권", b["_group"]),
                        ("가입 방법", b.get("join_way")),
                        ("상품 유형", b.get("crdt_prdt_type_nm")),
                        ("신용평가사", b.get("cb_name")),
                        ("대출 한도", b.get("loan_lmt")),
                        ("대출 부대비용", b.get("loan_inci_expn")),
                        ("중도상환 수수료", b.get("erly_rpay_fee")),
                        ("연체 이자율", b.get("dly_rate")),
                        ("공시 기준월", b.get("dcls_month")),
                    ]
                ),
                "rates": rates[:12],
                "rates_title": "신용점수 구간별 금리" if key == "loans_credit" else "금리 구분별 범위",
                "link": LINKS[key],
            }
        )
    return out


def run() -> dict:
    out: dict = {"finance_source": "금융감독원 금융상품 한눈에 (은행·저축은행)"}
    errors = []
    tasks = {
        "deposits": lambda: _saving_rank("depositProductsSearch", "deposits"),
        "savings": lambda: _saving_rank("savingProductsSearch", "savings"),
        "loans_mortgage": lambda: _loan_rank("mortgageLoanProductsSearch", "loans_mortgage", "lend_rate_min", "최저"),
        "loans_rent": lambda: _loan_rank("rentHouseLoanProductsSearch", "loans_rent", "lend_rate_min", "최저"),
        "loans_credit": lambda: _loan_rank("creditLoanProductsSearch", "loans_credit", "crdt_grad_avg", "평균", min_rate=3.0),
    }
    for key, fn in tasks.items():
        try:
            rows = fn()
            if rows:
                out[key] = rows
        except Exception as e:
            errors.append(f"{key}: {e}")
    if len(out) == 1:
        raise RuntimeError("; ".join(errors) or "금리 데이터 없음")
    return out


jobs.register(jobs.Job(name="finance", run=run, env_keys=["FINLIFE_API_KEY"], interval_min=360))
