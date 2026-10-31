# -*- coding: utf-8 -*-
"""혜택 탭 "지역화폐"(2026-10-31): 한국조폐공사 지역사랑상품권 가맹점 업종별 결제정보(공공데이터포털 15149767, 이용허락범위 제한 없음).

 - 엔드포인트: apis.data.go.kr/B190001/localGiftsKsciPaymentV1/paymentsV1 (신청서의 "요청 주소"에 오퍼레이션 이름이 따로 있음 — 베이스만 부르면 NO_OPENAPI_SERVICE_ERROR 12).
   파라미터는 odcloud식: page·perPage(≤1000)·returnType=JSON·`cond[usage_rgn_cd::EQ]`(사용처 시군구 5자리)·`cond[crtr_ym::EQ]`(기준연월).
   **응답의 totalCount는 전체 데이터(약 2,580만 행) 건수이고 필터가 걸린 건수는 matchCount** — 처음에 totalCount가 안 줄어서 필터가 안 먹는 줄 착각했음.
   한 지역·한 달이 읍면동×업종×성별×연령 행으로 수백~5천 행, 호출 한 번(1,000행)에 5~6초 → 1쪽으로 matchCount를 보고 나머지 쪽은 병렬로 받고, 결과는 하루 캐시.
 - 운영대행사 14곳(코나아이·간편결제진흥원·신한카드·조폐공사·KT·농협 …) 자료를 모은 것이라 지역 구분 없이 전국이 옴. 자료가 없는 지역(상품권이 없는 곳)은 `empty`.
 - 이번 달은 아직 덜 찬 달(10월 중 춘천 73억 vs 9월 117억) → **지난달 이전의 완결된 달**만 씀. 지난달 자료가 아직 없으면 한 달씩 더 거슬러 올라감.
 - 가맹점 기본정보(카드 15108279·모바일 15108285)는 활용신청·호출까지 확인했지만 안 씀: 모바일은 전부 2022-10-30 기준이고 폐업자가 절반 가까이, 카드는 2022~2026 섞여 있어 "쓸 수 있는 가게"로 보여 주기엔 낡음.
   결제정보(15108292)는 업종 구분이 없어 업종별 자료로 충분.
 - 연령대 코드: 01 ~19세, 02 20대, 03 30대, 04 40대, 05 50대, 06 60대 이상(포털 설명은 "01: ~19세 02: 20~29세 03: 30~39세 …"까지만 있고 06은 자료에서 가장 큰 코드라 60세 이상으로 읽음 — 확실하지 않음).
"""

from __future__ import annotations

import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta

import config
import geo
import store
from sources import _cache, _http, _kst, outing

URL = "https://apis.data.go.kr/B190001/localGiftsKsciPaymentV1/paymentsV1"
PAGE = 1000
MAX_PAGES = 12  # 한 지역·달 최대 약 5천 행 — 넉넉히 12쪽
LOOKBACK = 4  # 지난달부터 최대 4달을 거슬러 "자료가 있는 가장 최근 달"을 찾음
AGE_LABELS = {"01": "19세 이하", "02": "20대", "03": "30대", "04": "40대", "05": "50대", "06": "60대 이상"}


def available() -> bool:
    return bool(config.get_key(_http.KEY_ENV))


def _prev_months(today) -> list[str]:
    """['202609', '202608', …] — 지난달부터 거슬러(이번 달은 덜 찬 달이라 뺌)."""
    y, m = today.year, today.month
    out = []
    for _ in range(LOOKBACK):
        m -= 1
        if m == 0:
            y, m = y - 1, 12
        out.append(f"{y}{m:02d}")
    return out


def _page(rgn: str, ym: str, page: int) -> dict:
    return _http.get(
        URL,
        {"page": page, "perPage": PAGE, "returnType": "JSON", "cond[usage_rgn_cd::EQ]": rgn, "cond[crtr_ym::EQ]": ym},
        timeout=60,
    ).json()


