# -*- coding: utf-8 -*-
"""제철 품목 사진 수집(일회용): 위키백과 문서의 대표 이미지를 가져와서 위키미디어 공용(Commons)
라이선스를 확인하고, 이용 가능한 것(CC0·퍼블릭 도메인·CC BY·CC BY-SA)만
backend/data/produce_images.json 에 저장함. 사진 위에 출처·라이선스를 화면에 표시해야 함.

사용: python tools_build_produce_images.py
무분별한 이미지 검색 대신 "그 품목 문서의 대표 사진"을 쓰는 이유: 검색은 병해·꽃가루 사진 같은
엉뚱한 결과가 많고, 대표 사진은 편집자가 고른 것이라 정확하고 라이선스 정보도 일관됨.
"""

import html
import json
import re
import time
from pathlib import Path

import requests

UA = {"User-Agent": "dailycut-app/1.0 (dkwmsmrdu.sophie@gmail.com)"}
# 품목 → 위키백과(영문) 문서 제목
TITLES = {
    "배추": "Napa cabbage", "무": "Daikon", "양파": "Onion", "당근": "Carrot", "감자": "Potato",
    "고구마": "Sweet potato", "오이": "Cucumber", "호박": "Zucchini", "상추": "Lettuce", "시금치": "Spinach",
    "파": "Scallion", "마늘": "Garlic", "토마토": "Tomato", "가지": "Eggplant", "양배추": "Cabbage",
    "브로콜리": "Broccoli", "깻잎": "Perilla frutescens", "사과": "Apple", "배": "Pyrus pyrifolia",
    "단감": "Diospyros kaki", "감귤": "Mandarin orange", "포도": "Grape", "딸기": "Strawberry",
    "수박": "Watermelon", "참외": "Korean melon", "복숭아": "Peach", "고등어": "Atlantic mackerel",
    "갈치": "Largehead hairtail", "오징어": "Squid", "쇠고기": "Beef", "우유": "Milk",
}
OK_LICENSES = ("cc0", "public domain", "cc by", "cc by-sa", "pd")


def strip(s: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", s or "")).strip()


out = {}
for ko, title in TITLES.items():
    try:
        r = requests.get(
            "https://en.wikipedia.org/w/api.php",
            params={"action": "query", "format": "json", "redirects": 1, "titles": title, "prop": "pageimages", "piprop": "name", "pithumbsize": 640},
            headers=UA, timeout=20,
        ).json()
        page = next(iter(r["query"]["pages"].values()))
        fname = page.get("pageimage")
        if not fname:
            print(ko, "대표 이미지 없음")
            continue
        info = requests.get(
            "https://commons.wikimedia.org/w/api.php",
            params={"action": "query", "format": "json", "titles": f"File:{fname}", "prop": "imageinfo", "iiprop": "url|extmetadata", "iiurlwidth": 640},
            headers=UA, timeout=20,
        ).json()
        ii = next(iter(info["query"]["pages"].values()))["imageinfo"][0]
        meta = ii["extmetadata"]
        lic = strip(meta.get("LicenseShortName", {}).get("value", ""))
        if not any(lic.lower().startswith(k) for k in OK_LICENSES):
            print(ko, "라이선스 부적합:", lic)
            continue
        out[ko] = {
            "url": ii.get("thumburl") or ii["url"],
            "page": ii.get("descriptionurl"),
            "credit": strip(meta.get("Artist", {}).get("value", "")) or "Wikimedia Commons",
            "license": lic,
        }
        print(ko, "OK", lic, fname[:50])
    except Exception as e:
        print(ko, "ERR", type(e).__name__, str(e)[:80])
    time.sleep(0.4)

dst = Path(__file__).resolve().parent.parent / "data" / "produce_images.json"
dst.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
print(len(out), "/", len(TITLES), "→", dst)
