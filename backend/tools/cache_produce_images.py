# -*- coding: utf-8 -*-
"""produce_images.json 의 사진을 내려받아 앱 안에 넣을 크기(16:10, 가로 720px JPEG)로 줄여
app/assets/produce/ 에 저장하고, JSON에 asset 경로를 적음(일회용 도구).
이유: 위키미디어 원본/썸네일은 1~2MB라 느리고, 남의 서버에 매번 의존하면 깨질 수 있음.
출처·라이선스(credit/license/page)는 JSON에 그대로 두고 화면에 표시함.

사용: python tools_cache_produce_images.py
"""

import io
import json
import time
from pathlib import Path

import requests
from PIL import Image

HERE = Path(__file__).resolve().parent.parent  # backend/
SRC = HERE / "data" / "produce_images.json"
OUT = HERE.parent / "app" / "assets" / "produce"
OUT.mkdir(parents=True, exist_ok=True)
UA = {"User-Agent": "dailycut-app/1.0 (dkwmsmrdu.sophie@gmail.com)"}

data = json.loads(SRC.read_text(encoding="utf-8"))
for i, (name, info) in enumerate(sorted(data.items()), 1):
    try:
        r = requests.get(info["url"], headers=UA, timeout=60)
        r.raise_for_status()
        im = Image.open(io.BytesIO(r.content)).convert("RGB")
        # 가운데를 16:10으로 자름
        w, h = im.size
        target = 16 / 10
        if w / h > target:
            nw = int(h * target)
            im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
        else:
            nh = int(w / target)
            im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
        im = im.resize((720, 450), Image.LANCZOS)
        path = OUT / f"p{i:02d}.jpg"
        im.save(path, "JPEG", quality=80, optimize=True)
        info["asset"] = f"assets/produce/{path.name}"
        print(name, path.name, path.stat().st_size // 1024, "KB")
    except Exception as e:
        print(name, "ERR", type(e).__name__, str(e)[:80])
    time.sleep(0.5)

SRC.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
print("done", sum(1 for v in data.values() if v.get("asset")), "/", len(data))
