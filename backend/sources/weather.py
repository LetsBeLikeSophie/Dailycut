# -*- coding: utf-8 -*-
"""날씨 수집: 기상청 단기·중기예보 + 에어코리아 + 생활기상지수 + 출몰시각 + 특일정보.

사용자 위치(위경도)로 전국 어디서든 동작함 — 격자(nx, ny)·근접 측정소·중기 예보 구역·
시도 지점코드를 geo.py로 계산하고, 같은 격자 칸은 25분 동안 캐시(_cache.cached).
/weather 응답에 덮어쓸 필드: today, hourly, weekly, weekend, outfit, good_for,
air_quality, life, next_holiday, location, source.
"""

from __future__ import annotations

import math
from datetime import date, datetime, timedelta

import config
import geo
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
    """중기예보(4일 뒤부터). 발표는 06시·18시, 발표 직후에는 아직 없어서 30분 여유."""
    base = now - timedelta(minutes=30)
    if base.hour >= 18:
        tm = base.replace(hour=18, minute=0, second=0, microsecond=0)
    elif base.hour >= 6:
        tm = base.replace(hour=6, minute=0, second=0, microsecond=0)
    else:
        tm = (base - timedelta(days=1)).replace(hour=18, minute=0, second=0, microsecond=0)
    root = _cfg("KMA_MID_FCST_BASE_URL")
    common = {"pageNo": 1, "numOfRows": 10, "dataType": "JSON", "tmFc": tm.strftime("%Y%m%d%H%M")}
    ta = (_http.items_of(_http.get_json(root + "/getMidTa", {**common, "regId": temp_reg})) or [{}])[0]
    land = (_http.items_of(_http.get_json(root + "/getMidLandFcst", {**common, "regId": land_reg})) or [{}])[0]
    out = {}
    for n in range(3, 11):
        d = tm.date() + timedelta(days=n)
        if d not in wanted:
            continue
        low, high = ta.get(f"taMin{n}"), ta.get(f"taMax{n}")
        cond = land.get(f"wf{n}Pm") or land.get(f"wf{n}")
        pop = land.get(f"rnSt{n}Pm") if f"rnSt{n}Pm" in land else land.get(f"rnSt{n}")
        if low is None or high is None or not cond:
            continue
        out[d] = {"low": round(low), "high": round(high), "pop": int(pop or 0), "condition": cond}
    return out


def _outfit(temp: int, rainy: bool) -> str:
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
    return s + (" · 우산도 챙기세요" if rainy else "")


# ---------------- 에어코리아 ----------------

def _grade(value: float, cuts: tuple[float, float, float]) -> str:
    return "좋음" if value <= cuts[0] else "보통" if value <= cuts[1] else "나쁨" if value <= cuts[2] else "매우나쁨"


def _air_rows(sido_air: str) -> list[dict]:
    """시도 전체 측정소의 실시간 값(한 번 받아 시도별로 캐시 → 시군구마다 다시 부르지 않음)."""

    def load() -> dict:
        body = _http.get_json(
            _cfg("AIRKOREA_AIR_QUALITY_BASE_URL") + "/getCtprvnRltmMesureDnsty",
            {"returnType": "json", "numOfRows": 300, "pageNo": 1, "sidoName": sido_air, "ver": "1.0"},
        )
        return {"rows": _http.items_of(body)}

    return _cache.cached("air", f"air:{sido_air}", 25, load)["rows"]


def _air(place: dict) -> dict:
    """고른 시군구의 측정소 평균(없으면 시도 전체 평균). 미세먼지 30/80/150, 초미세먼지 15/35/75 기준 등급.
    측정소마다 값이 달라서 평균을 쓰고, 값이 빈 측정소는 뺌."""
    rows = _air_rows(place["air"])
    mine = [r for r in rows if r.get("stationName") in place["stations"]]
    use, scope = (mine, place["label"]) if mine else (rows, place["sido"])

    def avg(field: str) -> float | None:
        vals = []
        for r in use:
            try:
                vals.append(float(r[field]))
            except (KeyError, TypeError, ValueError):
                pass
        return sum(vals) / len(vals) if vals else None

    pm10, pm25 = avg("pm10Value"), avg("pm25Value")
    return {
        "pm10": _grade(pm10, (30, 80, 150)) if pm10 is not None else "정보 없음",
        "pm25": _grade(pm25, (15, 35, 75)) if pm25 is not None else "정보 없음",
        "pm10_value": round(pm10) if pm10 is not None else None,
        "pm25_value": round(pm25) if pm25 is not None else None,
        "stations": len(use),
        "scope": scope,
    }


# ---------------- 생활 지수 ----------------

def _warning(now: datetime, region: dict) -> dict | None:
    """발효 중인 기상특보. 지점이 서울(108, 수도권) 하나뿐이라 서울·인천·경기에서만 보임 —
    다른 시도는 지점코드 표를 확인해야 함. 평소엔 비어 있고 특보가 있을 때만 줄이 뜸."""
    if region["code"] not in ("11", "28", "41"):
        return None
    body = _http.get_json(
        _cfg("KMA_WARNING_BASE_URL") + "/getWthrWrnList",
        {"stnId": "108", "dataType": "JSON", "numOfRows": 5, "pageNo": 1},
    )
    items = _http.items_of(body)
    if not items:
        return None
    return {"title": "기상특보(서울·수도권)", "meta": str(items[0].get("title") or items[0])[:30], "basis": "기상청 기상특보(서울 지점)"}


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
    daily = _daily(merged, [today + timedelta(days=i) for i in range(3)])

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
                # 기상청이 단기예보(~2일 뒤)와 중기예보(4일 뒤~) 사이의 하루는 제공하지 않아 값이 비는 날이 있음
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
    for fn in (_warning, _uv, _sun, _pollen):
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
