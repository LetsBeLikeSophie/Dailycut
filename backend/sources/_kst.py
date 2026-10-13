# -*- coding: utf-8 -*-
"""한국 시간(KST) 헬퍼. 배포 서버는 UTC라서 date.today()가 한국 새벽(0~9시)에는 하루 전 날짜를 줌 —
"접수 N일 남음"·"이번 주말"처럼 날짜가 중요한 곳은 이걸 쓸 것(2026-10-14에 발견)."""

from __future__ import annotations

from datetime import date, datetime, timedelta


def now() -> datetime:
    return datetime.utcnow() + timedelta(hours=9)


def today() -> date:
    return now().date()
