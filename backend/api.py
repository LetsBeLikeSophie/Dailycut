# -*- coding: utf-8 -*-
"""데일리컷 백엔드 (v0, 뼈대).

기획 문서(https://claude.ai/artifact/U8h2Ukqj5FfBkLaPGVgtBZ)의 "컴포넌트" 표에
나온 필드 그대로 응답 모양을 잡아뒀어요. 아직 공공 API 키를 안 받아서
전부 스텁 데이터 — 실제 연동은 각 함수 안의 TODO 자리에 KAMIS/KOBIS/KOPIS/
TourAPI/ECOS 호출로 교체하면 됨.

실행: uvicorn api:app --reload --port 8010
"""

from __future__ import annotations

import random
from datetime import date, datetime, timedelta

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="데일리컷 API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {"status": "ok"}


# 2026-09-29: 기획 문서에 "생활" 섹션 확정 내용이 추가되면서 날씨가 제일
# 먼저 나옴 — 축제가 맑은 날 위주로 뜨는 것(문화 섹션), 미세먼지 나쁜 날
# 실내 추천처럼 다른 섹션도 같이 쓸 "공통" 데이터라서 /market에 얹지 않고
# 독립 엔드포인트로 뺌.
#
# 2026-09-29(2차): "한국 날씨는 변덕스러우니 네이버 날씨처럼 자세히"
# 요청 — 오늘 하루 요약만으론 부족해서 시간대별(hourly)·주간(weekly)
# 예보를 추가함. (실시간 지역별 채팅 같은 "날씨톡" 기능은 웹소켓·채팅방
# 관리가 필요한 완전히 다른 스코프라 이번엔 보류하기로 함 — 필요해지면
# 별도로 설계.)
#
# TODO: 기상청 단기예보(오늘·시간대별)·중기예보(주간) API
#   (https://www.data.go.kr/data/15084084/openapi.do,
#    https://www.data.go.kr/data/15059468/openapi.do)
# TODO: 에어코리아 대기질 실시간 조회 API (미세먼지)
#   (https://www.data.go.kr/data/15109350/openapi.do)
# 옷차림 추천 / 빨래·세차 좋은 날은 API가 따로 없음 — 기온·강수 확률로
# 자체 규칙(rule-based)을 만들면 됨(AI 호출 없이도 충분).
def _mock_hourly(base_temp: int, hours: int = 8) -> list[dict]:
    rng = random.Random(1)
    now = datetime.now()
    slots = []
    for i in range(hours):
        t = now + timedelta(hours=i * 3)
        drift = round(4 * (0.5 - abs((t.hour - 15) / 24)))
        slots.append(
            {
                "time": t.strftime("%H시"),
                "temp": base_temp + drift + rng.randint(-1, 1),
                "condition": rng.choice(["맑음", "맑음", "구름 조금", "흐림"]),
                "pop": rng.choice([0, 0, 10, 20, 30]),
            }
        )
    return slots


def _mock_weekly(base_high: int, base_low: int, days: int = 6) -> list[dict]:
    rng = random.Random(2)
    weekday_names = ["월", "화", "수", "목", "금", "토", "일"]
    today = date.today()
    out = []
    for i in range(1, days + 1):
        d = today + timedelta(days=i)
        out.append(
            {
                "day": weekday_names[d.weekday()],
                "date": f"{d.month}/{d.day}",
                "high": base_high + rng.randint(-3, 3),
                "low": base_low + rng.randint(-3, 2),
                "condition": rng.choice(["맑음", "구름 많음", "흐림", "비"]),
                "pop": rng.choice([0, 10, 30, 60, 80]),
            }
        )
    return out


@app.get("/weather")
def weather():
    return {
        "today": {"temp": 19, "feels_like": 17, "condition": "맑음", "high": 22, "low": 14},
        "hourly": _mock_hourly(19),
        "weekly": _mock_weekly(22, 14),
        "weekend": "토요일은 흐리고 일요일은 맑아요 — 나들이는 일요일 추천",
        "outfit": "가벼운 니트에 자켓 하나 걸치면 딱 좋아요",
        "good_for": [
            {"label": "빨래", "good": True},
            {"label": "세차", "good": False},
        ],
        "air_quality": {"pm10": "보통", "pm25": "좋음"},
    }


# 2026-09-29: 처음엔 "시세"를 품목 가격 순위만 보여주는 좁은 지표로
# 잡았는데, "주부가 장 볼 때 필요한 생활 물가" 전체로 넓히자는 피드백으로
# 제철 과일/채소를 캡션 한 줄에서 카드로 승격하고, 축산물/생필품/전통시장
# 세 카테고리를 추가함. 각 TODO가 실제 연동할 공공 API.
#
# 2026-09-29(2차): "전주 대비 -18%" 같은 단일 숫자보다 "지금 제철인 게
# 뭔지"가 장보기 의사결정에 더 도움된다는 피드백 — 제철 목록을 화면
# 제일 위(hero 자리)로 올리고, 가격은 텍스트 대신 추이 그래프(ChartCard)
# 로 보여주도록 price_trend를 추가함. 지금은 매일 실제로 값을 저장하는
# 파이프라인이 없어서 결정론적 시드로 그럴듯한 가짜 14일치를 만들어
# 둠(_mock_daily_series) — KAMIS 연동 후엔 진짜 스케줄러가 매일 스냅샷을
# DB에 쌓고 그걸 그대로 반환하면 됨(기획 문서 "다음 할 일"의 "매일 저장해서
# 주간·월간 추이" 항목과 같은 방향). "쌓아서 인사이트에 활용"까지 하려면
# price_history 테이블 + 매일 스냅샷 배치가 별도로 필요함 — 아직 없음.
#
# TODO: KAMIS 농산물유통정보 (https://www.kamis.or.kr/customer/reference/openapi_list.do)
# TODO: 축산물품질평가원 축산물유통정보 (계란·돼지고기·한우 — KAMIS는 농산물만 다룸)
# TODO: 통계청 KOSIS 소비자물가지수 (세제·휴지 등 공산품 — 월별 갱신)
# TODO: 소상공인시장진흥공단 전통시장 현황 (위치·휴장일)
# TODO: price_history 테이블 + 매일 스냅샷 배치 (진짜 추이 그래프·인사이트용)
def _mock_daily_series(item: str, base: int, days: int = 14) -> list[dict]:
    rng = random.Random(hash(item) % 10_000)
    today = date.today()
    values, v = [], float(base)
    for _ in range(days):
        v *= 1 + rng.uniform(-0.035, 0.035)
        values.append(round(v))
    return [
        {"date": (today - timedelta(days=days - 1 - i)).isoformat(), "price": p}
        for i, p in enumerate(values)
    ]


