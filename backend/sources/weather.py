# -*- coding: utf-8 -*-
"""날씨 수집: 기상청 단기·중기예보 + 에어코리아 + 생활기상지수 + 출몰시각 + 특일정보.

사용자 위치(위경도)로 전국 어디서든 동작함 — 격자(nx, ny)·근접 측정소·중기 예보 구역·
시도 지점코드를 geo.py로 계산하고, 같은 격자 칸은 25분 동안 캐시(_cache.cached).
/weather 응답에 덮어쓸 필드: today, hourly, weekly, weekend, outfit, good_for,
air_quality, life, next_holiday, location, source.
"""

from __future__ import annotations

import math

import requests
from datetime import date, datetime, timedelta

import config
import geo
import jobs
from sources import _cache, _http

WEEKDAYS = ["월", "화", "수", "목", "금", "토", "일"]
SKY = {"1": "맑음", "3": "구름 많음", "4": "흐림"}
PTY = {"1": "비", "2": "비/눈", "3": "눈", "4": "소나기", "5": "빗방울", "6": "빗방울눈날림", "7": "눈날림"}
GRADE = {"1": "좋음", "2": "보통", "3": "나쁨", "4": "매우나쁨"}


def _cfg(name: str) -> str:
    v = config.get_key(name)
    if not v:
        raise RuntimeError(f"{name} 없음")
    return v


def available() -> bool:
    return config.has_keys([_http.KEY_ENV, "KMA_SHORT_FCST_BASE_URL", "KMA_MID_FCST_BASE_URL"])


# ---------------- 기상청 ----------------

def _short(base_date: str, base_time: str, nx: int, ny: int) -> dict[tuple[str, str], dict[str, str]]:
    body = _http.get_json(
        _cfg("KMA_SHORT_FCST_BASE_URL") + "/getVilageFcst",
        {"pageNo": 1, "numOfRows": 1000, "dataType": "JSON", "base_date": base_date, "base_time": base_time, "nx": nx, "ny": ny},
    )
    out: dict[tuple[str, str], dict[str, str]] = {}
    for it in _http.items_of(body):
        out.setdefault((it["fcstDate"], it["fcstTime"]), {})[it["category"]] = it["fcstValue"]
    return out


def _latest_base(now: datetime) -> tuple[str, str]:
    """발표(02·05·08·11·14·17·20·23시) 후 20분이 지난 가장 최근 발표 시각."""
    avail = now - timedelta(minutes=20)
    hours = [h for h in (2, 5, 8, 11, 14, 17, 20, 23) if avail.hour >= h]
    if hours:
        return avail.strftime("%Y%m%d"), f"{hours[-1]:02d}00"
    return (avail - timedelta(days=1)).strftime("%Y%m%d"), "2300"


def _ncst(now: datetime, nx: int, ny: int) -> dict[str, str]:
    """초단기실황(지금 관측): 정시 자료는 40분 뒤부터 나와서 45분 전 정시를 씀."""
    t = now - timedelta(minutes=45)
    body = _http.get_json(
        _cfg("KMA_SHORT_FCST_BASE_URL") + "/getUltraSrtNcst",
        {"pageNo": 1, "numOfRows": 20, "dataType": "JSON", "base_date": t.strftime("%Y%m%d"), "base_time": t.strftime("%H00"), "nx": nx, "ny": ny},
    )
    return {it["category"]: it["obsrValue"] for it in _http.items_of(body)}


def _cond(vals: dict[str, str]) -> str:
    return PTY.get(vals.get("PTY", "0")) or SKY.get(vals.get("SKY", "1"), "맑음")


def _feels_like(temp: float, wind_ms: float) -> int:
    kmh = wind_ms * 3.6
    if temp <= 10 and kmh >= 4.8:
        v = kmh**0.16
        return round(13.12 + 0.6215 * temp - 11.37 * v + 0.3965 * v * temp)
    return round(temp)


