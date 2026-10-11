# -*- coding: utf-8 -*-
"""고른 사진으로 앱 에셋과 produce_images.json 만들기(일회용).
 입력: 후보 폴더(tools_photo_candidates.py가 만든 <품목>.json) + picks.json({품목: 후보 번호})
 출력: app/assets/produce/<순번>.jpg (16:10, 가로 720px) + backend/data/produce_images.json
        {품목: {asset, credit, license, license_url, page}}  — 화면은 작가만 짧게 보여주고 ⓘ에 나머지를 보여줌.

사용: python tools_build_photos.py <후보폴더> <picks.json>
기존 produce_images.json의 항목 중 picks에 없는 품목은 그대로 둠(앞으로 다시 고르기 전까지 유지).
"""

import io
import json
import sys
import time
from pathlib import Path

import requests
from PIL import Image

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "app" / "assets" / "produce"
DST = HERE / "data" / "produce_images.json"
UA = {"User-Agent": "dailycut-app/1.0 (dkwmsmrdu.sophie@gmail.com)"}

cands_dir = Path(sys.argv[1])
picks = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
out = json.loads(DST.read_text(encoding="utf-8")) if DST.exists() else {}
OUT.mkdir(parents=True, exist_ok=True)

# 기존 에셋 파일은 새 품목 사진으로 덮어쓰이지 않게 새 이름(pNN)으로 이어서 매김
used = {int(p.stem[1:]) for p in OUT.glob("p*.jpg") if p.stem[1:].isdigit()}
nxt = max(used or {0}) + 1

for name, idx in sorted(picks.items()):
    cands = json.loads((cands_dir / f"{name}.json").read_text(encoding="utf-8"))
    c = cands[idx]
    try:
        # 원본은 수 MB라 960px 썸네일을 받음(위키미디어 썸네일 주소 규칙)
        url = c["thumb"].replace("/320px-", "/960px-") if "/320px-" in c["thumb"] else c["thumb"]
        r = requests.get(url, headers=UA, timeout=60)
        if r.status_code != 200:
            r = requests.get(c["thumb"], headers=UA, timeout=60)
        r.raise_for_status()
        im = Image.open(io.BytesIO(r.content)).convert("RGB")
        w, h = im.size
        target = 16 / 10
        if w / h > target:
            nw = int(h * target)
            im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
        else:
            nh = int(w / target)
            im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
        im = im.resize((720, 450), Image.LANCZOS)
        old = out.get(name, {}).get("asset")
        fname = Path(old).name if old else f"p{nxt:02d}.jpg"
        if not old:
            nxt += 1
        im.save(OUT / fname, "JPEG", quality=80, optimize=True)
        out[name] = {
            "asset": f"assets/produce/{fname}",
            "credit": c["artist"],
            "license": c["license"],
            "license_url": c.get("license_url", ""),
            "page": c["page"],
        }
        print(name, fname, c["license"])
    except Exception as e:
        print(name, "ERR", type(e).__name__, str(e)[:80])
    time.sleep(0.5)

DST.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
print("saved", len(out))
