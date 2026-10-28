# -*- coding: utf-8 -*-
"""시군구 지역 마스터 생성: 에어코리아 측정소 목록(주소·좌표)에서 시도→시군구 목록, 시군구 중심 좌표,
소속 측정소, "구" 별칭(수원시 팔달구 → 수원시)을 뽑아 backend/data/regions.json 으로 저장.

사용: python tools_build_regions.py  (.env의 포털 키 필요, 17번 호출)
왜 측정소인가: 전국 시군구를 다 갖고 중심 좌표까지 주는 공공 API/파일이 따로 없는데, 측정소가
거의 모든 시군구에 있고 주소가 "서울 중구 …" 꼴이라 시군구 이름과 좌표를 함께 얻을 수 있음.
측정소가 없는 시군구는 목록에서 빠짐(그 지역은 시도 전체로 선택).
"""

import json
from collections import defaultdict
from pathlib import Path

import sys
from pathlib import Path as _P
sys.path.insert(0, str(_P(__file__).resolve().parent.parent))  # backend/ (config·geo·sources)
import config
import geo
from sources import _http

base = config.get_key("AIRKOREA_STATION_BASE_URL") + "/getMsrstnList"
rows = []
for r in geo.REGIONS:
    body = _http.get_json(base, {"returnType": "json", "numOfRows": 500, "pageNo": 1, "addr": r[2]}, timeout=60)
    rows += _http.items_of(body)

groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
aliases: dict[tuple[str, str], set[str]] = defaultdict(set)
for r in rows:
    toks = (r.get("addr") or "").split()
    code = geo.sido_of_address(toks[0]) if toks else None
    if not code or len(toks) < 2:
        continue
    sg = "세종시" if code == "36" else toks[1]
    try:
        lat, lon = float(r["dmX"]), float(r["dmY"])
    except (KeyError, ValueError):
        continue
    groups[(code, sg)].append({"name": r["stationName"], "lat": lat, "lon": lon})
    if len(toks) > 2 and toks[1].endswith("시") and toks[2].endswith("구"):
        aliases[(code, sg)].add(toks[2])

sidos = []
for code, name, _air, _la, _lo, _p in geo.REGIONS:
    sgs = []
    for (c, sg), sts in sorted(groups.items(), key=lambda kv: kv[0][1]):
        if c != code:
            continue
        sgs.append(
            {
                "id": f"{name} {sg}",
                "name": sg,
                "lat": round(sum(s["lat"] for s in sts) / len(sts), 4),
                "lon": round(sum(s["lon"] for s in sts) / len(sts), 4),
                "stations": [s["name"] for s in sts],
                "aliases": sorted(aliases.get((c, sg), [])),
            }
        )
    sidos.append({"code": code, "name": name, "sigungu": sgs})

dst = Path(__file__).resolve().parent.parent / "data" / "regions.json"
dst.write_text(json.dumps({"source": "에어코리아 측정소 주소·좌표로 생성", "sidos": sidos}, ensure_ascii=False), encoding="utf-8")
print(sum(len(s["sigungu"]) for s in sidos), "개 시군구 →", dst)
