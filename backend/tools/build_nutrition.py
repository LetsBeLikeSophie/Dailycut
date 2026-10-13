# -*- coding: utf-8 -*-
"""장보기 품목별 영양(100g 기준)을 식약처 식품영양성분DB에서 뽑아 data/nutrition.json으로 저장(한 번만 돌리면 됨 — 영양값은 안 변함).

 python backend/tools/build_nutrition.py

 - 이름으로만 찾으면 조리·가공식품이 먼저 나와서 `FOOD_CAT1_NM`(대분류)로 거른 "원재료성" 행에서 찾음.
 - 품목 이름으로 시작하고 "생것"인 행 중 가장 짧은 이름(= 대표)을 고름. 못 찾거나 애매한 품목은 건너뛰고 목록으로 알려 줌.
 - 열량 AMT_NUM1(kcal), 수분 NUM2, 단백질 NUM3, 지방 NUM4, 탄수화물 NUM6, 당류 NUM7, 식이섬유 NUM8 (g).
 - 호출 실패 때 주소(인증키 포함)가 출력에 안 나오게 예외 내용은 찍지 않음.
"""

import json
import os
import re
import sys

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import config  # noqa: E402

KEY = config.get_key("DATA_GO_KR_SERVICE_KEY_DECODED")
BASE = (config.get_key("MFDS_FOOD_NUTRITION_BASE_URL") or "https://apis.data.go.kr/1471000/FoodNtrCpntDbInfo03") + "/getFoodNtrCpntDbInq03"
CATS = ["채소류", "과일류", "감자 및 전분류", "곡류", "두류", "어패류", "육류", "난류", "버섯류", "견과 및 종실류", "해조류", "조미료류"]  # 대분류는 부분 일치로 거름(이름은 2026-10-14 실제 호출로 확인)


def fetch_cat(cat: str) -> list[dict]:
    rows: list[dict] = []
    for page in range(1, 30):
        try:
            r = requests.get(BASE, params={"serviceKey": KEY, "pageNo": page, "numOfRows": 100, "type": "json", "FOOD_CAT1_NM": cat}, timeout=60)
            body = r.json().get("body", {})
        except Exception as e:
            print("  호출 실패", cat, page, type(e).__name__)
            break
        items = body.get("items") or []
        rows += items
        if len(rows) >= int(body.get("totalCount") or 0) or not items:
            break
    return rows


def main() -> None:
    guide = json.load(open(os.path.join(os.path.dirname(HERE), "data", "produce_guide.json"), encoding="utf-8"))["items"]
    allrows: list[dict] = []
    for c in CATS:
        got = fetch_cat(c)
        print(c, len(got))
        allrows += got
    raw = [r for r in allrows if r.get("DB_GRP_NM") == "원재료성"]
    print("원재료성", len(raw))
    out, miss = {}, []
    for name in guide:
        cands = [r for r in raw if r["FOOD_NM_KR"].startswith(name + ",") or r["FOOD_NM_KR"] == name]
        fresh = [r for r in cands if "생것" in r["FOOD_NM_KR"] and "말린" not in r["FOOD_NM_KR"]]
        # 먹는 부위가 따로 있는 품목(고구마·호박)은 잎·줄기·순·꽃 행을 뒤로 미룸
        def odd_part(r):
            return any(f", {w}" in r["FOOD_NM_KR"] for w in ("잎", "줄기", "순", "새싹", "꽃", "껍질"))

        pick = sorted(fresh or [], key=lambda r: (odd_part(r), len(r["FOOD_NM_KR"]), r["FOOD_NM_KR"]))
        if not pick:
            miss.append(name)
            continue
        p = pick[0]

        def num(k):
            try:
                return round(float(p.get(k)), 1)
            except (TypeError, ValueError):
                return None

        out[name] = {"ref": p["FOOD_NM_KR"], "kcal": num("AMT_NUM1"), "protein": num("AMT_NUM3"), "fat": num("AMT_NUM4"), "carb": num("AMT_NUM6"), "sugar": num("AMT_NUM7"), "fiber": num("AMT_NUM8")}
    json.dump({"source": "식품의약품안전처 식품영양성분DB(원재료성 식품, 생것, 100g 기준)", "items": out}, open(os.path.join(os.path.dirname(HERE), "data", "nutrition.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("매칭", len(out), "/", len(guide))
    for k, v in out.items():
        print(f"  {k:6s} <- {v['ref'][:40]:40s} {v['kcal']}kcal")
    print("못 찾음:", miss)


if __name__ == "__main__":
    main()
