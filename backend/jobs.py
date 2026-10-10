# -*- coding: utf-8 -*-
"""수집 작업 등록 + 백그라운드 스케줄러.

한 소스(예: 기상청 날씨, KAMIS 시세)가 Job 하나. 서버가 켜져 있는 동안
주기적으로 run()을 불러서 결과를 store에 저장하고, API 엔드포인트는 그 저장된
값만 읽음(요청마다 외부 API를 부르지 않음 — 하루 호출 한도가 100~1만 회라서).

- 필요한 키(env_keys)가 하나라도 없으면 그 작업은 건너뛰고 스텁이 그대로 나감.
- 수집이 실패하면 예외 메시지만 기록하고 마지막 성공값(last-good)을 계속 씀.
- 새 소스 추가: sources/ 아래에 파일을 만들고 register(Job(...)) 호출 후
  sources/__init__.py에서 import.
"""

from __future__ import annotations

import threading
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Callable

import config
import store


@dataclass
class Job:
    name: str  # 캐시 키이자 api.py에서 합치는 이름(예: "weather", "market")
    run: Callable[[], dict]  # 응답에 덮어쓸 필드들을 담은 dict를 반환
    env_keys: list[str] = field(default_factory=list)
    interval_min: int = 60


JOBS: dict[str, Job] = {}
_last_run: dict[str, datetime] = {}


def register(job: Job) -> Job:
    JOBS[job.name] = job
    return job


def run_job(job: Job) -> bool:
    """작업 한 번 실행. 키가 없으면 False(건너뜀), 성공하면 True."""
    _last_run[job.name] = datetime.now()
    if not config.has_keys(job.env_keys):
        store.set_status(job.name, ok=False, error="키 없음(스텁 사용 중)")
        return False
    try:
        payload = job.run()
        store.save_cache(job.name, payload)
        store.set_status(job.name, ok=True)
        return True
    except Exception as e:  # 한 소스의 실패가 서버를 멈추면 안 됨
        store.set_status(job.name, ok=False, error=f"{type(e).__name__}: {e}")
        return False


def get_live(name: str) -> dict | None:
    """저장된 마지막 성공 결과(없으면 None → 호출한 쪽이 스텁을 씀)."""
    cached = store.load_cache(name)
    return cached[0] if cached else None


def _loop(tick_sec: int) -> None:
    while True:
        now = datetime.now()
        for job in list(JOBS.values()):
            last = _last_run.get(job.name)
            if last is None or now - last >= timedelta(minutes=job.interval_min):
                run_job(job)
        time.sleep(tick_sec)


_started = False


def start(tick_sec: int = 30) -> None:
    """서버 시작 때 한 번 호출. 백그라운드 스레드에서 주기 실행."""
    global _started
    if _started:
        return
    _started = True
    threading.Thread(target=_loop, args=(tick_sec,), daemon=True, name="dailycut-jobs").start()


def describe() -> list[dict]:
    """/status용. 키 값은 절대 안 내보내고 '있음/없음'만."""
    st = store.all_status()
    out = []
    for job in JOBS.values():
        s = st.get(job.name, {})
        has = config.has_keys(job.env_keys)
        out.append(
            {
                "name": job.name,
                "mode": "live" if has and s.get("last_ok") else ("waiting" if has else "stub"),
                "keys_present": has,
                "interval_min": job.interval_min,
                "last_ok": s.get("last_ok"),
                "last_error": s.get("last_error"),
            }
        )
    return out
