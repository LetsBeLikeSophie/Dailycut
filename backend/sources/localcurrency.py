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

    ind: dict[str, list[int]] = {}  # 업종 → [금액, 건수]
    age: dict[str, int] = {}
    age_combo: dict[str, dict[tuple, list[int]]] = {}  # 나이대 → (읍면동코드, 읍면동, 업종코드, 업종) → [금액, 건수]
    dong: dict[str, int] = {}
    dong_code: dict[str, str] = {}
    for r in rows:
        amt = int(r.get("stlm_amt") or 0)
        if amt <= 0:
            continue
        nocs = int(r.get("stlm_nocs") or 0)
        name = (r.get("ksic_nm") or "").strip()
        code = r.get("par_ag")
        if name:
            v = ind.setdefault(name, [0, 0])
            v[0] += amt
            v[1] += nocs
        if code in AGE_LABELS:
            age[code] = age.get(code, 0) + amt
            emd_n = (r.get("emd_nm") or "").strip()
            ksic_c = str(r.get("ksic") or "")
            if name and emd_n and ksic_c:
                v = age_combo.setdefault(code, {}).setdefault((str(r.get("emd_cd") or ""), emd_n, ksic_c, name), [0, 0])
                v[0] += amt
                v[1] += nocs
        emd = (r.get("emd_nm") or "").strip()
        if emd:
            dong[emd] = dong.get(emd, 0) + amt
            dong_code.setdefault(emd, str(r.get("emd_cd") or ""))
    total = now["amt"] or 1
    industries = [
        {"name": n, "amt": v[0], "share": round(v[0] / total * 100, 1), "avg": round(v[0] / v[1]) if v[1] else None}
        for n, v in sorted(ind.items(), key=lambda x: -x[1][0])[:6]
    ]
    age_total = sum(age.values()) or 1
    ages = [{"code": c, "label": AGE_LABELS[c], "share": round(age.get(c, 0) / age_total * 100, 1)} for c in AGE_LABELS if age.get(c)]
    # 나이대별 "어느 동네의 어떤 업종에서 많이 쓰나" TOP 6(2026-11-01). 가게별 결제액은 자료에 없어서 가장 잘게 쪼갠 단위가 동네×업종 —
    # 앱에서 줄을 누르면 그 동네·업종의 실제 가맹점 목록(stores)으로 이어짐.
    by_age = {}
    for c, combos in age_combo.items():
        t = age.get(c) or 1
        by_age[c] = [
            {"dong": k[1], "emd": k[0], "ksic": k[2], "cat": k[3], "share": round(v[0] / t * 100, 1), "avg": round(v[0] / v[1]) if v[1] else None}
            for k, v in sorted(combos.items(), key=lambda x: -x[1][0])[:6]
        ]
    dongs = [{"name": n, "code": dong_code.get(n, ""), "share": round(a / total * 100, 1)} for n, a in sorted(dong.items(), key=lambda x: -x[1])[:5]] if len(dong) > 1 else []
    # 가게 찾기의 "동네" 고르기용 전체 목록(결제금액 많은 순, 최대 80곳)
    dong_all = [{"name": n, "code": dong_code.get(n, "")} for n, _ in sorted(dong.items(), key=lambda x: -x[1])[:80] if len(dong_code.get(n, "")) == 8]
    return {
        "live": True, "empty": False, "now": now, "prev": prev, "pct": pct,
        "industries": industries, "ages": ages, "by_age": by_age, "dongs": dongs, "dong_all": dong_all,
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
    key = f"lc5:{place['key']}"  # lc1 → lc2(나이대별 업종·평균 결제·읍면동 순위) → lc3(읍면동 코드, 가맹점 찾기의 동네 필터용) — 응답 모양이 바뀔 때마다 올림(2026-11-01)
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


# ───────── 가맹점 찾기(2026-11-01) ─────────
# 한국조폐공사 가맹점 기본정보(모바일 15108285·카드 15108279)로 "내 동네에서 상품권 쓸 수 있는 가게". 처음엔 "낡았다"고 접었지만
# 맨 앞 몇 줄(2022년·폐업자)만 보고 한 판단이었음 — 춘천은 모바일 3.7만 건 중 2026년 기준이 3.1만, 계속사업자 2.5만(카드는 152건뿐).
# 필터가 서버에서 먹음: usage_rgn_cd(시군구)·emd_cd(읍면동)·ksic_cd(업종 3자리)·bzmn_stts(01 계속 / 03 폐업)·crtr_ymd(GTE)·frcs_nm(LIKE=포함). 호출 하나 2~3초.
# 정렬 옵션이 없어 순서는 서버 기준(무작위처럼 보임). 기준일이 지난 뒤 문을 닫았을 수 있어서 앱에서 "가기 전에 전화로" 안내.
MOBILE_URL = "https://apis.data.go.kr/B190001/mobileFranchisesV4/mobileV4"
CARD_URL = "https://apis.data.go.kr/B190001/cardFranchisesV4/cardV4"
CATS = {  # 앱 칩 → KSIC 3자리(한 칩에 한 코드: 코드마다 호출이 따로라 늘리면 느려짐)
    "food": "561", "cafe": "562", "mart": "471", "grocery": "472", "pharm": "477",
    "beauty": "961", "clinic": "862", "academy": "856", "stay": "551",
}
CAT_NAMES = {"561": "음식점", "562": "카페·주점", "471": "마트·편의점", "472": "식료품", "477": "약국·화장품", "961": "미용·세탁", "862": "병원·의원", "856": "학원", "551": "숙박"}
STORE_PER = 24
_STORE_TTL = timedelta(minutes=30)
_store_memo: dict[str, tuple[datetime, dict]] = {}


def _phone(raw) -> str | None:
    """'0331234567' → '033-123-4567'. 자리표시(0310000000 같은 뒤가 전부 0)는 없는 걸로."""
    d = "".join(c for c in str(raw or "") if c.isdigit())
    if len(d) < 9 or not d.startswith("0") or d[3:].strip("0") == "" or d[2:].strip("0") == "":
        return None
    if d.startswith("02"):
        return f"02-{d[2:-4]}-{d[-4:]}"
    return f"{d[:3]}-{d[3:-4]}-{d[-4:]}"


def _store_item(r: dict, kind: str) -> dict:
    addr = (r.get("frcs_addr") or "").strip()
    return {
        "name": (r.get("frcs_nm") or "").strip(), "addr": addr, "dong": (r.get("emd_nm") or "").strip(),
        "phone": _phone(r.get("frcs_rprs_telno")), "kind": kind,
        "cat": CAT_NAMES.get(str(r.get("ksic_cd") or ""), (r.get("ksic_cd_nm") or "").split(";")[0]),
        "asof": str(r.get("crtr_ymd") or ""),
        "lat": r.get("lat") if isinstance(r.get("lat"), (int, float)) else None,
        "lng": r.get("lot") if isinstance(r.get("lot"), (int, float)) else None,
    }


def stores(sido: str | None, sgg: str | None, q: str = "", cat: str = "", emd: str = "", page: int = 1) -> dict:
    if not sgg:
        return {"live": False, "need_sgg": True}
    if not available():
        return {"live": False}
    q = (q or "").strip()[:20]
    # 업종은 쉼표로 여러 개(칩 키 또는 3자리 업종 코드 — 숫자는 내 또래 줄에서 넘어옴). 없으면 전체
    ksics = []
    for c in (cat or "").split(",")[:6]:
        k = CATS.get(c.strip()) or (c.strip() if c.strip().isdigit() and len(c.strip()) == 3 else None)
        if k and k not in ksics:
            ksics.append(k)
    emd = emd if emd.isdigit() and len(emd) == 8 else ""
    page = max(1, min(page, 50))
    place = geo.place(sido, sgg)
    mkey = f"{place['key']}|{q}|{','.join(sorted(ksics))}|{emd}|{page}"
    hit = _store_memo.get(mkey)
    if hit and datetime.now() - hit[0] < _STORE_TTL:
        return hit[1]
    area, targets = outing._targets(sido, sgg)
    if not targets:
        return {"live": False}
    codes = [area + t["code"] for t in targets][:6]
    cutoff = (_kst.today() - timedelta(days=548)).strftime("%Y%m%d")  # 1년 반보다 오래 갱신 안 된 가게는 뺌
    jobs = [(url, kind, code, k) for url, kind in ((MOBILE_URL, "모바일"), (CARD_URL, "카드")) for code in codes for k in (ksics or [None])]
    per = max(4, -(-STORE_PER // len(jobs)))

    def call(job):
        url, kind, code, ksic = job
        params = {"page": page, "perPage": per, "returnType": "JSON",
                  "cond[usage_rgn_cd::EQ]": code, "cond[bzmn_stts::EQ]": "01", "cond[crtr_ymd::GTE]": cutoff}
        if ksic:
            params["cond[ksic_cd::EQ]"] = ksic
        if emd:
            params["cond[emd_cd::EQ]"] = emd
        if q:
            params["cond[frcs_nm::LIKE]"] = q
        d = _http.get(url, params, timeout=60).json()
        return kind, int(d.get("matchCount") or 0), d.get("data") or []

    items: list[dict] = []
    total = 0
    more = False
    ok = 0
    with ThreadPoolExecutor(max_workers=8) as ex:
        for res in ex.map(lambda j: _safe(call, j), jobs):
            if res is None:
                continue
            ok += 1
            kind, match, rows = res
            total += match
            more = more or match > page * per
            items.extend(_store_item(r, kind) for r in rows)
    if not ok:
        return {"live": False}
    seen: set[tuple[str, str]] = set()
    out = []
    for it in sorted(items, key=lambda x: x["name"]):  # 모바일·카드에 같이 올라온 가게는 한 번만
        k = (it["name"], it["addr"])
        if it["name"] and k not in seen:
            seen.add(k)
            out.append(it)
    result = {"live": True, "total": total, "items": out, "page": page, "has_more": more}
    if len(_store_memo) > 300:
        _store_memo.clear()
    _store_memo[mkey] = (datetime.now(), result)
    return result


def _safe(fn, arg):
    try:
        return fn(arg)
    except Exception:
        return None
