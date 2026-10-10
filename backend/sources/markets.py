# -*- coding: utf-8 -*-
"""전통시장(시도별): 소상공인시장진흥공단 전통시장현황 파일 데이터(2026-08-04 기준).

API가 아니라 공공데이터포털에서 내려받는 CSV라서 backend/data/traditional_markets.json 으로
줄여 저장해 둠(tools_build_markets.py). 휴장일·좌표는 데이터에 없어서 "어느 시도에 어떤
시장이 있고 아케이드·주차장이 있는지"까지만 보여줌. 키가 필요 없어서 항상 실데이터(정적).
응답에 덮어쓰는 필드: markets_nearby, markets_total, markets_source.
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data" / "traditional_markets.json"


@lru_cache(maxsize=1)
def _load() -> dict:
    return json.loads(DATA.read_text(encoding="utf-8"))


def get(code: str, sgg: str | None = None) -> dict | None:
    """고른 시군구의 전통시장(없으면 시도 전체). 시설 많은 순이 기본, 화면에서 필터·정렬을 바꿈."""
    if not DATA.exists():
        return None
    import geo

    data = _load()
    in_sido = [m for m in data["markets"] if m["sido"] == code]
    if not in_sido:
        return None
    place = geo.place(code, sgg)
    local = [m for m in in_sido if place["names"] and m["sigungu"] in place["names"]]
    rows = local or in_sido
    scope = place["label"] if local else place["sido"]
    rows = sorted(rows, key=lambda m: (-len(m["facilities"]), m["name"]))
    return {
        "markets_nearby": [
            {
                "title": m["name"],
                "meta": " · ".join([m["sigungu"], *m["facilities"][:2]]),
                "type": m["type"],
                "sigungu": m["sigungu"],
                "addr": m["addr"],
                "facilities": m["facilities"],
            }
            for m in rows
        ],
        "markets_total": len(rows),
        "markets_scope": scope,
        "markets_source": data["source"],
    }


# ---------------- 시장 상세(사진): 한국관광공사 TourAPI 키워드 검색 ----------------
import config  # noqa: E402
from sources import _cache, _http  # noqa: E402

PHOTO_HOSTS = ("tong.visitkorea.or.kr",)


def detail(name: str, sigungu: str | None) -> dict:
    """시장 이름으로 한국관광공사 관광정보를 찾아 사진을 가져옴(있을 때만).
    사진은 "출처표시·상업적 이용 허용"(Type1)인 것만 씀 — 변경금지(Type3)는 화면에서 잘라서 쓰기 때문에 제외."""

    def load() -> dict:
        base = config.get_key("TOUR_API_BASE_URL")
        body = _http.get_json(
            base + "/searchKeyword2",
            {
                "MobileOS": config.get_key("TOUR_API_MOBILE_OS"),
                "MobileApp": config.get_key("TOUR_API_MOBILE_APP"),
                "_type": "json",
                "keyword": name,
                "numOfRows": 10,
                "pageNo": 1,
            },
        )
        for it in _http.items_of(body):
            addr = it.get("addr1") or ""
            same_place = (not sigungu) or sigungu in addr
            if it.get("title", "").replace(" ", "").startswith(name.replace(" ", "")[:4]) and same_place and it.get("firstimage") and it.get("cpyrhtDivCd") == "Type1":
                return {"found": True, "title": it["title"], "addr": addr, "image": it["firstimage"], "tel": it.get("tel") or None}
        return {"found": False}

    if not config.has_keys(["DATA_GO_KR_SERVICE_KEY_DECODED", "TOUR_API_BASE_URL", "TOUR_API_MOBILE_OS", "TOUR_API_MOBILE_APP"]):
        return {"found": False}
    try:
        return _cache.cached("market_detail", f"mkt:{name}:{sigungu or ''}", 60 * 24 * 7, load)
    except Exception:
        return {"found": False}
