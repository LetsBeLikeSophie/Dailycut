# -*- coding: utf-8 -*-
"""전통시장 CSV(소상공인시장진흥공단_전통시장현황, 공공데이터포털 파일데이터 15052837) →
backend/data/traditional_markets.json 로 줄이는 일회용 스크립트.

사용: python tools_build_markets.py <내려받은 csv 경로>
CSV는 cp949, 휴장일·좌표는 없고 시도/시군구/주소/시설 보유 여부만 있음.
"""

import csv
import io
import json
import sys
from pathlib import Path

import sys
from pathlib import Path as _P
sys.path.insert(0, str(_P(__file__).resolve().parent.parent))  # backend/ (config·geo·sources)
import geo

src = Path(sys.argv[1])
text = src.read_bytes().decode("cp949", errors="replace")
rows = list(csv.DictReader(io.StringIO(text)))

FACILITY = {
    "아케이드 보유 여부": "아케이드",
    "시장전용 고객주차장_보유여부": "주차장",
    "고객휴게실_보유여부": "휴게실",
    "쇼핑카트_보유여부": "카트",
    "수유센터_보유여부": "수유실",
}

out = []
for r in rows:
    code = geo.sido_of_address(r.get("시도") or r.get("도로명주소") or r.get("지번주소"))
    if not code:
        continue
    flags = [label for col, label in FACILITY.items() if (r.get(col) or "").strip().upper().startswith(("Y", "유", "있"))]
    out.append(
        {
            "name": (r.get("시장명") or "").strip(),
            "type": (r.get("시장 유형") or "").strip(),
            "sido": code,
            "sigungu": (r.get("시군구") or "").strip(),
            "addr": (r.get("도로명주소") or r.get("지번주소") or "").strip(),
            "facilities": flags,
        }
    )

dst = Path(__file__).resolve().parent.parent / "data" / "traditional_markets.json"
dst.parent.mkdir(exist_ok=True)
dst.write_text(json.dumps({"source": "소상공인시장진흥공단 전통시장현황(2026-08-04 기준)", "markets": out}, ensure_ascii=False), encoding="utf-8")
from collections import Counter

print(len(out), "곳 →", dst, Counter(m["sido"] for m in out).most_common(5))
print(Counter(f for m in out for f in m["facilities"]))
