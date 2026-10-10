# -*- coding: utf-8 -*-
"""날씨 수집: 기상청 단기예보·중기예보 + 에어코리아 + 특일정보(다음 공휴일).

/weather 응답에 덮어쓸 필드를 만듦: today, hourly, weekly, weekend, outfit,
good_for, air_quality, next_holiday, source.
위치는 지금 서울(격자 nx=60, ny=127 / 중기 육상 11B00000, 기온 11B10101 /
측정소 중구)로 고정 — 사용자 위치별 날씨는 나중에(위경도→격자 변환 필요).
"""

from __future__ import annotations

import math
from datetime import date, datetime, timedelta

import config
import jobs
from sources import _http

NX, NY = 60, 127
MID_LAND_REG, MID_TEMP_REG = "11B00000", "11B10101"
AIR_STATION = "중구"
WEEKDAYS = ["월", "화", "수", "목", "금", "토", "일"]
SKY = {"1": "맑음", "3": "구름 많음", "4": "흐림"}
PTY = {"1": "비", "2": "비/눈", "3": "눈", "4": "소나기", "5": "빗방울", "6": "빗방울눈날림", "7": "눈날림"}
GRADE = {"1": "좋음", "2": "보통", "3": "나쁨", "4": "매우나쁨"}


def _cfg(name: str) -> str:
    v = config.get_key(name)
    if not v:
        raise RuntimeError(f"{name} 없음")
    return v