def _daily(pivot: dict, days: list[date]) -> dict[date, dict]:
    out = {}
    for d in days:
        key = d.strftime("%Y%m%d")
        rows = {t: v for (dd, t), v in pivot.items() if dd == key}
        if not rows:
            continue
        temps = [float(v["TMP"]) for v in rows.values() if "TMP" in v]
        tmn = next((float(v["TMN"]) for v in rows.values() if "TMN" in v), min(temps) if temps else None)
        tmx = next((float(v["TMX"]) for v in rows.values() if "TMX" in v), max(temps) if temps else None)
        pop = max((int(v["POP"]) for v in rows.values() if "POP" in v), default=0)
        day_rows = [v for t, v in sorted(rows.items()) if "0900" <= t <= "1800"] or list(rows.values())
        wet = next((v for v in day_rows if v.get("PTY", "0") != "0"), None)
        cond = _cond(wet or day_rows[len(day_rows) // 2])
        out[d] = {"low": round(tmn) if tmn is not None else None, "high": round(tmx) if tmx is not None else None, "pop": pop, "condition": cond}
    return out


def _mid(now: datetime, wanted: list[date], land_reg: str, temp_reg: str) -> dict[date, dict]:
    """중기예보. 발표는 06시·18시(발표 직후엔 아직 없어서 30분 여유).
    18시 발표분은 5일 뒤부터 시작해서(06시 발표분은 4일 뒤부터) 저녁에는 하루가 비므로,
    최신 발표분으로 먼저 채우고 비는 날은 직전 발표분(12시간 전)으로 채움."""
    base = now - timedelta(minutes=30)
    if base.hour >= 18:
        tm = base.replace(hour=18, minute=0, second=0, microsecond=0)
    elif base.hour >= 6:
        tm = base.replace(hour=6, minute=0, second=0, microsecond=0)
    else:
        tm = (base - timedelta(days=1)).replace(hour=18, minute=0, second=0, microsecond=0)
    root = _cfg("KMA_MID_FCST_BASE_URL")
    out: dict[date, dict] = {}
    for t in (tm, tm - timedelta(hours=12)):
        if all(d in out for d in wanted):
            break
        common = {"pageNo": 1, "numOfRows": 10, "dataType": "JSON", "tmFc": t.strftime("%Y%m%d%H%M")}
        try:
            ta = (_http.items_of(_http.get_json(root + "/getMidTa", {**common, "regId": temp_reg})) or [{}])[0]
            land = (_http.items_of(_http.get_json(root + "/getMidLandFcst", {**common, "regId": land_reg})) or [{}])[0]
        except Exception:
            continue
        for n in range(3, 11):
            d = t.date() + timedelta(days=n)
            if d not in wanted or d in out:
                continue
            low, high = ta.get(f"taMin{n}"), ta.get(f"taMax{n}")
            cond = land.get(f"wf{n}Pm") or land.get(f"wf{n}")
            pop = land.get(f"rnSt{n}Pm") if f"rnSt{n}Pm" in land else land.get(f"rnSt{n}")
            if low is None or high is None or not cond:
                continue
            out[d] = {"low": round(low), "high": round(high), "pop": int(pop or 0), "condition": cond}
    return out


def _outfit(temp: int, rainy: bool, swing: int = 0) -> str:
    """temp: 낮 시간대(9~18시) 평균 기온. swing: 하루 최고-최저 차이(일교차)."""
    if temp >= 28:
        s = "민소매나 얇은 반팔에 시원한 하의가 좋아요"
    elif temp >= 23:
        s = "반팔에 얇은 셔츠 정도면 충분해요"
    elif temp >= 20:
        s = "얇은 긴팔이나 가벼운 가디건이면 딱이에요"
    elif temp >= 17:
        s = "가벼운 니트에 자켓 하나 걸치면 딱 좋아요"
    elif temp >= 12:
        s = "자켓이나 트렌치코트를 챙기세요"
    elif temp >= 9:
        s = "니트에 도톰한 코트가 필요해요"
    elif temp >= 5:
        s = "두꺼운 코트에 목도리를 더하세요"
    else:
        s = "패딩과 목도리, 장갑까지 챙기세요"
    if swing >= 10:
        s += " · 일교차가 커서 아침저녁엔 겉옷도 챙기세요"
    return s + (" · 우산도 챙기세요" if rainy else "")


# ---------------- 에어코리아 ----------------

def _grade(value: float, cuts: tuple[float, float, float]) -> str:
    return "좋음" if value <= cuts[0] else "보통" if value <= cuts[1] else "나쁨" if value <= cuts[2] else "매우나쁨"


def _air_rows(sido_air: str) -> list[dict]:
    """시도 전체 측정소의 실시간 값(한 번 받아 시도별로 캐시 → 시군구마다 다시 부르지 않음)."""

    def load() -> dict:
        body = _http.get_json(
            _cfg("AIRKOREA_AIR_QUALITY_BASE_URL") + "/getCtprvnRltmMesureDnsty",
            {"returnType": "json", "numOfRows": 300, "pageNo": 1, "sidoName": sido_air, "ver": "1.3"},
        )
        return {"rows": _http.items_of(body)}

    return _cache.cached("air", f"air13:{sido_air}", 25, load)["rows"]


_GRADE_NAME = {"1": "좋음", "2": "보통", "3": "나쁨", "4": "매우나쁨"}


def _num(v) -> float | None:
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _air_station(place: dict, rows: list[dict]) -> dict | None:
    """보여줄 측정소 한 곳: 고른 시군구의 측정소(목록 순서대로 값이 있는 첫 곳), 시도만 골랐으면 시도청에 가장 가까운 시군구의 측정소부터."""
    by_name = {r.get("stationName"): r for r in rows}

    def usable(r) -> bool:
        return bool(r) and (_num(r.get("pm10Value")) is not None or _num(r.get("pm25Value")) is not None)

    names = list(place.get("stations") or [])
    if not names:
        near = sorted(geo.sigungu_list(place["code"]), key=lambda g: geo.haversine_km((place["lat"], place["lon"]), (g["lat"], g["lon"])))
        for g in near:
            names += g.get("stations", [])
    for n in names:
        if usable(by_name.get(n)):
            return by_name[n]
    return next((r for r in rows if usable(r)), None)


def _air(place: dict) -> dict:
    """에어코리아(공공누리 3유형: 출처표시·**변경금지**) 값을 가공하지 않고 보여줌(2026-10-16 광고 대비).
    예전엔 시군구 측정소 평균을 내고 등급을 직접 다시 매겼는데, 변경금지에 걸릴 소지가 있어 → 측정소 한 곳의 실시간 원값과
    에어코리아가 준 1시간 등급(pm10Grade1h·pm25Grade1h)을 그대로 씀."""
    r = _air_station(place, _air_rows(place["air"]))
    if not r:
        return {"pm10": "정보 없음", "pm25": "정보 없음"}

    def grade(key: str) -> str:
        return _GRADE_NAME.get(str(r.get(key + "Grade1h") or r.get(key + "Grade") or ""), "정보 없음")

    pm10, pm25 = _num(r.get("pm10Value")), _num(r.get("pm25Value"))
    return {
        "pm10": grade("pm10"),
        "pm25": grade("pm25"),
        "pm10_value": int(pm10) if pm10 is not None else None,
        "pm25_value": int(pm25) if pm25 is not None else None,
        "station": r.get("stationName"),
        "data_time": r.get("dataTime"),
        "scope": place["label"],
    }


# ---------------- 생활 지수 ----------------

WARNING_REGIONS = ("11", "28", "41")  # 서울·인천·경기(기상청 수도권 지점 108)만 지원


def _quakes() -> list[dict]:
    """최근 3일 기상청 지진 통보 중 국내에 영향이 있는 것(해외 지진은 "국내영향없음"이라 뺌). 기상청 지진정보 getEqkMsg는 3일 전까지만 조회됨."""
    from sources import _kst

    base = config.get_key("KMA_EARTHQUAKE_BASE_URL")
    if not base:
        return []
    today = _kst.today()
    r = requests.get(
        base + "/getEqkMsg",
        params={"serviceKey": config.get_key(_http.KEY_ENV), "numOfRows": 100, "pageNo": 1, "dataType": "JSON",
                "fromTmFc": (today - timedelta(days=2)).strftime("%Y%m%d"), "toTmFc": today.strftime("%Y%m%d")},
        timeout=20,
    )
    r.raise_for_status()
    it = (((r.json().get("response") or {}).get("body") or {}).get("items") or {}).get("item") or []
    it = it if isinstance(it, list) else [it]
    return [
        {"loc": (x.get("loc") or "").strip(), "mt": x.get("mt"), "t": str(x.get("tmEqk") or "")}
        for x in it
        if "국내영향없음" not in (x.get("rem") or "")
    ]


def _warning(now: datetime, region: dict) -> dict:
    """발효 중인 기상특보. 지점이 서울(108, 수도권) 하나뿐이라 서울·인천·경기에서만 제공함 — 다른 시도는
    지점 코드 표를 확인해야 해서 "제공 안 함"으로 보여줌.
    특보 현황(getPwnStatus)의 전국 현재 특보 글에서 "해제"가 아닌 주의보·경보 줄 중 우리 지역 이름이 든 것만 고름.
    특보가 실제로 발효된 날의 글 모양은 못 봐서(오늘은 "없음"), 줄 단위로 방어적으로 읽음.
    반환: {"supported", "items": [{"title", "text"}], "recent": 최근 통보 제목}."""
    if region["code"] not in WARNING_REGIONS:
        return {"supported": False, "items": [], "recent": None}
    base = _cfg("KMA_WARNING_BASE_URL")
    status = _http.items_of(_http.get_json(base + "/getPwnStatus", {"stnId": "108", "dataType": "JSON", "numOfRows": 5, "pageNo": 1}))
    text = ""
    if status:
        text = "\n".join(str(status[0][k]) for k in ("t1", "t2", "t3", "t4", "t5", "t6", "t7", "other") if status[0].get(k))
    keys = [k for k in (region["sido"], region.get("sgg")) if k]
    items = []
    for line in text.splitlines():
        line = line.strip().lstrip("o").strip()
        if line and ("주의보" in line or "경보" in line) and "해제" not in line and any(k in line for k in keys):
            items.append({"title": line[:160], "text": None})
    recent = None
    try:
        lst = _http.items_of(_http.get_json(base + "/getWthrWrnList", {"stnId": "108", "dataType": "JSON", "numOfRows": 1, "pageNo": 1}))
        if lst:
            recent = str(lst[0].get("title"))[:160]
    except Exception:
        pass
    return {"supported": True, "items": items, "recent": recent}


def _uv(now: datetime, region: dict) -> dict | None:
    """오늘 낮 시간대 자외선지수 최고값. 응답의 h0·h3·… 는 발표 시각(date)에서 N시간 뒤 값."""
    body = _http.get_json(
        _cfg("KMA_LIVING_IDX_BASE_URL") + "/getUVIdxV5",
        {"areaNo": region["code"] + "00000000", "time": now.strftime("%Y%m%d%H"), "dataType": "JSON", "numOfRows": 1, "pageNo": 1},
    )
    it = (_http.items_of(body) or [None])[0]
    if not it:
        return None
    base_hour = int(it["date"][-2:])
    vals = [int(it[f"h{h}"]) for h in range(0, 22, 3) if it.get(f"h{h}", "") != "" and 6 <= base_hour + h <= 18]
    if not vals:
        return None
    v = max(vals)
    label = "낮음" if v <= 2 else "보통" if v <= 5 else "높음" if v <= 7 else "매우 높음" if v <= 10 else "위험"
    return {"title": "자외선", "meta": f"{label} ({v})", "basis": f"기상청 자외선지수 · {region['sido']} 시도 단위 · 오늘 낮(6~18시) 최고 {v} · 0~2 낮음, 3~5 보통, 6~7 높음, 8~10 매우 높음, 11~ 위험"}


def _pollen(now: datetime, region: dict) -> dict | None:
    """꽃가루(잡초류) — 제공 기간(보통 9~10월)에만 값이 나오고 0(낮음)이면 보여줄 게 없어서 생략."""
    body = _http.get_json(
        _cfg("KMA_POLLEN_BASE_URL") + "/getWeedsPollenRiskndxV3",
        {"areaNo": region["code"] + "00000000", "time": now.strftime("%Y%m%d%H"), "dataType": "JSON", "numOfRows": 1, "pageNo": 1},
    )
    it = (_http.items_of(body) or [None])[0]
    if not it or not str(it.get("today", "")).isdigit() or int(it["today"]) < 1:
        return None
    level = {1: "보통", 2: "높음", 3: "매우 높음"}.get(int(it["today"]), "주의")
    return {"title": "꽃가루(잡초류)", "meta": level, "basis": f"기상청 꽃가루농도위험지수 · 잡초류 · {region['sido']} 시도 단위"}


def _sun(now: datetime, region: dict) -> dict | None:
    items = _http.get_xml_items(
        _cfg("KASI_RISE_SET_BASE_URL") + "/getLCRiseSetInfo",
        {"locdate": now.strftime("%Y%m%d"), "longitude": region["lon"], "latitude": region["lat"], "dnYn": "Y"},
    )
    if not items:
        return None
    a = items[0]
    f = lambda t: f"{t[:2]}:{t[2:4]}"
    return {"title": "일출 · 일몰", "meta": f"{f(a['sunrise'])} · {f(a['sunset'])}", "basis": f"한국천문연구원 · {region['label']} 기준"}


def _next_term(today: date) -> dict | None:
    """다음 24절기(이번 달에 없으면 다음 달)."""
    y, m = today.year, today.month
    for _ in range(2):
        items = _http.get_xml_items(_cfg("KASI_SPECIAL_DAY_BASE_URL") + "/get24DivisionsInfo", {"solYear": y, "solMonth": f"{m:02d}"})
        for it in sorted(items, key=lambda i: i["locdate"]):
            d = datetime.strptime(it["locdate"], "%Y%m%d").date()
            if d >= today:
                return {"title": "다음 절기", "meta": f"{it['dateName']} " + ("오늘" if d == today else f"D-{(d - today).days}"), "basis": "한국천문연구원 24절기"}
        m += 1
        if m > 12:
            y, m = y + 1, 1
    return None


def _next_holiday(today: date) -> dict | None:
    """오늘 이후 가장 가까운 공휴일(이번 달부터 최대 4달 뒤까지 찾음)."""
    y, m = today.year, today.month
    for _ in range(5):
        items = _http.get_xml_items(_cfg("KASI_SPECIAL_DAY_BASE_URL") + "/getRestDeInfo", {"solYear": y, "solMonth": f"{m:02d}", "numOfRows": 50})
        days = sorted((datetime.strptime(i["locdate"], "%Y%m%d").date(), i["dateName"]) for i in items if i.get("isHoliday") == "Y")
        for d, name in days:
            if d > today:
                return {"name": name, "date": d.isoformat(), "d_day": (d - today).days}
        m += 1
        if m > 12:
            y, m = y + 1, 1
    return None


# ---------------- 조립 ----------------

def fetch(code: str, sgg: str | None = None) -> dict:
    # 고른 시군구의 중심 좌표 기준(시군구 없이 시도만 고르면 시도청 소재지 기준)
    region = geo.place(code, sgg)
    now = datetime.now()
    today = now.date()
    nx, ny = geo.to_grid(region["lat"], region["lon"])
    land_reg, temp_reg = geo.mid_regions(region["lat"], region["lon"])

    ncst = _ncst(now, nx, ny)
    base_date, base_time = _latest_base(now)
    latest = _short(base_date, base_time, nx, ny)
    # 오늘 최저/최고는 02시 발표분에만 들어 있음(02시 20분 전이면 어제 23시 발표분)
    if now - timedelta(minutes=20) >= now.replace(hour=2, minute=0, second=0, microsecond=0):
        daily_src = _short(today.strftime("%Y%m%d"), "0200", nx, ny)
    else:
        daily_src = _short((today - timedelta(days=1)).strftime("%Y%m%d"), "2300", nx, ny)
    merged = {k: {**daily_src.get(k, {}), **latest.get(k, {})} for k in set(daily_src) | set(latest)}
    daily = _daily(merged, [today + timedelta(days=i) for i in range(4)])  # 단기예보는 글피(+3일)까지 줌

    temp = float(ncst.get("T1H", "nan"))
    if math.isnan(temp):
        raise RuntimeError("실황 기온 없음")
    here = latest.get((today.strftime("%Y%m%d"), now.strftime("%H00"))) or next(
        (v for (d, t), v in sorted(latest.items()) if (d, t) >= (today.strftime("%Y%m%d"), now.strftime("%H00"))), {}
    )
    td = daily.get(today, {})
    today_block = {
        "temp": round(temp),
        "feels_like": _feels_like(temp, float(ncst.get("WSD", 0) or 0)),
        "condition": PTY.get(ncst.get("PTY", "0")) or SKY.get(here.get("SKY", "1"), "맑음"),
        "high": td.get("high", round(temp)),
        "low": td.get("low", round(temp)),
    }

    # 시간대별: 오늘 0시 ~ 모레 0시(1시간 간격 49칸). 지난 시각은 예보값, "지금"은 실황 기온.
    # 오늘 0~2시는 어제 23시 발표분에만 있어서(02시 20분 이후에는 02시 발표분에 없음) 따로 받음.
    prev: dict = {}
    if now - timedelta(minutes=20) >= now.replace(hour=2, minute=0, second=0, microsecond=0):
        try:
            prev = _short((today - timedelta(days=1)).strftime("%Y%m%d"), "2300", nx, ny)
        except Exception:
            prev = {}
    allv: dict = {}
    for src in (prev, daily_src, latest):  # 뒤에 온 발표분이 앞의 값을 덮어씀
        for k, v in src.items():
            allv.setdefault(k, {}).update(v)
    hourly = []
    t0 = datetime.combine(today, datetime.min.time())
    this_hour = now.replace(minute=0, second=0, microsecond=0)
    for i in range(0, 49):
        t = t0 + timedelta(hours=i)
        v = allv.get((t.strftime("%Y%m%d"), t.strftime("%H00")))
        if not v or "TMP" not in v:
            continue
        is_now = t == this_hour
        hourly.append(
            {
                "date": t.date().isoformat(),
                "hour": t.hour,
                "time": f"{t.hour}시",
                "temp": round(temp) if is_now else round(float(v["TMP"])),
                "condition": _cond(v),
                "pop": int(v.get("POP", 0)),
                "is_now": is_now,
                "is_past": t < this_hour,
            }
        )

    wanted = [today + timedelta(days=i) for i in range(0, 7)]  # 오늘 포함 7일(시간대별과 같은 "오늘"부터)
    by_day = dict(daily)
    try:
        by_day.update(_mid(now, wanted, land_reg, temp_reg))
    except Exception:
        pass  # 중기예보가 안 와도 단기 구간은 보여줌
    weekly = []
    for d in wanted:
        row = by_day.get(d)
        weekly.append(
            {
                "day": "오늘" if d == today else WEEKDAYS[d.weekday()],
                "weekday": WEEKDAYS[d.weekday()],
                "date": f"{d.month}/{d.day}",
                "is_today": d == today,
                # 단기예보는 3일 뒤까지, 중기예보는 4일 뒤부터라 이어지지만, 어느 한쪽이 실패하면 값이 빌 수 있음
                "high": row["high"] if row else None,
                "low": row["low"] if row else None,
                "condition": row["condition"] if row else None,
                "pop": row["pop"] if row else None,
            }
        )

    wk = {w["weekday"]: w for w in weekly if w["high"] is not None and not w["is_today"]}
    weekend = ""
    if "토" in wk and "일" in wk:
        weekend = f"토요일은 {wk['토']['condition']} {wk['토']['low']}~{wk['토']['high']}°, 일요일은 {wk['일']['condition']} {wk['일']['low']}~{wk['일']['high']}°예요"

    pop_2d = max([td.get("pop", 0)] + [daily[d]["pop"] for d in (today + timedelta(days=1),) if d in daily])
    pop_3d = max([daily[d]["pop"] for d in daily] or [0])
    rainy_now = ncst.get("PTY", "0") != "0" or td.get("pop", 0) >= 60

    out: dict = {
        "source": "기상청 · 에어코리아",
        "today": today_block,
        "hourly": hourly,
        "weekly": weekly,
        "outfit": _outfit(round((today_block["high"] + today_block["temp"]) / 2), rainy_now),
        "good_for": [
            {"label": "빨래", "good": pop_2d < 30, "basis": f"오늘·내일 강수확률 최대 {pop_2d}%", "source": "데일리컷 기준(공식 지수 아님) · 강수확률 30% 미만이면 좋음"},
            {"label": "세차", "good": pop_3d < 30, "basis": f"오늘~모레 강수확률 최대 {pop_3d}%", "source": "데일리컷 기준(공식 지수 아님) · 강수확률 30% 미만이면 좋음"},
        ],
        "weekly_range": f"{wanted[0].month}/{wanted[0].day}~{wanted[-1].month}/{wanted[-1].day}",
        "weekend": weekend,  # 비어 있으면 화면에서 숨김(스텁 문구가 남지 않게 항상 덮어씀)
    }

    out["location"] = {"label": region["label"], "code": region["code"], "sgg": region["sgg"]}
    try:
        out["air_quality"] = _air(region)
    except Exception:
        out["air_quality"] = {"pm10": "정보 없음", "pm25": "정보 없음"}

    life = []
    for fn in (_uv, _sun, _pollen):
        try:
            row = fn(now, region)
            if row:
                life.append(row)
        except Exception:
            pass
    try:
        term = _next_term(today)
        if term:
            life.append(term)
    except Exception:
        pass
    out["life"] = life
    try:
        nh = _next_holiday(today)
        if nh:
            out["next_holiday"] = nh
    except Exception:
        pass

    # ---- 오늘의 생활 지수(아이콘·누르면 설명) ----
    warning = {"supported": False, "items": []}
    try:
        warning = _warning(now, region)
    except Exception:
        warning = {"supported": region["code"] in WARNING_REGIONS, "items": [], "error": True}

    day_hours = [allv.get((today.strftime("%Y%m%d"), f"{h:02d}00")) for h in range(9, 19)]
    day_hours = [v for v in day_hours if v]
    pop_day = max([int(v.get("POP", 0)) for v in day_hours] or [0])
    rain_day = any(v.get("PTY", "0") != "0" for v in day_hours)
    reh_vals = [float(v["REH"]) for v in day_hours if "REH" in v]
    wind_vals = [float(v["WSD"]) for v in day_hours if "WSD" in v]
    reh = round(sum(reh_vals) / len(reh_vals)) if reh_vals else None
    wind = round(sum(wind_vals) / len(wind_vals), 1) if wind_vals else None
    air = out.get("air_quality", {})
    dust_bad = air.get("pm25") in ("나쁨", "매우나쁨") or air.get("pm10") in ("나쁨", "매우나쁨")

    # 빨래: 오늘 낮(9~18시)에 잘 마르는 날인가 — 비·습도·미세먼지만 봄(내일·모레 날씨는 보지 않음)
    laundry_lines = [f"낮(9~18시) 강수확률 최대 {pop_day}%" + (" · 비 예보 있음" if rain_day else "")]
    if reh is not None:
        laundry_lines.append(f"낮 평균 습도 {reh}% (60% 아래면 잘 말라요, 70% 넘으면 눅눅해요)")
    if wind is not None:
        laundry_lines.append(f"낮 평균 바람 {wind}m/s (살랑이는 바람이면 더 빨리 말라요)")
    laundry_lines.append(f"미세먼지 {air.get('pm10', '정보 없음')} · 초미세먼지 {air.get('pm25', '정보 없음')}")
    laundry_lines.append("판정 기준: 비 예보나 강수확률 50% 이상이면 별로, 강수확률 30% 이상·습도 70% 이상·미세먼지 나쁨이면 보통, 그 외는 좋음")
    if rain_day or pop_day >= 50:
        laundry_level, laundry_value = "bad", "별로예요"
    elif pop_day >= 30 or (reh is not None and reh >= 70) or dust_bad:
        laundry_level, laundry_value = "ok", "보통이에요"
    else:
        laundry_level, laundry_value = "good", "좋아요"

    # 세차: 닦고 나서 곧 비가 오면 헛수고라서 앞으로 1~2일 비 예보를 봄
    next24 = [h for h in hourly if not h["is_past"]][:24]
    pop_next = max([h["pop"] for h in next24] or [0])
    wet_next = any(any(k in (h["condition"] or "") for k in ("비", "눈", "소나기")) for h in next24)
    d2 = daily.get(today + timedelta(days=2), {})
    pop_d2 = d2.get("pop", 0)
    wash_lines = [f"앞으로 24시간 강수확률 최대 {pop_next}%" + (" · 비/눈 예보 있음" if wet_next else "")]
    if d2:
        wash_lines.append(f"모레({(today + timedelta(days=2)).month}/{(today + timedelta(days=2)).day}) 강수확률 {pop_d2}%")
    wash_lines.append("비가 오기 전에 닦으면 효과가 줄어서, 앞으로 하루이틀 맑을 때가 좋아요")
    if wet_next or pop_next >= 40:
        wash_level, wash_value = "bad", "별로예요"
    elif pop_d2 >= 50:
        wash_level, wash_value = "ok", "보통이에요"
        wash_lines.append("오늘은 괜찮지만 모레쯤 비 예보가 있어요")
    else:
        wash_level, wash_value = "good", "좋아요"

    GRADE_LEVEL = {"좋음": "good", "보통": "ok", "나쁨": "bad", "매우나쁨": "bad"}
    uv_row = next((r for r in life if r["title"] == "자외선"), None)
    sun_row = next((r for r in life if r["title"] == "일출 · 일몰"), None)
    pollen_row = next((r for r in life if r["title"].startswith("꽃가루")), None)
    term_row = next((r for r in life if r["title"] == "다음 절기"), None)
    uv_val = None
    if uv_row:
        import re as _re

        m = _re.search(r"\((\d+)\)", uv_row["meta"])
        uv_val = int(m.group(1)) if m else None

    indexes = [
        {"key": "laundry", "title": "빨래", "value": laundry_value, "level": laundry_level, "detail": laundry_lines,
         "source": "데일리컷 기준(공식 지수 아님) · 기상청 단기예보(강수확률·습도·바람) + 에어코리아 미세먼지로 계산"},
        {"key": "carwash", "title": "세차", "value": wash_value, "level": wash_level, "detail": wash_lines,
         "source": "데일리컷 기준(공식 지수 아님) · 기상청 단기예보 강수확률로 계산"},
        {"key": "pm10", "title": "미세먼지", "value": air.get("pm10", "정보 없음"), "level": GRADE_LEVEL.get(air.get("pm10")),
         "detail": [f"PM10 {air.get('pm10_value')}㎍/㎥" if air.get("pm10_value") is not None else "측정값 없음",
                    f"{air.get('station', '')} 측정소 · {air.get('data_time', '')} 측정", "등급은 에어코리아가 준 값 그대로예요(좋음 30 이하 · 보통 80 이하 · 나쁨 150 이하 · 매우나쁨 초과)"],
         "source": "한국환경공단 에어코리아 실시간 측정값(가공 없이 표시)"},
        {"key": "pm25", "title": "초미세먼지", "value": air.get("pm25", "정보 없음"), "level": GRADE_LEVEL.get(air.get("pm25")),
         "detail": [f"PM2.5 {air.get('pm25_value')}㎍/㎥" if air.get("pm25_value") is not None else "측정값 없음",
                    f"{air.get('station', '')} 측정소 · {air.get('data_time', '')} 측정", "등급은 에어코리아가 준 값 그대로예요(좋음 15 이하 · 보통 35 이하 · 나쁨 75 이하 · 매우나쁨 초과)"],
         "source": "한국환경공단 에어코리아 실시간 측정값(가공 없이 표시)"},
    ]
    if uv_row:
        indexes.append(
            {"key": "uv", "title": "자외선", "value": uv_row["meta"].split(" (")[0], "level": ("good" if (uv_val or 0) <= 2 else "ok" if (uv_val or 0) <= 5 else "bad"),
             "detail": [f"오늘 낮(6~18시) 최고 자외선지수 {uv_val}", f"{region['sido']} 시도 단위 값이에요", "0~2 낮음 · 3~5 보통 · 6~7 높음 · 8~10 매우 높음 · 11 이상 위험",
                        "지수가 6 이상이면 모자·선크림을 챙기세요"],
             "source": "기상청 생활기상지수(자외선지수)"}
        )
    if pollen_row:
        indexes.append({"key": "pollen", "title": "꽃가루", "value": pollen_row["meta"], "level": "bad",
                        "detail": ["잡초류 꽃가루 위험지수", f"{region['sido']} 시도 단위 값이에요"], "source": "기상청 꽃가루농도위험지수"})
    if sun_row:
        indexes.append({"key": "sun", "title": "일출 · 일몰", "value": sun_row["meta"], "level": None,
                        "detail": [f"{region['label']} 중심 좌표 기준", "앞이 일출, 뒤가 일몰 시각이에요"], "source": "한국천문연구원 출몰시각"})
    if term_row:
        indexes.append({"key": "term", "title": "다음 절기", "value": term_row["meta"], "level": None,
                        "detail": ["24절기는 태양의 위치로 정하는 계절의 마디예요"], "source": "한국천문연구원 24절기"})
    if out.get("next_holiday"):
        nh = out["next_holiday"]
        indexes.append({"key": "holiday", "title": "다음 공휴일", "value": f"D-{nh['d_day']}", "level": None,
                        "detail": [f"{nh['name']} ({nh['date']})"], "source": "한국천문연구원 특일정보"})
    # 기상특보: 서울·인천·경기만 제공
    if not warning.get("supported"):
        w_value, w_level, w_detail = "제공 안 함", None, ["기상특보는 지금 서울·인천·경기만 보여드려요", "다른 지역은 기상청 지점 정보를 추가하면 지원할 수 있어요"]
    elif warning.get("items"):
        w_value, w_level = f"{len(warning['items'])}건", "bad"
        w_detail = [x for it in warning["items"] for x in ([it["title"]] + ([it["text"]] if it.get("text") else []))]
    else:
        w_value, w_level = ("확인 못 함" if warning.get("error") else "없음"), ("good" if not warning.get("error") else None)
        w_detail = [f"{region['label']}에 발효 중인 특보가 없어요"] + ([f"참고: 최근 기상청 통보(전국) — {warning['recent']}"] if warning.get("recent") else [])
    indexes.append({"key": "warning", "title": "기상특보", "value": w_value, "level": w_level, "detail": w_detail, "source": "기상청 기상특보(서울·인천·경기만)"})
    # 지진: 최근 3일 국내 영향 지진(전국 공통). 못 받으면 줄 자체를 안 냄.
    try:
        quakes = _cache.cached("quake", "quake:recent", 15, lambda: {"v": _quakes()})["v"]
        if quakes:
            q_detail = [f"{q['loc']} 규모 {q['mt']} ({q['t'][4:6]}/{q['t'][6:8]} {q['t'][8:10]}:{q['t'][10:12]})" for q in quakes[:5]]
            indexes.append({"key": "quake", "title": "지진", "value": f"{len(quakes)}건", "level": "bad", "detail": q_detail + ["최근 3일 기상청이 발표한 국내 지진이에요"], "source": "기상청 지진정보"})
        else:
            indexes.append({"key": "quake", "title": "지진", "value": "없음", "level": "good", "detail": ["최근 3일 동안 국내에서 발표된 지진이 없어요", "해외 지진은 빼고 보여드려요"], "source": "기상청 지진정보(전국, 최근 3일)"})
    except Exception:
        pass
    out["indexes"] = indexes

    # 옷차림: 낮 평균 기온 + 일교차 + 비 여부
    day_temps = [float(v["TMP"]) for v in day_hours if "TMP" in v]
    if day_temps:
        out["outfit"] = _outfit(round(sum(day_temps) / len(day_temps)), rainy_now, (today_block["high"] or 0) - (today_block["low"] or 0))
    return out


def get(code: str, sgg: str | None = None) -> dict | None:
    """지역별 캐시된 날씨(키/수집 실패 시 None → 스텁). 같은 시군구는 25분 동안 외부를 다시 안 부름."""
    if not available():
        return None
    pl = geo.place(code, sgg)
    try:
        return _cache.cached("weather", f"weather:{pl['key']}", 25, lambda: fetch(pl["code"], pl["sgg"]))
    except Exception:
        return None


def _warm() -> dict:
    """기본 지역(서울) 날씨를 미리 데워 둠 — 캐시가 25분마다 만료돼서 방문자가 기다리지 않게(2026-10-14).
    에어코리아 일 500회 한도: 30분마다 = 하루 48회 수준."""
    get("11", None)
    return {"ok": True}


jobs.register(jobs.Job(name="weather_warm", run=_warm, env_keys=[], interval_min=30))
