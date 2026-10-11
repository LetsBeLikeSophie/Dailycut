# -*- coding: utf-8 -*-
"""품목별 사진 후보 수집(일회용): 위키미디어 커먼즈에서 검색 → 이용 가능한 라이선스(CC0·PD·CC BY·CC BY-SA)만
추려 작은 썸네일과 메타를 저장하고, 눈으로 고를 수 있게 품목별 컨택트 시트(번호 붙은 썸네일 격자)를 만듦.

사용: python tools_photo_candidates.py <출력폴더> [품목명 ...]   (품목명을 안 주면 전부)
"""

import html
import io
import json
import re
import sys
import time
from pathlib import Path

import requests
from PIL import Image, ImageDraw, ImageFont

UA = {"User-Agent": "dailycut-app/1.0 (dkwmsmrdu.sophie@gmail.com)"}
API = "https://commons.wikimedia.org/w/api.php"
OK = ("cc0", "public domain", "cc by", "cc by-sa", "pd")
BAD_WORDS = ("disease", "pest", "flower", "blossom", "seed", "plant ", "field", "tree", "farm", "harvest", "map", "drawing", "illustration", "painting", "diagram", "flag", "logo", "cooking", "dish", "soup", "stew", "kimchi", "recipe")

# 품목 → 검색어(영문, 앞쪽일수록 우선). 신선해 보이는 "식재료 사진"이 나오도록 품목 이름 위주.
Q = {
    "감자": ["potatoes", "potato tuber"], "고구마": ["sweet potato", "sweet potatoes"], "녹두": ["mung beans", "mung bean"],
    "느타리버섯": ["oyster mushroom Pleurotus ostreatus", "oyster mushrooms"], "땅콩": ["peanuts", "peanut in shell"],
    "보리쌀": ["pearl barley", "barley grains"], "새송이버섯": ["king trumpet mushroom", "Pleurotus eryngii"],
    "쌀": ["rice grains", "uncooked rice"], "참깨": ["sesame seeds", "white sesame"], "찹쌀": ["glutinous rice", "sticky rice uncooked"],
    "콩": ["soybeans", "soybean seeds"], "팥": ["adzuki beans", "azuki beans"], "팽이버섯": ["enoki mushroom", "Flammulina velutipes"],
    "현미": ["brown rice grains", "brown rice"], "혼식곡": ["multigrain rice", "mixed grains rice"],
    "감귤": ["mandarin orange", "satsuma mandarin", "mikan"], "레몬": ["lemons", "lemon fruit"], "망고": ["mango fruit", "mangoes"],
    "바나나": ["bananas", "banana bunch"], "배": ["Asian pear", "nashi pear", "Pyrus pyrifolia"], "블루베리": ["blueberries", "blueberry fruit"],
    "사과": ["apples", "red apple"], "아보카도": ["avocado fruit", "avocados"], "오렌지": ["oranges fruit", "orange fruit"],
    "키위": ["kiwifruit", "kiwi fruit"], "파인애플": ["pineapple fruit", "pineapple"], "포도": ["grapes", "bunch of grapes"],
    "갈치": ["hairtail fish", "cutlassfish", "Trichiurus lepturus"], "고등어": ["mackerel fish", "Scomber japonicus", "Scomber scombrus"],
    "마른멸치": ["dried anchovies", "dried anchovy"], "명태": ["Alaska pollock", "Gadus chalcogrammus"], "물오징어": ["squid fish market", "squid fresh", "Todarodes pacificus"],
    "삼치": ["Spanish mackerel", "Scomberomorus"], "가지": ["eggplant", "aubergine"], "건고추": ["dried chili peppers", "dried red pepper"],
    "고춧가루": ["gochugaru", "Korean chili flakes", "red pepper powder"], "깻잎": ["perilla leaves", "kkaennip", "Perilla frutescens leaf"],
    "당근": ["carrots", "carrot"], "마늘": ["garlic bulbs", "garlic"], "멜론": ["melon fruit", "cantaloupe", "honeydew melon"],
    "무": ["Korean radish", "daikon radish", "mu radish"], "미나리": ["water dropwort", "Oenanthe javanica", "minari"],
    "방울토마토": ["cherry tomatoes", "cherry tomato"], "배추": ["napa cabbage", "Chinese cabbage"], "부추": ["garlic chives", "Allium tuberosum"],
    "붉은고추": ["red chili pepper", "red chilli peppers"], "브로콜리": ["broccoli", "broccoli head"], "상추": ["lettuce leaves", "green leaf lettuce"],
    "생강": ["ginger root", "ginger rhizome"], "수박": ["watermelon", "watermelons"], "시금치": ["spinach leaves", "fresh spinach"],
    "알배기배추": ["mini napa cabbage", "baby napa cabbage", "napa cabbage"], "양배추": ["cabbage head", "green cabbage"], "양파": ["onions", "yellow onion"],
    "얼갈이배추": ["young napa cabbage", "Chinese cabbage leaves"], "열무": ["young radish greens", "yeolmu", "radish greens"],
    "오이": ["cucumbers", "cucumber"], "토마토": ["tomatoes", "tomato fruit"], "파": ["Welsh onion", "scallions", "green onions"],
    "파프리카": ["bell peppers", "paprika"], "풋고추": ["green chili pepper", "green chilli peppers"], "피망": ["green bell pepper", "bell pepper green"],
    "호박": ["zucchini", "Korean zucchini", "courgette"],
    "딸기": ["strawberries", "strawberry fruit"], "단감": ["persimmon fruit", "Diospyros kaki fruit"], "참외": ["Korean melon", "chamoe", "oriental melon"],
    "복숭아": ["peaches", "peach fruit"], "쇠고기": ["raw beef steak", "beef cuts"], "우유": ["milk bottle", "milk glass"],
}


