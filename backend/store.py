# -*- coding: utf-8 -*-
"""SQLite 저장소: 수집 결과 캐시 + 가격 이력 + 수집 상태.

- cache: 소스별 마지막으로 성공한 응답(JSON). 수집이 실패해도 이 값을 계속
  내보내서(last-good) 화면이 비지 않게 함.
- price_history: 하루 한 줄씩 쌓는 가격 스냅샷. "지난주/작년 같은 날 대비",
  이번 달 추이 차트의 원천 — 쌓기 시작한 날부터만 존재함.
- job_status: 소스별 마지막 실행/성공/오류(오류 메시지는 짧게 잘라 저장).
"""

from __future__ import annotations

import json
from collections import OrderedDict
import os
import sqlite3
import threading
from datetime import datetime, timedelta
from pathlib import Path

DB_PATH = Path(os.environ.get("DAILYCUT_DB") or Path(__file__).with_name("dailycut.db"))
_lock = threading.Lock()


def _conn() -> sqlite3.Connection:
    c = sqlite3.connect(DB_PATH, timeout=10)
    c.row_factory = sqlite3.Row
    return c


def init() -> None:
    with _lock:
        c = _conn()
        try:
            c.executescript(
                """
                CREATE TABLE IF NOT EXISTS cache (
                    name TEXT PRIMARY KEY,
                    payload TEXT NOT NULL,
                    fetched_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS price_history (
                    source TEXT NOT NULL,
                    item TEXT NOT NULL,
                    day TEXT NOT NULL,
                    price REAL NOT NULL,
                    unit TEXT,
                    PRIMARY KEY (source, item, day)
                );
                -- 익명 이용 통계: (날짜, 이벤트, 값)별 횟수만 저장. 사용자·기기 식별 값은 어디에도 없음.
                CREATE TABLE IF NOT EXISTS usage_events (
                    day TEXT NOT NULL,
                    name TEXT NOT NULL,
                    prop TEXT NOT NULL DEFAULT '',
                    n INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (day, name, prop)
                );
                CREATE TABLE IF NOT EXISTS job_status (
                    name TEXT PRIMARY KEY,
                    last_run TEXT,
                    last_ok TEXT,
                    last_error TEXT
                );
                """
            )
            c.commit()
        finally:
            c.close()


def _now() -> str:
    return datetime.now().isoformat(timespec="seconds")


def _exec(sql: str, params: tuple = ()) -> None:
    with _lock:
        c = _conn()
        try:
            c.execute(sql, params)
            c.commit()
        finally:
            c.close()


def _query(sql: str, params: tuple = ()) -> list[sqlite3.Row]:
    with _lock:
        c = _conn()
        try:
            return c.execute(sql, params).fetchall()
        finally:
            c.close()


def save_cache(name: str, payload: dict) -> None:
    _exec(
        "INSERT INTO cache(name, payload, fetched_at) VALUES (?,?,?) "
        "ON CONFLICT(name) DO UPDATE SET payload=excluded.payload, fetched_at=excluded.fetched_at",
        (name, json.dumps(payload, ensure_ascii=False), _now()),
    )


_parsed: "OrderedDict[str, tuple[str, dict]]" = OrderedDict()
_PARSED_MAX = 8  # 메모리가 작은 서버라 큰 캐시 몇 개만(가장 오래 안 쓴 것부터 버림)


def load_cache(name: str, shared: bool = False) -> tuple[dict, str] | None:
    """저장된 마지막 응답. shared=True면 파싱한 결과를 기억해 같은 저장 시각이면 다시 파싱하지 않음(2026-10-16: 캠핑 3,000곳 등
    큰 캐시를 요청마다 JSON으로 풀던 것). **돌려받은 값은 읽기만 해야 함**(여러 요청이 같은 객체를 씀 — 고치면 안 됨)."""
    if shared:
        stamp = _query("SELECT fetched_at FROM cache WHERE name=?", (name,))
        if not stamp:
            return None
        with _lock:
            hit = _parsed.get(name)
            if hit and hit[0] == stamp[0]["fetched_at"]:
                _parsed.move_to_end(name)
                return hit[1], hit[0]
    rows = _query("SELECT payload, fetched_at FROM cache WHERE name=?", (name,))
    if not rows:
        return None
    payload, at = json.loads(rows[0]["payload"]), rows[0]["fetched_at"]
    if shared:
        with _lock:
            _parsed[name] = (at, payload)
            _parsed.move_to_end(name)
            while len(_parsed) > _PARSED_MAX:
                _parsed.popitem(last=False)
    return payload, at


def record_prices(source: str, rows: list[dict]) -> int:
    """rows: {item, day(YYYY-MM-DD), price, unit?}. 같은 날 같은 품목은 덮어씀."""
    with _lock:
        c = _conn()
        try:
            c.executemany(
                "INSERT INTO price_history(source,item,day,price,unit) VALUES (?,?,?,?,?) "
                "ON CONFLICT(source,item,day) DO UPDATE SET price=excluded.price, unit=excluded.unit",
                [(source, r["item"], r["day"], float(r["price"]), r.get("unit")) for r in rows],
            )
            c.commit()
        finally:
            c.close()
    return len(rows)


