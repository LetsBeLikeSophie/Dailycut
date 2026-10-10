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
        # 2026-10-06: "출처 표시가 하나도 없다"는 지적 — 기획 문서 원칙
        # ("모든 데이터 카드에는 출처를 표시")을 처음 반영함. 지금은 TODO
        # 상태라 실제 기상청 연동 전이지만, 나중에 실제 소스로 자연스럽게
        # 바뀌게 문자열 하나로 빼둠.
        "source": "기상청",
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


def _mini_series(label: str, price: int, change: str, points: int = 8) -> list[int]:
    """목록 행 옆에 그리는 작은 추이선용 스텁 — 마지막 값이 price이고
    change(up/down/flat) 방향으로 흐르게 결정론적으로 만듦."""
    rng = random.Random(sum(ord(c) for c in label))
    drift = {"up": -0.03, "down": 0.03, "flat": 0.0}[change]
    out, v = [], float(price) * (1 + drift)
    for i in range(points - 1):
        v += (price - v) / (points - 1 - i) + price * rng.uniform(-0.006, 0.006)
        out.append(round(v))
    out.append(price)
    return out


def _price_row(label: str, price: int, change: str, pct: float, sub: str | None = None, unit: str = "원") -> dict:
    return {
        "label": label,
        "sub": sub,
        "value": f"{price:,}{unit}",
        "change": change,
        "pct": pct,
        "series": _mini_series(label, price, change),
    }


