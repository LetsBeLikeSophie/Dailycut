# -*- coding: utf-8 -*-
"""설정/비밀 값 읽기.

API 키는 코드나 저장소에 두지 않고 `backend/.env`(git 추적 안 함)나 서버의
환경변수로만 받음. 형식은 한 줄에 `이름=값`, `#`로 시작하면 주석.
이미 환경변수로 들어와 있는 값이 있으면 .env보다 우선(서버 배포용).
키 값은 어떤 응답/로그에도 내보내지 않음 — 있는지 없는지만 확인함.
"""

from __future__ import annotations

import os
from pathlib import Path

ENV_PATH = Path(__file__).with_name(".env")


def load_env(path: Path = ENV_PATH) -> int:
    """.env를 읽어 os.environ에 채움(이미 있는 값은 안 덮어씀). 새로 채운 개수 반환."""
    if not path.exists():
        return 0
    n = 0
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, _, value = line.partition("=")
        name = name.strip().removeprefix("export ").strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if name and value and name not in os.environ:
            os.environ[name] = value
            n += 1
    return n


def get_key(name: str) -> str | None:
    value = os.environ.get(name, "").strip()
    return value or None


def has_keys(names: list[str]) -> bool:
    return all(get_key(n) for n in names)


load_env()
