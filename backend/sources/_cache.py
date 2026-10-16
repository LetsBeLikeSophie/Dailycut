# -*- coding: utf-8 -*-
"""요청 시점에 계산하는(위치별) 소스용 캐시.

전국 공통 소스(생활 시세·머니)는 jobs.py가 백그라운드로 주기 수집하지만, 날씨·문화처럼
사용자 위치에 따라 달라지는 소스는 위치마다 따로 불러야 해서 요청이 올 때 부르고
위치 칸(격자 등)별로 TTL 동안 캐시함. 외부 API 하루 한도(기상청 1만, 에어코리아 500)를
지키려는 목적이라, 같은 칸의 요청은 TTL 안에서 외부를 다시 안 부름.
실패하면 마지막 성공값(오래됐어도)을 돌려주고, 한 번도 성공한 적이 없으면 예외를 던짐.
"""

from __future__ import annotations

import threading
from datetime import datetime, timedelta
from typing import Callable

import store

_locks: dict[str, threading.Lock] = {}
_guard = threading.Lock()


_STALE_EXTRA_MIN = 180


def peek(key: str, ttl_min: int) -> dict | None:
    """저장돼 있고 아직 신선하면 그 값, 아니면 None(외부를 부르지 않음)."""
    hit = store.load_cache(key)
    if hit and datetime.now() - datetime.fromisoformat(hit[1]) < timedelta(minutes=ttl_min):
        return hit[0]
    return None


def _refresh_async(source: str, key: str, fn: Callable[[], dict]) -> None:
    """만료된 칸을 뒤에서 새로 받음. 이미 누가 받는 중이면 아무것도 안 함(락을 못 잡으면 그냥 지나감)."""
    with _guard:
        lock = _locks.setdefault(key, threading.Lock())
    if not lock.acquire(blocking=False):
        return

    def work() -> None:
        try:
            store.save_cache(key, fn())
            store.set_status(source, ok=True)
        except Exception as e:  # 실패해도 옛 값이 그대로 남음
            store.set_status(source, ok=False, error=f"{type(e).__name__}: {e}")
        finally:
            lock.release()

    threading.Thread(target=work, daemon=True).start()


def cached(source: str, key: str, ttl_min: int, fn: Callable[[], dict], shared: bool = False) -> dict:
    """source: 상태 표시용 이름(예: "weather"), key: 캐시 키(위치 칸 포함).
    shared=True: 큰 읽기 전용 캐시(파싱 결과를 기억) — 돌려받은 값을 고치면 안 됨."""
    hit = store.load_cache(key, shared)
    if hit:
        age = datetime.now() - datetime.fromisoformat(hit[1])
        if age < timedelta(minutes=ttl_min):
            return hit[0]
        # 2026-10-14: 만료 직후 처음 온 방문자가 외부 API가 끝날 때까지(날씨 약 20초) 기다리던 문제 —
        # 너무 오래되지 않았으면(만료 후 3시간 안) 옛 값을 바로 주고 새 값은 뒤에서 받음.
        if age < timedelta(minutes=ttl_min + _STALE_EXTRA_MIN):
            _refresh_async(source, key, fn)
            return hit[0]
    with _guard:
        lock = _locks.setdefault(key, threading.Lock())
    with lock:  # 같은 칸을 동시에 여러 번 부르지 않게
        hit = store.load_cache(key, shared)
        if hit and datetime.now() - datetime.fromisoformat(hit[1]) < timedelta(minutes=ttl_min):
            return hit[0]
        try:
            payload = fn()
        except Exception as e:
            store.set_status(source, ok=False, error=f"{type(e).__name__}: {e}")
            if hit:
                return hit[0]
            raise
        store.save_cache(key, payload)
        store.set_status(source, ok=True)
        return payload
