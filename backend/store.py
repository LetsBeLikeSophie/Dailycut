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
import os
import sqlite3
import threading
from datetime import datetime
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


def load_cache(name: str) -> tuple[dict, str] | None:
    rows = _query("SELECT payload, fetched_at FROM cache WHERE name=?", (name,))
    return (json.loads(rows[0]["payload"]), rows[0]["fetched_at"]) if rows else None


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