def _month_rows(rgn: str, ym: str) -> list[dict]:
    first = _page(rgn, ym, 1)
    rows = list(first.get("data") or [])
    match = int(first.get("matchCount") or 0)
    pages = min((match + PAGE - 1) // PAGE, MAX_PAGES)
    if pages > 1:
        with ThreadPoolExecutor(max_workers=6) as ex:
            for part in ex.map(lambda p: _page(rgn, ym, p).get("data") or [], range(2, pages + 1)):
                rows.extend(part)
    return rows


def _months_rows(codes: list[str], months: list[str]) -> dict[str, list[dict]]:
    """여러 달·여러 구 코드를 한꺼번에(호출 하나가 5~6초라 순서대로 받으면 구가 4개인 수원시는 100초가 넘음)."""
    jobs = [(c, ym) for ym in months for c in codes]
    out: dict[str, list[dict]] = {ym: [] for ym in months}
    with ThreadPoolExecutor(max_workers=4) as ex:
        for (c, ym), rows in zip(jobs, ex.map(lambda j: _month_rows(*j), jobs)):
            out[ym].extend(rows)
    return out


def _totals(rows: list[dict]) -> dict:
    return {"amt": sum(int(r.get("stlm_amt") or 0) for r in rows), "nocs": sum(int(r.get("stlm_nocs") or 0) for r in rows)}


def _build(sido: str | None, sgg: str | None) -> dict:
    area, targets = outing._targets(sido, sgg)
    if not targets:
        raise RuntimeError("지역사랑상품권 지역 코드를 못 찾음")
    codes = [area + t["code"] for t in targets]
    months = _prev_months(_kst.today())
    # 지난달·그 전 달을 먼저 받고, 지난달이 비었으면 더 거슬러 올라감
    got: list[tuple[str, list[dict]]] = []
    for i in range(0, len(months), 2):
        part = _months_rows(codes, months[i:i + 2])
        got.extend((ym, part[ym]) for ym in months[i:i + 2] if part[ym])
        if got:
            break  # 자료가 있는 달을 찾았으면 거기서 멈춤(지난달·그 전 달 둘 다 받아 둔 상태)
    got = got[:2]
    if not got:
        return {"live": True, "empty": True, "asof": _kst.now().isoformat(timespec="minutes")}
    ym, rows = got[0]
    now = {"ym": ym, **_totals(rows)}
    prev = None
    pct = None
    if len(got) > 1:
        pym, prows = got[1]
        prev = {"ym": pym, **_totals(prows)}
        if prev["amt"] > 0:
            pct = round((now["amt"] / prev["amt"] - 1) * 100, 1)
            if abs(pct) > 100:  # 상품권을 막 시작한 곳 등은 배로 뛰어서 비교가 의미 없음
                pct = None

    ind: dict[str, int] = {}
    age: dict[str, int] = {}
    for r in rows:
        amt = int(r.get("stlm_amt") or 0)
        if amt <= 0:
            continue
        name = (r.get("ksic_nm") or "").strip()
        if name:
            ind[name] = ind.get(name, 0) + amt
        code = r.get("par_ag")
        if code in AGE_LABELS:
            age[code] = age.get(code, 0) + amt
    total = now["amt"] or 1
    industries = [{"name": n, "amt": a, "share": round(a / total * 100, 1)} for n, a in sorted(ind.items(), key=lambda x: -x[1])[:6]]
    age_total = sum(age.values()) or 1
    ages = [{"code": c, "label": AGE_LABELS[c], "share": round(age.get(c, 0) / age_total * 100, 1)} for c in AGE_LABELS if age.get(c)]
    return {
        "live": True, "empty": False, "now": now, "prev": prev, "pct": pct,
        "industries": industries, "ages": ages,
        "asof": _kst.now().isoformat(timespec="minutes"),
    }


_TTL = 1440
_inflight: set[str] = set()
_failed: dict[str, datetime] = {}
_lock = threading.Lock()


def _start(key: str, sido: str | None, sgg: str | None) -> None:
    """캐시가 없는 지역은 뒤에서 계산(큰 도시는 30~50초라 한 요청에 묶어 두면 앱이 먼저 포기함) — 앱이 몇 초마다 다시 물어봄."""
    with _lock:
        if key in _inflight:
            return
        _inflight.add(key)

    def work() -> None:
        try:
            _cache.cached("localcur", key, _TTL, lambda: _build(sido, sgg), shared=True)
            _failed.pop(key, None)
        except Exception:
            _failed[key] = datetime.now()
        finally:
            with _lock:
                _inflight.discard(key)

    threading.Thread(target=work, daemon=True).start()


def get(sido: str | None, sgg: str | None = None) -> dict:
    place = geo.place(sido, sgg)
    base = {"region": place["label"], "need_sgg": False, "source": "한국조폐공사 지역사랑상품권 가맹점 업종별 결제정보"}
    if not sgg:
        return {**base, "live": False, "need_sgg": True}
    if not available():
        return {**base, "live": False}
    key = f"lc1:{place['key']}"
    hit = store.load_cache(key, True)
    if hit and datetime.now() - datetime.fromisoformat(hit[1]) < timedelta(minutes=_TTL + 180):
        # 신선하거나 만료 직후(3시간 안)면 바로 — 만료 직후는 cached()가 옛 값을 주고 새 값은 뒤에서 받음
        try:
            return {**base, **_cache.cached("localcur", key, _TTL, lambda: _build(sido, sgg), shared=True)}
        except Exception:
            return {**base, "live": False}
    failed = _failed.get(key)
    if failed and datetime.now() - failed < timedelta(minutes=5):
        return {**base, "live": False}  # 방금 실패한 지역은 5분 동안 다시 시도하지 않음
    _start(key, sido, sgg)
    return {**base, "live": True, "pending": True}
