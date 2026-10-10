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


def get(code: str) -> dict | None:
    if not DATA.exists():
        return None
    data = _load()
    rows = [m for m in data["markets"] if m["sido"] == code]
    if not rows:
        return None
    # 시설(아케이드·주차장·휴게실…)을 많이 갖춘 시장을 앞으로(대표 시장)
    rows.sort(key=lambda m: (-len(m["facilities"]), m["name"]))
    return {
        "markets_nearby": [
            {"title": m["name"], "meta": " · ".join([m["sigungu"], *m["facilities"][:2]])} for m in rows[:6]
        ],
        "markets_total": len(rows),
        "markets_source": data["source"],
    }
