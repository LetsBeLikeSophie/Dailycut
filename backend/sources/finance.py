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


def _saving_rank(endpoint: str, term: str = "12", top: int = 5) -> list[dict]:
    """예금/적금: 해당 기간(개월) 옵션의 최고 우대금리 높은 순."""
    bases, options = _all(endpoint)
    by_key = {(b["fin_co_no"], b["fin_prdt_cd"]): b for b in bases}
    best: dict[tuple, dict] = {}
    for o in options:
        if str(o.get("save_trm")) != term or o.get("intr_rate2") is None:
            continue
        k = (o["fin_co_no"], o["fin_prdt_cd"])
        if k in by_key and (k not in best or o["intr_rate2"] > best[k]["intr_rate2"]):
            best[k] = o
    ranked = sorted(best.items(), key=lambda kv: -kv[1]["intr_rate2"])[:top]
    out = []
    for i, (k, o) in enumerate(ranked, 1):
        b = by_key[k]
        base_rate = o.get("intr_rate")
        meta = f"최고 연 {o['intr_rate2']:.2f}%" + (f" (기본 {base_rate:.2f}%)" if base_rate not in (None, o["intr_rate2"]) else "")
        out.append({"rank": i, "title": _name(b), "meta": f"{meta} · {term}개월"})
    return out


def _loan_rank(endpoint: str, field: str, label: str, top: int = 5, min_rate: float = 2.0) -> list[dict]:
    """대출: 최저금리(또는 평균금리) 낮은 순. 상품마다 가장 낮은 값을 대표로."""
    bases, options = _all(endpoint)
    by_key = {(b["fin_co_no"], b["fin_prdt_cd"]): b for b in bases}
    best: dict[tuple, float] = {}
    for o in options:
        v = o.get(field)
        k = (o["fin_co_no"], o["fin_prdt_cd"])
        # 낮은 값(1~2%대)은 금리가 아니라 가산/미적용 값인 경우가 있어 min_rate 미만은 제외
        if v and v >= min_rate and k in by_key and (k not in best or v < best[k]):
            best[k] = v
    ranked = sorted(best.items(), key=lambda kv: kv[1])[:top]
    return [
        {"rank": i, "title": _name(by_key[k]), "meta": f"{label} 연 {v:.2f}%"}
        for i, (k, v) in enumerate(ranked, 1)
    ]


def run() -> dict:
    out: dict = {"finance_source": "금융감독원 금융상품 한눈에 (은행·저축은행)"}
    errors = []
    tasks = {
        "deposits": lambda: _saving_rank("depositProductsSearch"),
        "savings": lambda: _saving_rank("savingProductsSearch"),
        "loans_mortgage": lambda: _loan_rank("mortgageLoanProductsSearch", "lend_rate_min", "최저"),
        "loans_rent": lambda: _loan_rank("rentHouseLoanProductsSearch", "lend_rate_min", "최저"),
        "loans_credit": lambda: _loan_rank("creditLoanProductsSearch", "crdt_grad_avg", "평균", min_rate=3.0),
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