@app.get("/market")
def market():
    trend = _mock_daily_series("배추", 2650)
    return {
        "source": "KAMIS 농산물유통정보",
        "price_trend": {
            "item": "배추",
            "unit": "원/포기",
            "series": trend,
            "change_pct": round((trend[-1]["price"] - trend[0]["price"]) / trend[0]["price"] * 100, 1),
        },
        "items": [
            _price_row("배추", 2400, "down", 4.0, "1포기"),
            _price_row("무", 1800, "down", 2.0, "1개"),
            _price_row("대파", 3200, "flat", 0.0, "1kg"),
            _price_row("양파", 2100, "up", 3.0, "1kg"),
        ],
        # 2026-09-30: "제철이 언제부터 언제까지인지 월별 간트차트로"
        # 요청 — 자유 텍스트(meta) 대신 시작·끝 월(1~12)로 바꿔서
        # 프론트(SeasonalGantt)가 직접 막대를 그리게 함.
        "in_season": [
            {"name": "배추", "start_month": 10, "end_month": 12, "tip": "속이 꽉 차고 묵직한 것"},
            {"name": "무", "start_month": 10, "end_month": 12, "tip": "들었을 때 무겁고 매끈한 것"},
            {"name": "단감", "start_month": 10, "end_month": 11, "tip": "꼭지가 마르지 않은 것"},
            {"name": "고구마", "start_month": 9, "end_month": 11, "tip": "통통하고 껍질이 매끈한 것"},
        ],
        "livestock": [
            _price_row("계란", 6900, "flat", 0.0, "특란 30구"),
            _price_row("삼겹살", 2450, "up", 2.0, "100g"),
        ],
        "essentials": [
            {"label": "세제류", "sub": "물가지수", "value": "+1.8%", "change": "up", "pct": 1.8},
            {"label": "생활용품", "sub": "물가지수", "value": "+0.6%", "change": "up", "pct": 0.6},
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
            "label": "어제 박스오피스 1위",
            "title": "영화 A",
            "poster": None,
            "rank": 1,
            "stat_label": "누적 관객",
            "stat": "182만 명",
            "source": "KOBIS 영화관입장권통합전산망",
        },
        "box_office": [
            {"rank": 1, "title": "영화 A", "meta": "182만 명"},
            {"rank": 2, "title": "영화 B", "meta": "94만 명"},
            {"rank": 3, "title": "영화 C", "meta": "61만 명"},
        ],
        "performances": [{"title": "공연 A", "meta": "이번 주 개막"}],
        "festivals": [{"title": "축제 A", "meta": "이번 주말 · OO시"}],
        # 2026-09-29: "음악 순위도 넣을 수 있나" 질문 — 멜론/지니/벅스/
        # 가온(써클차트) 전부 공식 오픈 API가 없어서(스크래핑밖에 방법이
        # 없는데 이용약관 위반 소지가 있어 지금까지의 "공식 API만" 원칙에
        # 안 맞음) 제외하고, 공식 API가 있는 두 곳만 근사치로 넣기로 함.
        # 주의: Spotify는 국내 점유율이 멜론보다 훨씬 낮아서 "한국 실제
        # 인기 순위"랑은 차이가 날 수 있음 — "국내 차트"가 아니라
        # "Spotify 기준"이라고 라벨을 명확히 해야 함(UI에서 이미 그렇게
        # 표시 중, spotify_top의 title 필드가 "Spotify 기준" 포함).
        #
        # TODO: Spotify Web API — Client Credentials 플로우로 토큰 받고
        #   "Top 50 - South Korea" 공개 플레이리스트(37i9dQZEVXbNxXF4SkHj9F)
        #   조회 (https://developer.spotify.com/documentation/web-api)
        # TODO: YouTube Data API v3 — videos.list(chart=mostPopular,
        #   regionCode=KR, videoCategoryId=10) 로 인기 급상승 음악
        #   (https://developers.google.com/youtube/v3/docs/videos/list)
        "spotify_top": [
            {"rank": 1, "title": "곡 제목 A", "meta": "아티스트 A"},
            {"rank": 2, "title": "곡 제목 B", "meta": "아티스트 B"},
            {"rank": 3, "title": "곡 제목 C", "meta": "아티스트 C"},
        ],
        "youtube_trending": [
            {"rank": 1, "title": "뮤직비디오 제목 A", "meta": "채널 A"},
            {"rank": 2, "title": "뮤직비디오 제목 B", "meta": "채널 B"},
        ],
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
            "source": "한국은행 ECOS",
        },
        # 2026-10-10: 환율 카드 뒷면(뒤집으면 보임)용 — 주요 통화 환율.
        "fx_others": [
            {"title": "엔화 (100엔)", "meta": "910.4원"},
            {"title": "유로", "meta": "1,462.8원"},
            {"title": "위안", "meta": "188.1원"},
        ],
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
    """투데이(홈) — 섹션별 대표 카드 1개씩만 모아서 반환.
    2026-09-30: 날씨가 독립 섹션으로 빠지면서 투데이 카드 목록에도
    다른 섹션들과 동등하게 날씨 카드를 추가함(맨 앞)."""
    w, m, c, mo, a = weather(), market(), culture(), money(), ai()
    season_top = m["in_season"][0]
    weather_card = {
        "theme": "weather",
        "title": "오늘 날씨",
        "highlight": f"{w['today']['temp']}° {w['today']['condition']}",
        "meta": f"체감 {w['today']['feels_like']}°",
    }
    market_card = {
        "theme": "market",
        "title": "지금 제철",
        "highlight": season_top["name"],
        "meta": f"{season_top['start_month']}~{season_top['end_month']}월 제철",
    }
    # 2026-10-05: culture()["hero"]엔 title/poster/rank/stat_label/stat만
    # 있고 투데이 HeroCard가 쓰는 highlight/meta가 없어서, 투데이의 문화
    # 카드가 지금까지 제목만 뜨고 "182만 명" 같은 수치는 안 보였음(PosterCard
    # 작업하면서 발견) — highlight/meta로 매핑해서 채움.
    culture_card = {
        "theme": "culture",
        "title": c["hero"]["title"],
        "highlight": f"{c['hero']['rank']}위",
        "meta": f"{c['hero']['stat_label']} {c['hero']['stat']}",
    }
    return {
        "headline": "오늘 한 줄 요약(스텁)",
        "cards": [
            {"section": "weather", **weather_card},
            {"section": "market", **market_card},
            {"section": "culture", **culture_card},
            {"section": "money", **mo["hero"]},
            {"section": "ai", **a["weekly_article"]},
        ],
    }
