# -*- coding: utf-8 -*-
"""정리 작업(2026-10-19): 하루 한 번 오래된 데이터를 지워 DB가 끝없이 커지지 않게 함.

데이터 보관 기준(개인정보처리방침·docs/ops-server.md와 같이 볼 것):
  요청 때 계산한 캐시   7일 안 갱신되면 삭제 (예: culture:kcisa:날짜 — 하루 600KB씩 쌓이던 것)
  익명 이용 통계         24개월
  가격 이력              계속 보관(작고 인사이트용) — 400일 넘게 기록이 끊긴 품목만 삭제
  접속 로그(nginx)       14일(logrotate)   ·   DB 백업 14일(backup_db.py)
작업 이름(JOBS 키)과 같은 cache 행은 마지막 성공값이라 지우지 않음.
"""

from __future__ import annotations

import jobs
import store

CACHE_KEEP_DAYS = 7
USAGE_KEEP_DAYS = 730
DEAD_ITEM_DAYS = 400


def run() -> dict:
    return store.prune(CACHE_KEEP_DAYS, USAGE_KEEP_DAYS, DEAD_ITEM_DAYS, protect=set(jobs.JOBS))


jobs.register(jobs.Job(name="prune", run=run, env_keys=[], interval_min=1440))
