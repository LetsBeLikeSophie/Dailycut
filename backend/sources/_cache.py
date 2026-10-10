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


def cached(source: str, key: str, ttl_min: int, fn: Callable[[], dict]) -> dict:
    """source: 상태 표시용 이름(예: "weather"), key: 캐시 키(위치 칸 포함)."""
    hit = store.load_cache(key)
    if hit and datetime.now() - datetime.fromisoformat(hit[1]) < timedelta(minutes=ttl_min):
        return hit[0]
    with _guard:
        lock = _locks.setdefault(key, threading.Lock())
    with lock:  # 같은 칸을 동시에 여러 번 부르지 않게
        hit = store.load_cache(key)
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