def strip(s):
    return html.unescape(re.sub(r"<[^>]+>", "", s or "")).strip()


def search(term: str, limit: int = 14) -> list[dict]:
    r = requests.get(
        API,
        params={
            "action": "query", "format": "json", "generator": "search", "gsrnamespace": 6, "gsrlimit": limit,
            "gsrsearch": f"{term} filetype:bitmap", "prop": "imageinfo",
            "iiprop": "url|size|mime|extmetadata", "iiurlwidth": 320,
        },
        headers=UA, timeout=30,
    ).json()
    out = []
    for p in (r.get("query", {}).get("pages") or {}).values():
        ii = (p.get("imageinfo") or [None])[0]
        if not ii or ii.get("mime") not in ("image/jpeg", "image/png"):
            continue
        meta = ii.get("extmetadata", {})
        lic = strip(meta.get("LicenseShortName", {}).get("value", ""))
        if not any(lic.lower().startswith(k) for k in OK):
            continue
        title = p["title"]
        low = title.lower() + " " + strip(meta.get("ImageDescription", {}).get("value", "")).lower()[:200]
        if ii["width"] < 700 or ii["height"] < 450 or any(w in low for w in BAD_WORDS):
            continue
        out.append(
            {
                "title": title, "thumb": ii["thumburl"], "url": ii["url"], "page": ii["descriptionurl"],
                "w": ii["width"], "h": ii["height"], "license": lic, "license_url": strip(meta.get("LicenseUrl", {}).get("value", "")),
                "artist": strip(meta.get("Artist", {}).get("value", "")) or "Wikimedia Commons",
                "desc": strip(meta.get("ImageDescription", {}).get("value", ""))[:120],
            }
        )
    return out


def main():
    out_dir = Path(sys.argv[1])
    import os
    if os.environ.get("QFILE"):
        Q.update(json.loads(Path(os.environ["QFILE"]).read_text(encoding="utf-8")))  # 재검색용 검색어 덮어쓰기
    out_dir.mkdir(parents=True, exist_ok=True)
    names = sys.argv[2:] or list(Q)
    font = ImageFont.load_default()
    for ko in names:
        seen, cands = set(), []
        for term in Q[ko]:
            try:
                for c in search(term):
                    if c["title"] not in seen:
                        seen.add(c["title"])
                        cands.append(c)
            except Exception as e:
                print(ko, term, "ERR", type(e).__name__)
            time.sleep(0.5)
        cands = cands[:15]
        thumbs = []
        for c in cands:
            try:
                r = requests.get(c["thumb"], headers=UA, timeout=30)
                r.raise_for_status()
                thumbs.append(Image.open(io.BytesIO(r.content)).convert("RGB"))
            except Exception:
                thumbs.append(Image.new("RGB", (320, 200), "gray"))
            time.sleep(0.25)
        (out_dir / f"{ko}.json").write_text(json.dumps(cands, ensure_ascii=False, indent=1), encoding="utf-8")
        if not thumbs:
            print(ko, "후보 없음")
            continue
        cols, cw, ch = 5, 240, 170
        rows = (len(thumbs) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * cw, rows * (ch + 14)), "white")
        d = ImageDraw.Draw(sheet)
        for i, im in enumerate(thumbs):
            im.thumbnail((cw - 6, ch - 4))
            x, y = (i % cols) * cw, (i // cols) * (ch + 14)
            sheet.paste(im, (x + 3, y + 14))
            d.text((x + 4, y + 1), f"{i}", fill="red", font=font)
        sheet.save(out_dir / f"{ko}.jpg", quality=70)
        print(ko, len(cands))


main()
