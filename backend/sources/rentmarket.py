# -*- coding: utf-8 -*-
"""혜택 탭 "전월세 시세"(2026-10-31): 국토교통부 아파트 전월세·오피스텔 전월세 실거래가(공공데이터포털, 이용허락범위 제한 없음 — 2026-10-13 신청서 표기, 쓰기 전에 포털에서 다시 확인할 것).

 - 엔드포인트: apis.data.go.kr/1613000/RTMSDataSvcAptRent/getRTMSDataSvcAptRent · RTMSDataSvcOffiRent/getRTMSDataSvcOffiRent
   (LAWD_CD 법정동 앞 5자리 + DEAL_YMD 계약년월 6자리, 응답은 XML, 한 번에 최대 1,000건 — 강남구 한 달 아파트 전월세가 1,200건대라 페이지를 넘겨 받음).
 - 시군구 5자리 코드는 `outing._targets`(TourAPI 법정동코드)를 그대로 씀. **새 시도 코드(강원 51·전북 52·광주전남 12)도 이 API가 받는 것을 2026-10-31에 확인.**
   시 아래에 구가 나뉜 곳(전주시 → 완산구·덕진구)은 부모 코드의 거래가 0건이라 구 코드들을 합쳐서 받음(`_targets`가 시를 고르면 구를 모두 돌려줌).
 - 보여 주는 것은 "체감" 지표 셋: 아파트 전세(전용 60~85㎡ 보증금 중위) · 아파트 월세(전용 85㎡ 이하 월세 중위) · 오피스텔 월세(월세 중위).
   중위값은 한 달에 5건 이상일 때만 믿고, 달마다 건수가 달라서 "가장 최근 거래가 충분한 달"을 기준으로 한 달 전과 비교함. **우리 자체 가공 통계**이고 원본은 국토부 실거래가 공개시스템(rt.molit.go.kr)이라고 화면에 밝힘.
 - 계약일은 신고 지연이 있어서 이번 달은 늘 덜 찬 상태 → 비교는 지난 달·그 전 달(완결된 달)끼리만.
 - 시군구를 고르지 않으면(시도 전체) 호출이 너무 많아져서(경기 31곳) 안 보여 줌(`need_sgg`).
"""

from __future__ import annotations

import statistics
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor

import requests

import config
import geo
from sources import _cache, _http, _kst, outing

URLS = {
    "apt": "https://apis.data.go.kr/1613000/RTMSDataSvcAptRent/getRTMSDataSvcAptRent",
    "offi": "https://apis.data.go.kr/1613000/RTMSDataSvcOffiRent/getRTMSDataSvcOffiRent",
}
PAGE = 1000
MAX_PAGES = 4
MIN_N = 5  # 한 달 거래가 이보다 적으면 중위값을 믿지 않음
MONTHS = 4  # 이번 달(덜 찬 달) + 지난 3개월


def available() -> bool:
    return bool(config.get_key(_http.KEY_ENV))


def _months(today) -> list[str]:
    """['202610', '202609', '202608', '202607'] — 이번 달부터 거슬러."""
    y, m = today.year, today.month
    out = []
    for _ in range(MONTHS):
        out.append(f"{y}{m:02d}")
        m -= 1
        if m == 0:
            y, m = y - 1, 12
    return out


def _num(s) -> int | None:
    try:
        return int(str(s).replace(",", "").strip() or "0")
    except ValueError:
        return None


def _fetch(kind: str, lawd: str, ym: str) -> list[dict]:
    rows: list[dict] = []
    for page in range(1, MAX_PAGES + 1):
        r = requests.get(
            URLS[kind],
            params={"serviceKey": config.get_key(_http.KEY_ENV), "LAWD_CD": lawd, "DEAL_YMD": ym, "numOfRows": PAGE, "pageNo": page},
            timeout=40,
        )
        if r.status_code != 200:
            break
        root = ET.fromstring(r.content)
        if (root.findtext(".//resultCode") or "") not in ("00", "000"):
            break
        items = [{c.tag: (c.text or "").strip() for c in it} for it in root.iter("item")]
        for it in items:
            dep, rent, area = _num(it.get("deposit")), _num(it.get("monthlyRent")), None
            try:
                area = float(it.get("excluUseAr") or 0)
            except ValueError:
                pass
            if dep is None or rent is None or not area:
                continue
            rows.append({
                "kind": kind, "name": it.get("aptNm") or it.get("offiNm") or "", "umd": it.get("umdNm") or "",
                "area": area, "floor": it.get("floor") or "", "dep": dep, "rent": rent,
                "ym": ym, "day": _num(it.get("dealDay")) or 0,
            })
        total = _num(root.findtext(".//totalCount")) or 0
        if page * PAGE >= total or not items:
            break
    return rows


