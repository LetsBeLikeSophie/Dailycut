# -*- coding: utf-8 -*-
"""정리 작업 점검(임시 DB 사용 — 실제 DB는 안 건드림): python backend/test_prune.py"""
import os
import sys
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
os.environ["DAILYCUT_DB"] = str(Path(tempfile.mkdtemp()) / "t.db")

import store  # noqa: E402

store.init()
old = (datetime.now() - timedelta(days=10)).isoformat(timespec="seconds")
fresh = datetime.now().isoformat(timespec="seconds")
c = store._conn()
c.executemany("INSERT INTO cache(name,payload,fetched_at) VALUES (?,?,?)", [
    ("culture:kcisa:20260101", "{}", old),   # 요청 때 계산한 칸, 오래됨 -> 삭제
    ("culture:kcisa:20260102", "{}", fresh),  # 요청 때 계산한 칸, 최근 -> 유지
    ("market", "{}", old),                    # 작업의 마지막 성공값 -> 오래돼도 유지
    ("outing3:11:*", "{}", old),              # 슬래시/콜론 칸, 오래됨 -> 삭제
])
c.executemany("INSERT INTO usage_events(day,name,prop,n) VALUES (?,?,?,?)", [
    ((datetime.now() - timedelta(days=800)).date().isoformat(), "tab_view", "life", 3),  # 24개월 넘음 -> 삭제
    (datetime.now().date().isoformat(), "tab_view", "life", 5),                         # 유지
])
c.executemany("INSERT INTO price_history(source,item,day,price) VALUES (?,?,?,?)", [
    ("at", "옛품목", "2010-03-24", 100.0),                                    # 400일 넘게 끊김 -> 삭제
    ("at", "배추", (datetime.now() - timedelta(days=30)).date().isoformat(), 3000.0),  # 유지
    ("at", "배추", datetime.now().date().isoformat(), 3100.0),               # 유지
])
c.commit()
c.close()

r = store.prune(7, 730, 400, protect={"market"})
assert r == {"cache": 2, "usage_events": 1, "price_history": 1}, r
left = {row["name"] for row in store._query("SELECT name FROM cache")}
assert left == {"culture:kcisa:20260102", "market"}, left
assert store._query("SELECT COUNT(*) AS n FROM price_history")[0]["n"] == 2
assert store._query("SELECT COUNT(*) AS n FROM usage_events")[0]["n"] == 1
# 한 번 더 돌려도 안전(지울 게 없음)
assert store.prune(7, 730, 400, protect={"market"}) == {"cache": 0, "usage_events": 0, "price_history": 0}
print("OK", r)
