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

import functools
import re

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

import config  # noqa: F401  (.env를 읽어 환경변수에 채움)
import geo
import jobs
import sources  # noqa: F401  (수집 작업 등록)
import store
from sources import culture as culture_src
from sources import benefits as benefits_src
from sources import gov_support as gov_support_src
from sources import markets as markets_src
from sources import outing as outing_src
from sources import places as places_src
from sources import _kst
from sources import weather as weather_src

app = FastAPI(title="데일리컷 API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def _startup() -> None:
    # 2026-10-10: 실데이터 연동 시작 — 수집 결과는 SQLite에 캐시/이력으로 저장하고
    # API는 저장된 값만 읽음. 키가 없는 소스는 건너뛰고 아래 스텁이 그대로 나감.
    store.init()
    jobs.start()


def live_merge(name: str, regional=None):
    """엔드포인트의 스텁 응답 위에 수집된 실데이터 필드를 덮어씀(전국 공통 소스).
    regional을 주면 시도(sido 쿼리)별 소스(예: 전통시장)도 같이 덮어씀.
    응답의 live_keys에 덮어쓴 필드 이름을 넣어서, 화면이 스텁(예시) 구간을
    "예시 데이터"로 표시할 수 있게 함."""

    def deco(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            stub = fn(*args, **kwargs)
            live: dict = {}
            for n in (name,) if isinstance(name, str) else name:
                live.update(jobs.get_live(n) or {})
            if regional is not None:
                live.update(regional.get(geo.region(kwargs.get("sido"))["code"], kwargs.get("sgg")) or {})
            if not live:
                return {**stub, "live_keys": []}
            return {**stub, **live, "live_keys": sorted(live.keys())}

        return wrapper

    return deco


def live_geo(source):
    """시도(sido 쿼리, 2자리 코드)별 실데이터를 스텁 위에 덮어씀. 코드가 없거나 모르면 서울(11).
    앱 전체가 시도 단위로 통일돼 있어서 위치별 소스는 시도 17곳만 캐시하면 됨."""

    def deco(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            stub = fn(*args, **kwargs)
            live = source.get(geo.region(kwargs.get("sido"))["code"], kwargs.get("sgg"))
            before = set(stub.get("live_keys", []))  # 안쪽 데코레이터(예: live_merge)가 이미 덮어쓴 필드
            if not live:
                return {**stub, "live_keys": sorted(before)}
            return {**stub, **live, "live_keys": sorted(before | set(live.keys()))}

        return wrapper

    return deco


@app.get("/market/detail")
def market_detail(name: str, sigungu: str | None = None):
    """전통시장 상세(사진 등, 있을 때만). 사진 주소는 /proxy/image 로 감싸서 줌(원본 서버가 브라우저 접근을 막아서)."""
    d = markets_src.detail(name, sigungu)
    if d.get("found"):
        from urllib.parse import quote

        d = {**d, "image": "/proxy/image?u=" + quote(d["image"], safe=""), "credit": "한국관광공사 TourAPI", "license": "출처표시"}
    return d


@app.get("/culture/detail")
def culture_detail(id: str):
    """행사 상세(기간·장소·요금·설명). id는 events 항목의 id. 사진 주소는 /proxy/image 로 감싸서 줌."""
    d = culture_src.detail(id)
    if d.get("image"):
        from urllib.parse import quote

        d = {**d, "image": "/proxy/image?u=" + quote(d["image"], safe="")}
    return d


@app.get("/support")
def support(sido: str | None = None, sgg: str | None = None, scope: str = "all", field: str | None = None, limit: int = 30):
    """정부 지원·혜택(행정안전부 공공서비스 정보). 지역(시도·시군구)만으로 거르고 개인 조건은 받지 않음.
    수집이 안 됐으면(키 미승인) live=False, items=[] — 화면은 섹션을 숨김(예시 데이터 없음)."""
    return gov_support_src.query(sido, sgg, scope if scope in ("all", "local", "central") else "all", field, min(max(limit, 1), 60))


@app.get("/outing")
def outing(sido: str | None = None, sgg: str | None = None):
    """문화 탭 "이번 주말 한산한 곳"(한국관광공사 관광지 집중률 예측 + 그날 날씨). 처음 부르는 지역은 몇 초 걸림(그 뒤 24시간 캐시)."""
    return outing_src.weekend(sido, sgg, weather(sido=sido, sgg=sgg).get("weekly", []))


@app.get("/places")
def places(kind: str = "library", sido: str | None = None, sgg: str | None = None):
    """문화 탭 "나들이": kind = library(도서관 빈자리) | camp(캠핑장) | pet(반려동물 동반) | wellness(웰니스) | trail(걷기길).
    캠핑은 이번 주말 날씨(토·일)를 같이 줌."""
    out = places_src.query(kind, sido, sgg)
    if kind == "camp" and out.get("live"):
        weekly = weather(sido=sido, sgg=sgg).get("weekly", [])
        days = []
        for d in outing_src.weekend_days(_kst.today()):
            w = next((x for x in weekly if x.get("date") == f"{d.month}/{d.day}"), None)
            if w:
                days.append({"label": "월화수목금토일"[d.weekday()], "md": f"{d.month}/{d.day}", "condition": w["condition"], "high": w["high"], "low": w["low"], "pop": w.get("pop")})
        out = {**out, "weather": days}
    return out


@app.get("/benefits/housing")
def benefits_housing(kind: str = "apply", sido: str | None = None, sgg: str | None = None):
    """청약(kind=apply, 한국부동산원 청약홈)·공공임대(kind=rent, 마이홈포털+LH) 공고. 접수가 안 끝난 것만, 선택한 시도 기준."""
    return benefits_src.housing("rent" if kind == "rent" else "apply", sido, sgg)


@app.get("/benefits/loans")
def benefits_loans(usage: str | None = None, sido: str | None = None):
    """서민금융진흥원 대출상품 한눈에(전국 공통 + 선택한 시도 상품). usage는 생계·주거·학자금·사업."""
    return benefits_src.loans(usage, sido)


class SupportProfile(BaseModel):
    """정부 지원 "내 조건" — 선택 항목만. 저장·로그 안 함(본문으로만 받음)."""
    sido: str | None = None
    sgg: str | None = None
    scope: str = "all"
    age: int | None = None
    gender: str | None = None  # m | f
    income: int | None = None  # 1~5 기준중위소득 구간
    traits: list[str] = []


@app.post("/support/search")
def support_search(body: SupportProfile):
    """조건(나이·성별·소득구간·해당 특성)으로 좁힌 정부 지원. 조건은 이 요청에서만 쓰고 어디에도 남기지 않음."""
    scope = body.scope if body.scope in ("all", "local", "central") else "all"
    return gov_support_src.query(
        body.sido, body.sgg, scope, None, 40, {"age": body.age, "gender": body.gender, "income": body.income, "traits": body.traits[:20]}
    )


@app.get("/proxy/image")
def proxy_image(u: str):
    """허용된 호스트(한국관광공사 사진 서버)의 이미지만 대신 받아 전달함. 아무 주소나 열지 못하게 호스트를 제한하고 크기도 제한."""
    from urllib.parse import urlparse

    import requests
    from fastapi import HTTPException
    from fastapi.responses import Response

    pu = urlparse(u)
    if pu.scheme not in ("http", "https") or pu.hostname not in (*markets_src.PHOTO_HOSTS, *culture_src.IMAGE_HOSTS):
        raise HTTPException(status_code=400, detail="허용되지 않은 주소")
    try:
        r = requests.get(u, timeout=15, stream=True)
        data = r.raw.read(3_000_001)
    except requests.RequestException:
        raise HTTPException(status_code=502, detail="사진을 가져오지 못했어요")
    if r.status_code != 200 or len(data) > 3_000_000 or not r.headers.get("content-type", "").startswith("image"):
        raise HTTPException(status_code=502, detail="사진을 가져오지 못했어요")
    return Response(content=data, media_type=r.headers["content-type"], headers={"Cache-Control": "public, max-age=604800"})


@app.get("/regions")
def regions():
    """앱의 지역 선택 목록: 시도 17곳과 각 시도의 시군구(별칭 포함, 예: 성남시 ← 분당구)."""
    return {"default": geo.DEFAULT_SIDO, "regions": geo.regions_tree()}


class Coord(BaseModel):
    lat: float
    lon: float


@app.post("/region")
def region_of(c: Coord):
    """좌표 → 시도·시군구. 앱이 위치 권한을 받았을 때 지역을 정하려고 딱 한 번 부름(이후엔 지역 이름만 씀).
    가장 가까운 측정소의 주소로 찾고, 못 찾으면 가장 가까운 시도청 소재지(시도만).
    2026-10-11: GET ?lat=&lon=은 nginx 접속 로그에 좌표가 그대로 남아서 POST 본문으로 바꿈(본문은 로그에 안 남음)."""
    la, lo = round(c.lat, 2), round(c.lon, 2)  # 좌표는 저장하지 않음, 정규화만 함
    code, sgg = None, None
    try:
        from sources import _http

        x, y = geo.to_tm(la, lo)
        body = _http.get_json(
            config.get_key("AIRKOREA_STATION_BASE_URL") + "/getNearbyMsrstnList",
            {"returnType": "json", "tmX": x, "tmY": y, "ver": "1.1"},
        )
        items = _http.items_of(body)
        if items:
            addr = items[0].get("addr") or ""
            code = geo.sido_of_address(addr)
            toks = addr.split()
            sg = geo.find_sigungu(code, toks[1]) if code and len(toks) > 1 else None
            sgg = sg["name"] if sg else None
    except Exception:
        pass
    code = code or geo.nearest_sido(la, lo)
    pl = geo.place(code, sgg)
    return {"code": pl["code"], "sgg": pl["sgg"], "label": pl["label"]}


class UsageEvent(BaseModel):
    n: str  # 이벤트 이름(예: tab_view)
    p: str = ""  # 값(예: money) — 항목 이름·시도 코드 같은 "무엇을"만. 개인 정보 금지


class UsageBatch(BaseModel):
    events: list[UsageEvent]


_USAGE_OK = re.compile(r"^[0-9A-Za-z_가-힣·\-\. ]{1,30}$")
_USAGE_NAMES = {
    "tab_view", "region_pick", "culture_kind", "culture_open", "market_open", "produce_open", "basket_add",
    "basket_remove", "support_profile", "support_trait", "benefit_seg", "money_metric", "money_range", "life_open", "sources_open", "life_edit", "location_ask",
}


@app.post("/events")
def usage_events(b: UsageBatch):
    """익명 이용 통계(어느 탭·칩·품목이 얼마나 쓰이는지). 사용자·기기 ID, 좌표, 검색어는 받지 않음 —
    허용된 이벤트 이름과 짧은 값만 받아 (날짜, 이벤트, 값)별 횟수만 올림. 한 번에 50개까지."""
    rows = []
    for e in b.events[:50]:
        if e.n in _USAGE_NAMES and (e.p == "" or _USAGE_OK.match(e.p)):
            rows.append((e.n, e.p))
    if rows:
        store.record_usage(rows)
    return {"ok": True, "n": len(rows)}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/status")
def status():
    """수집 작업별 상태(live/waiting/stub). 키 값은 절대 안 내보냄."""
    return {"jobs": jobs.describe()}


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


@live_geo(weather_src)
def weather(sido: str | None = None, sgg: str | None = None):
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


@app.get("/weather")
def weather_route(sido: str | None = None, sgg: str | None = None):
    """투데이 첫 화면은 이것만으로 그려짐(2026-10-15): 맨 위 한 문장(headline)을 함께 줌 — /today가 느려도 날씨 히어로가 안 막히게."""
    w = weather(sido=sido, sgg=sgg)
    return {**w, "headline": _headline(w)}


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
@live_merge(("market", "livestock"), regional=markets_src)
def market(sido: str | None = None, sgg: str | None = None):
    # 2026-10-10: 추이 차트 X축을 "이번 달 1일~말일" 고정축으로 바꿈 — 시리즈는
    # 이번 달 1일부터 오늘까지의 일별 값만 보내고(미래 날짜는 비워둠), 지난주
    # 대비 계산용으로 7일 전 값(week_ago)을 따로 줌(월초엔 지난달 값이 필요해서).
    # 실데이터 연결 후엔 price_history에서 같은 모양으로 만들면 됨.
    today_d = date.today()
    full = _mock_daily_series("배추", 2650, days=today_d.day + 7)
    trend = full[-today_d.day:]
    week_ago = full[-8]["price"]
    return {
        "source": "KAMIS 농산물유통정보",
        "price_trend": {
            "item": "배추",
            "unit": "원/포기",
            "series": trend,
            "week_ago": week_ago,
            "change_pct": round((trend[-1]["price"] - week_ago) / week_ago * 100, 1),
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
@live_geo(culture_src)
def culture(sido: str | None = None, sgg: str | None = None):
    return {
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


def _headline(w: dict) -> str:
    """투데이 맨 위 한 문장 — 실제 날씨가 붙은 경우에만 규칙으로 만듦(아직 AI 요약 없음)."""
    if "today" not in (w.get("live_keys") or []):
        return "오늘 한 줄 요약(스텁)"
    t = w["today"]
    wet = any(h.get("pop", 0) >= 60 for h in w.get("hourly", [])[:4])
    air_bad = w.get("air_quality", {}).get("pm25") in ("나쁨", "매우나쁨")
    tail = " · 우산을 챙기세요" if wet else (" · 마스크를 챙기세요" if air_bad else "")
    return f"오늘은 {t['condition']}, 낮 최고 {t['high']}°예요{tail}"


@app.get("/today")
def today(sido: str | None = None, sgg: str | None = None):
    """투데이(홈) — 섹션별 대표 카드 1개씩만 모아서 반환.
    2026-09-30: 날씨가 독립 섹션으로 빠지면서 투데이 카드 목록에도
    다른 섹션들과 동등하게 날씨 카드를 추가함(맨 앞)."""
    w, m, a = weather(sido=sido, sgg=sgg), market(sido=sido, sgg=sgg), ai()
    # 이번 달 제철: 실데이터 job이 돌면 편집 가이드(data/produce_guide.json) 기준 이름들, 아니면 스텁 첫 항목
    season_names = m.get("season_now") or [m["in_season"][0]["name"]]
    weather_card = {
        "theme": "weather",
        "title": "오늘 날씨",
        "highlight": f"{w['today']['temp']}° {w['today']['condition']}",
        "meta": f"체감 {w['today']['feels_like']}°",
    }
    market_card = {
        "theme": "market",
        "title": "지금 제철",
        "highlight": " · ".join(season_names[:3]),
        "meta": f"이번 달 제철 {len(season_names)}가지" if m.get("season_now") else f"{m['in_season'][0]['start_month']}~{m['in_season'][0]['end_month']}월 제철",
    }
    # 2026-10-13: 문화 카드는 예전엔 박스오피스(KOBIS 스텁)였는데, 광고 약관 때문에 빼고 "이번 주말 행사 N개"(관광공사·문화정보원)로 바꿈.
    # 혜택 카드(옛 머니 자리)는 행안부 공공서비스 건수. 둘 다 실데이터를 못 받았으면 카드를 아예 안 냄(예시 카드를 만들지 않음).
    region = geo.region(sido)
    place_name = region["name"] + (f" {sgg}" if sgg else "")
    live = culture_src.peek(region["code"], sgg)  # 캐시에 있을 때만(없으면 행사 수집으로 20초+ 걸려서 투데이가 느려짐)
    culture_card = None
    if live and live.get("events"):
        sat, sun = _weekend_range(_kst.today())
        n = sum(1 for e in live["events"] if e["start"] <= sun.isoformat() and e["end"] >= sat.isoformat())
        culture_card = {
            "theme": "culture",
            "title": "이번 주말 행사" if _kst.today().weekday() != 6 else "오늘 행사",
            "highlight": f"{n}개",
            "meta": f"{place_name} · {sat.month}/{sat.day}~{sun.day}" if sat != sun else place_name,
        }
    benefits = gov_support_src.query(sido, sgg, "all", None, 1)
    benefit_card = (
        {"theme": "money", "title": "정부 혜택", "highlight": f"{benefits['total']:,}개", "meta": f"{place_name} 기준"} if benefits.get("live") else None
    )
    cards = [
        {"section": "weather", **weather_card},
        {"section": "market", **market_card},
        *([{"section": "culture", **culture_card}] if culture_card else []),
        *([{"section": "money", **benefit_card}] if benefit_card else []),
        {"section": "ai", **a["weekly_article"]},
    ]
    return {
        "headline": _headline(w),
        # 어떤 섹션 카드가 실데이터인지(앱이 스텁 카드를 구분해서 표시)
        "live_sections": [
            name
            for name, is_live in (
                ("weather", "today" in w.get("live_keys", [])),
                ("culture", culture_card is not None),
                ("money", benefit_card is not None),
                ("market", "season_now" in m.get("live_keys", [])),
            )
            if is_live
        ],
        "cards": cards,
    }


def _weekend_range(today: date) -> tuple[date, date]:
    """이번 주말: 일요일이면 오늘 하루, 아니면 이번 주 토~일."""
    if today.weekday() == 6:
        return today, today
    sat = today + timedelta(days=(5 - today.weekday()) % 7)
    return sat, sat + timedelta(days=1)
