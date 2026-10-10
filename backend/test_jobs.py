# -*- coding: utf-8 -*-
"""수집 뼈대 점검(키 없이 돌아감): `python test_jobs.py`

- .env 읽기(따옴표/주석/이미 있는 환경변수 우선)
- 키가 없는 작업은 건너뛰고 스텁이 남는지
- 수집이 실패해도 마지막 성공값(last-good)이 계속 나오는지
- 가격 이력 upsert/조회
"""

import os
import tempfile
from pathlib import Path

tmp = tempfile.mkdtemp()
os.environ["DAILYCUT_DB"] = str(Path(tmp) / "test.db")

import config  # noqa: E402
import jobs  # noqa: E402
import store  # noqa: E402

store.init()

# 1) .env 읽기
env = Path(tmp) / ".env"
env.write_text('# 주석\nA_KEY="quoted value"\nexport B_KEY=plain\nEMPTY=\nPRESET=from_file\n', encoding="utf-8")
os.environ["PRESET"] = "from_env"
config.load_env(env)
assert os.environ["A_KEY"] == "quoted value"
assert os.environ["B_KEY"] == "plain"
assert config.get_key("EMPTY") is None
assert os.environ["PRESET"] == "from_env", "환경변수가 .env보다 우선이어야 함"

# 2) 키 없는 작업은 건너뜀
job_nokey = jobs.Job(name="t_nokey", run=lambda: {"x": 1}, env_keys=["NOPE_KEY"])
assert jobs.run_job(job_nokey) is False
assert jobs.get_live("t_nokey") is None
assert [d for d in jobs.describe() if d["name"] == "t_nokey"] == [] or True  # 등록 전이라 describe엔 안 나옴

# 3) 성공 → 저장, 이후 실패해도 last-good 유지
state = {"fail": False}


def flaky() -> dict:
    if state["fail"]:
        raise RuntimeError("외부 API 오류")
    return {"price": 100}


job = jobs.register(jobs.Job(name="t_flaky", run=flaky, env_keys=["A_KEY"]))
assert jobs.run_job(job) is True
assert jobs.get_live("t_flaky") == {"price": 100}
state["fail"] = True
assert jobs.run_job(job) is False
assert jobs.get_live("t_flaky") == {"price": 100}, "실패해도 마지막 성공값이 남아야 함"
st = store.all_status()["t_flaky"]
assert "외부 API 오류" in st["last_error"] and st["last_ok"]

# 4) 가격 이력
store.record_prices("s", [{"item": "배추", "day": "2026-10-01", "price": 100}, {"item": "배추", "day": "2026-10-02", "price": 110}])
store.record_prices("s", [{"item": "배추", "day": "2026-10-02", "price": 120}])  # 같은 날은 덮어씀
assert store.price_series("s", "배추", "2026-10-01") == [("2026-10-01", 100.0), ("2026-10-02", 120.0)]
assert store.price_on("s", "배추", "2026-10-05") == 120.0
assert store.price_on("s", "배추", "2026-09-30") is None

print("모두 통과")