def prune(keep_cache_days: int, keep_usage_days: int, dead_item_days: int, protect: set[str]) -> dict:
    """오래된 데이터 정리(2026-10-19 데이터 보관 기준 — sources/maintenance.py가 하루 한 번 부름).
    - cache: 요청 때 계산해 둔 칸(이름에 ':' 또는 '/'가 있는 것, 예: 날짜가 키인 행사 캐시)이 keep_cache_days보다 오래 갱신 안 됐으면 삭제.
      작업이 직접 관리하는 칸(protect = 작업 이름들)은 마지막 성공값(last-good)이라 건드리지 않음.
    - usage_events: keep_usage_days보다 오래된 날짜 삭제(익명 통계라 개인정보는 아니지만 무한정 쌓지 않음).
    - price_history: **지우지 않음**(인사이트용 자산) — 다만 마지막 기록이 dead_item_days보다 오래된 품목(2010년 조사값처럼 더 이상 안 들어오는 것)만 삭제.
    삭제가 있었으면 VACUUM으로 파일 크기도 줄임."""
    now = datetime.now()
    cut_cache = (now - timedelta(days=keep_cache_days)).isoformat(timespec="seconds")
    cut_usage = (now.date() - timedelta(days=keep_usage_days)).isoformat()
    cut_dead = (now.date() - timedelta(days=dead_item_days)).isoformat()
    with _lock:
        c = _conn()
        try:
            rows = c.execute("SELECT name FROM cache WHERE fetched_at < ? AND (name LIKE '%:%' OR name LIKE '%/%')", (cut_cache,)).fetchall()
            names = [r["name"] for r in rows if r["name"] not in protect]
            c.executemany("DELETE FROM cache WHERE name=?", [(n,) for n in names])
            n_usage = c.execute("DELETE FROM usage_events WHERE day < ?", (cut_usage,)).rowcount
            n_dead = c.execute(
                "DELETE FROM price_history WHERE (source, item) IN "
                "(SELECT source, item FROM price_history GROUP BY source, item HAVING MAX(day) < ?)",
                (cut_dead,),
            ).rowcount
            c.commit()
            if names or n_usage or n_dead:
                c.isolation_level = None  # VACUUM은 트랜잭션 밖에서
                c.execute("VACUUM")
        finally:
            c.close()
    return {"cache": len(names), "usage_events": n_usage, "price_history": n_dead}


def price_days(source: str) -> set[str]:
    """그 소스의 가격 기록이 이미 있는 날짜(YYYY-MM-DD)들."""
    return {r["day"] for r in _query("SELECT DISTINCT day FROM price_history WHERE source=?", (source,))}


def price_series(source: str, item: str, since: str) -> list[tuple[str, float]]:
    """since(YYYY-MM-DD) 이후의 (날짜, 가격) 오름차순."""
    rows = _query(
        "SELECT day, price FROM price_history WHERE source=? AND item=? AND day>=? ORDER BY day",
        (source, item, since),
    )
    return [(r["day"], r["price"]) for r in rows]


def price_on(source: str, item: str, day: str) -> float | None:
    """day 당일 또는 그 이전 가장 최근 가격."""
    rows = _query(
        "SELECT price FROM price_history WHERE source=? AND item=? AND day<=? ORDER BY day DESC LIMIT 1",
        (source, item, day),
    )
    return rows[0]["price"] if rows else None


def set_status(name: str, *, ok: bool, error: str | None = None) -> None:
    now = _now()
    _exec("INSERT OR IGNORE INTO job_status(name) VALUES (?)", (name,))
    if ok:
        _exec("UPDATE job_status SET last_run=?, last_ok=?, last_error=NULL WHERE name=?", (now, now, name))
    else:
        _exec("UPDATE job_status SET last_run=?, last_error=? WHERE name=?", (now, (error or "")[:200], name))


def all_status() -> dict[str, dict]:
    return {r["name"]: dict(r) for r in _query("SELECT * FROM job_status")}


def record_usage(rows: list[tuple[str, str]]) -> int:
    """rows: (이벤트, 값) 목록 → 오늘 날짜의 횟수를 올림. 개인을 구분하는 정보는 받지도 저장하지도 않음."""
    day = datetime.now().date().isoformat()
    with _lock:
        c = _conn()
        try:
            c.executemany(
                "INSERT INTO usage_events(day,name,prop,n) VALUES (?,?,?,1) "
                "ON CONFLICT(day,name,prop) DO UPDATE SET n=n+1",
                [(day, name, prop) for name, prop in rows],
            )
            c.commit()
        finally:
            c.close()
    return len(rows)