def _med(xs: list[int]) -> int:
    return int(round(statistics.median(xs)))


def _section(key: str, title: str, basis: str, rows: list[dict], months: list[str], main: str) -> dict:
    """한 지표: 달마다 {ym, n, dep, rent}(건수가 적으면 값은 None)와, 완결된 달 중 최근 두 달 비교."""
    series = []
    for ym in months:
        sel = [r for r in rows if r["ym"] == ym]
        ok = len(sel) >= MIN_N
        series.append({
            "ym": ym, "n": len(sel),
            "dep": _med([r["dep"] for r in sel]) if ok else None,
            "rent": _med([r["rent"] for r in sel]) if ok and main == "rent" else None,
        })
    full = [s for s in series[1:] if s[main] is not None]  # 이번 달(series[0])은 덜 찬 달이라 기준에서 뺌
    now = full[0] if full else None
    prev = full[1] if len(full) > 1 else None
    pct = None
    if now and prev and prev[main]:
        pct = round((now[main] / prev[main] - 1) * 100, 1)
    return {"key": key, "title": title, "basis": basis, "now": now, "prev": prev, "pct": pct, "series": series}


def _build(sido: str | None, sgg: str | None) -> dict:
    area, targets = outing._targets(sido, sgg)
    if not targets:
        raise RuntimeError("전월세 지역 코드를 못 찾음")
    months = _months(_kst.today())
    jobs = [(kind, area + t["code"], ym) for t in targets for kind in URLS for ym in months]
    rows: list[dict] = []
    with ThreadPoolExecutor(max_workers=8) as ex:
        for part in ex.map(lambda j: _fetch(*j), jobs):
            rows.extend(part)
    if not rows:
        raise RuntimeError("전월세 거래 없음")
    apt = [r for r in rows if r["kind"] == "apt"]
    offi = [r for r in rows if r["kind"] == "offi"]
    sections = [
        _section("apt_jeonse", "아파트 전세", "전용 60~85㎡ · 보증금 중위값", [r for r in apt if r["rent"] == 0 and 60 <= r["area"] <= 85], months, "dep"),
        _section("apt_wolse", "아파트 월세", "전용 85㎡ 이하 · 월세 중위값", [r for r in apt if r["rent"] > 0 and r["area"] <= 85], months, "rent"),
        _section("offi_wolse", "오피스텔 월세", "월세 중위값", [r for r in offi if r["rent"] > 0], months, "rent"),
    ]
    rows.sort(key=lambda r: (r["ym"], r["day"]), reverse=True)
    recent = [
        {"name": r["name"], "kind": "아파트" if r["kind"] == "apt" else "오피스텔", "umd": r["umd"], "area": round(r["area"]), "floor": r["floor"],
         "dep": r["dep"], "rent": r["rent"], "date": f"{r['ym'][4:]}.{r['day']:02d}"}
        for r in rows[:10]
    ]
    return {"live": True, "months": months, "sections": sections, "recent": recent, "n": len(rows), "asof": _kst.now().isoformat(timespec="minutes")}


def get(sido: str | None, sgg: str | None = None) -> dict:
    place = geo.place(sido, sgg)
    base = {"region": place["label"], "need_sgg": False, "source": "국토교통부 아파트·오피스텔 전월세 실거래가"}
    if not sgg:
        return {**base, "live": False, "need_sgg": True}
    if not available():
        return {**base, "live": False}
    try:
        data = _cache.cached("rent", f"rent1:{place['key']}", 720, lambda: _build(sido, sgg), shared=True)
    except Exception:
        return {**base, "live": False}
    return {**base, **data}