@app.get("/market")
def market():
    trend = _mock_daily_series("배추", 2650)
    return {
        "price_trend": {
            "item": "배추",
            "unit": "원/포기",
            "series": trend,
            "change_pct": round((trend[-1]["price"] - trend[0]["price"]) / trend[0]["price"] * 100, 1),
        },
        "items": [
            {"label": "배추", "value": "2,400원", "change": "down"},
            {"label": "무", "value": "1,800원", "change": "down"},
            {"label": "대파", "value": "3,200원", "change": "flat"},
            {"label": "양파", "value": "2,100원", "change": "up"},
        ],
        "in_season": [
            {"name": "배추", "meta": "김장철 성수품"},
            {"name": "무", "meta": "김장철 성수품"},
            {"name": "단감", "meta": "10~11월 제철"},
            {"name": "고구마", "meta": "9~11월 제철"},
        ],
        "livestock": [
            {"label": "계란(특란 30구)", "value": "6,900원", "change": "flat"},
            {"label": "돼지고기(삼겹살 100g)", "value": "2,450원", "change": "up"},
        ],
        "essentials": [
            {"label": "세제류 물가지수", "value": "+1.8%", "change": "up"},
            {"label": "생활용품 물가지수", "value": "+0.6%", "change": "up"},
        ],
        "markets_nearby": [
            {"title": "OO전통시장", "meta": "휴장일: 매월 둘째·넷째 화요일"},
        ],
    }


# TODO: KOBIS 박스오피스 (https://www.kobis.or.kr/kobisopenapi/homepg/apiservice/searchServiceInfo.do)
# + KOPIS 공연예술통합전산망 + TourAPI 지역 축제
@app.get("/culture")
def culture():
    return {
        "hero": {
            "theme": "culture",
            "title": "어제 박스오피스 1위",
            "poster": None,
            "rank": 1,
            "stat_label": "누적 관객",
            "stat": "182만 명",
        },
        "box_office": [
            {"rank": 1, "title": "영화 A", "meta": "182만 명"},
            {"rank": 2, "title": "영화 B", "meta": "94만 명"},
            {"rank": 3, "title": "영화 C", "meta": "61만 명"},
        ],
        "performances": [{"title": "공연 A", "meta": "이번 주 개막"}],
        "festivals": [{"title": "축제 A", "meta": "이번 주말 · OO시"}],
    }


# TODO: 한국은행 ECOS (https://ecos.bok.or.kr/api/) + 금감원 금융상품 한눈에
@app.get("/money")
def money():
    return {
        "hero": {
            "theme": "money",
            "label": "달러 환율",
            "value": 1350.2,
            "change": "up",
            "series": [1342.1, 1345.0, 1348.5, 1350.2],
        },
        "stats": [
            {"label": "기준금리", "value": "3.50%", "change": "flat"},
            {"label": "소비자물가", "value": "2.1%", "change": "up"},
        ],
        "deposits": [
            {"rank": 1, "title": "은행 A · 정기예금", "meta": "연 4.10%"},
            {"rank": 2, "title": "은행 B · 정기예금", "meta": "연 4.05%"},
        ],
    }


# TODO: Hugging Face Papers API / arXiv API / Epoch AI / Artificial Analysis / SPRi
@app.get("/ai")
def ai():
    return {
        "weekly_article": {
            "title": "이번 주 AI 글 제목(스텁)",
            "highlight": "핵심 한 줄",
            "meta": "2026-09-29",
        },
        "papers": [{"title": "논문 제목 A", "meta": "이번 주 인기 1위"}],
        "new_models": [{"label": "이번 달 새 모델", "value": "12개", "change": "up"}],
    }


@app.get("/today")
def today():
    """투데이(홈) — 섹션별 대표 카드 1개씩만 모아서 반환."""
    m, c, mo, a = market(), culture(), money(), ai()
    season_top = m["in_season"][0]
    market_card = {
        "theme": "market",
        "title": "지금 제철",
        "highlight": season_top["name"],
        "meta": season_top["meta"],
    }
    return {
        "headline": "오늘 한 줄 요약(스텁)",
        "cards": [
            {"section": "market", **market_card},
            {"section": "culture", **c["hero"]},
            {"section": "money", **mo["hero"]},
            {"section": "ai", **a["weekly_article"]},
        ],
    }