def _short(base_date: str, base_time: str) -> dict[tuple[str, str], dict[str, str]]:
    body = _http.get_json(
        _cfg("KMA_SHORT_FCST_BASE_URL") + "/getVilageFcst",
        {"pageNo": 1, "numOfRows": 1000, "dataType": "JSON", "base_date": base_date, "base_time": base_time, "nx": NX, "ny": NY},
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


def _ncst(now: datetime) -> dict[str, str]:
    """초단기실황(지금 관측): 정시 자료는 40분 뒤부터 나와서 45분 전 정시를 씀."""
    t = now - timedelta(minutes=45)
    body = _http.get_json(
        _cfg("KMA_SHORT_FCST_BASE_URL") + "/getUltraSrtNcst",
        {"pageNo": 1, "numOfRows": 20, "dataType": "JSON", "base_date": t.strftime("%Y%m%d"), "base_time": t.strftime("%H00"), "nx": NX, "ny": NY},
    )
    return {it["category"]: it["obsrValue"] for it in _http.items_of(body)}


def _cond(vals: dict[str, str]) -> str:
    pty = vals.get("PTY", "0")
    return PTY.get(pty) or SKY.get(vals.get("SKY", "1"), "맑음")


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


def _mid(now: datetime, wanted: list[date]) -> dict[date, dict]:
    """중기예보(3~10일 뒤). 발표는 06시·18시, 발표 직후에는 아직 없어서 30분 여유."""
    base = now - timedelta(minutes=30)
    if base.hour >= 18:
        tm = base.replace(hour=18, minute=0, second=0, microsecond=0)
    elif base.hour >= 6:
        tm = base.replace(hour=6, minute=0, second=0, microsecond=0)
    else:
        tm = (base - timedelta(days=1)).replace(hour=18, minute=0, second=0, microsecond=0)
    tm_fc = tm.strftime("%Y%m%d%H%M")
    root = _cfg("KMA_MID_FCST_BASE_URL")
    common = {"pageNo": 1, "numOfRows": 10, "dataType": "JSON", "tmFc": tm_fc}
    ta = (_http.items_of(_http.get_json(root + "/getMidTa", {**common, "regId": MID_TEMP_REG})) or [{}])[0]
    land = (_http.items_of(_http.get_json(root + "/getMidLandFcst", {**common, "regId": MID_LAND_REG})) or [{}])[0]
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


def _air() -> dict:
    body = _http.get_json(
        _cfg("AIRKOREA_AIR_QUALITY_BASE_URL") + "/getMsrstnAcctoRltmMesureDnsty",
        {"returnType": "json", "numOfRows": 6, "pageNo": 1, "stationName": AIR_STATION, "dataTerm": "DAILY", "ver": "1.0"},
    )
    # 매 정시 직후에는 최신 행의 값이 비어 있어서(null) 값이 있는 가장 최근 행을 씀
    rows = _http.items_of(body)
    it = next((r for r in rows if r.get("pm10Grade") and r.get("pm25Grade")), rows[0] if rows else {})
    return {"pm10": GRADE.get(str(it.get("pm10Grade")), "정보 없음"), "pm25": GRADE.get(str(it.get("pm25Grade")), "정보 없음")}


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


def run() -> dict:
    now = datetime.now()
    today = now.date()

    ncst = _ncst(now)
    base_date, base_time = _latest_base(now)
    latest = _short(base_date, base_time)
    # 오늘 최저/최고는 02시 발표분에만 들어 있음(02시 20분 전이면 어제 23시 발표분)
    if now - timedelta(minutes=20) >= now.replace(hour=2, minute=0, second=0, microsecond=0):
        daily_src = _short(today.strftime("%Y%m%d"), "0200")
    else:
        daily_src = _short((today - timedelta(days=1)).strftime("%Y%m%d"), "2300")
    merged = {k: {**daily_src.get(k, {}), **latest.get(k, {})} for k in set(daily_src) | set(latest)}
    daily = _daily(merged, [today + timedelta(days=i) for i in range(3)])

    # 지금
    temp = float(ncst.get("T1H", "nan"))
    if math.isnan(temp):
        raise RuntimeError("실황 기온 없음")
    here = latest.get((today.strftime("%Y%m%d"), now.strftime("%H00"))) or next((v for (d, t), v in sorted(latest.items()) if (d, t) >= (today.strftime("%Y%m%d"), now.strftime("%H00"))), {})
    cond_now = PTY.get(ncst.get("PTY", "0")) or SKY.get(here.get("SKY", "1"), "맑음")
    td = daily.get(today, {})
    today_block = {
        "temp": round(temp),
        "feels_like": _feels_like(temp, float(ncst.get("WSD", 0) or 0)),
        "condition": cond_now,
        "high": td.get("high", round(temp)),
        "low": td.get("low", round(temp)),
    }

    # 시간대별: 3시간 간격 8칸
    hourly = []
    start = now.replace(minute=0, second=0, microsecond=0)
    for i in range(0, 24, 3):
        t = start + timedelta(hours=i)
        v = latest.get((t.strftime("%Y%m%d"), t.strftime("%H00")))
        if not v or "TMP" not in v:
            continue
        hourly.append({"time": t.strftime("%H시"), "temp": round(float(v["TMP"])), "condition": _cond(v), "pop": int(v.get("POP", 0))})
        if len(hourly) == 8:
            break

    # 주간: 내일~6일 뒤(단기 2일 + 중기)
    wanted = [today + timedelta(days=i) for i in range(1, 7)]
    by_day = dict(daily)
    try:
        by_day.update(_mid(now, wanted))
    except Exception:
        pass  # 중기예보가 안 와도 단기 구간은 보여줌
    weekly = [
        {"day": WEEKDAYS[d.weekday()], "date": f"{d.month}/{d.day}", "high": by_day[d]["high"], "low": by_day[d]["low"], "condition": by_day[d]["condition"], "pop": by_day[d]["pop"]}
        for d in wanted
        if d in by_day
    ]

    # 주말 한 줄
    wk = {w["day"]: w for w in weekly}
    weekend = ""
    if "토" in wk and "일" in wk:
        weekend = f"토요일은 {wk['토']['condition']} {wk['토']['low']}~{wk['토']['high']}°, 일요일은 {wk['일']['condition']} {wk['일']['low']}~{wk['일']['high']}°예요"

    # 빨래/세차: 비 예보 기준 규칙
    pop_2d = max([td.get("pop", 0)] + [daily[d]["pop"] for d in (today + timedelta(days=1),) if d in daily])
    pop_3d = max([daily[d]["pop"] for d in daily] or [0])
    rainy_now = ncst.get("PTY", "0") != "0" or td.get("pop", 0) >= 60

    out = {
        "source": "기상청 · 에어코리아",
        "today": today_block,
        "hourly": hourly,
        "weekly": weekly,
        "outfit": _outfit(round((today_block["high"] + today_block["temp"]) / 2), rainy_now),
        "good_for": [{"label": "빨래", "good": pop_2d < 30}, {"label": "세차", "good": pop_3d < 30}],
    }
    out["weekend"] = weekend  # 비어 있으면 화면에서 숨김(스텁 문구가 남지 않게 항상 덮어씀)
    try:
        out["air_quality"] = _air()
    except Exception:
        out["air_quality"] = {"pm10": "정보 없음", "pm25": "정보 없음"}
    try:
        nh = _next_holiday(today)
        if nh:
            out["next_holiday"] = nh
    except Exception:
        pass
    return out


jobs.register(jobs.Job(name="weather", run=run, env_keys=[_http.KEY_ENV, "KMA_SHORT_FCST_BASE_URL", "KMA_MID_FCST_BASE_URL"], interval_min=30))
