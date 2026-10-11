# -*- coding: utf-8 -*-
"""dailycut.db 일일 백업: SQLite 온라인 백업 API로 일관된 사본을 만들고 gzip, 14일치만 보관."""
import gzip
import shutil
import sqlite3
import time
from datetime import datetime
from pathlib import Path

SRC = Path("/home/ubuntu/dailycut-backend/dailycut.db")
DST = Path("/home/ubuntu/dailycut-backups")
KEEP_DAYS = 14

DST.mkdir(exist_ok=True)
stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
tmp = DST / f"dailycut-{stamp}.db"
src = sqlite3.connect(SRC)
dst = sqlite3.connect(tmp)
with dst:
    src.backup(dst)
dst.close()
src.close()
with open(tmp, "rb") as f, gzip.open(str(tmp) + ".gz", "wb") as g:
    shutil.copyfileobj(f, g)
tmp.unlink()
cut = time.time() - KEEP_DAYS * 86400
for p in DST.glob("dailycut-*.db.gz"):
    if p.stat().st_mtime < cut:
        p.unlink()
print("backup ok", stamp)
