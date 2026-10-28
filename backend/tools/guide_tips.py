# -*- coding: utf-8 -*-
"""produce_guide.json에 "팁" 분류 추가(일회용 이전 스크립트).
 - note(한 줄 메모)와, good·storage 안에 라벨이 '팁'·'당도'·'주의'로 섞여 있던 항목을 `tips`(문장 목록)로 옮김.
 - 팁이 없는 품목은 tips가 빈 목록(화면에서 섹션을 안 보여줌).
이미 옮긴 데이터에 다시 돌려도 안전함(note가 비어 있으면 건너뜀).
"""
import json
from pathlib import Path

P = Path(__file__).resolve().parent.parent / "data" / "produce_guide.json"
d = json.loads(P.read_text(encoding="utf-8"))
TIP_LABELS = {"팁", "당도", "주의"}
moved = 0
for name, it in d["items"].items():
    tips = list(it.get("tips") or [])
    for key in ("good", "storage"):
        keep = []
        for row in it.get(key, []):
            if row[0] in TIP_LABELS:
                tips.append(row[1].rstrip("."))
                moved += 1
            else:
                keep.append(row)
        it[key] = keep
    note = (it.pop("note", "") or "").strip().rstrip(".")
    if note:
        tips.append(note)
        moved += 1
    # 중복 제거(순서 유지)
    seen, uniq = set(), []
    for t in tips:
        if t not in seen:
            seen.add(t)
            uniq.append(t)
    it["tips"] = uniq
P.write_text(json.dumps(d, ensure_ascii=False, indent=1), encoding="utf-8")
print("moved", moved, "items with tips:", sum(1 for v in d["items"].values() if v["tips"]), "/", len(d["items"]))
