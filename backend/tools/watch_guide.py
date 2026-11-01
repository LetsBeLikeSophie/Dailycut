"""지역화폐 "사는 법" 공식 안내 페이지가 바뀌었는지 감지(2026-11-01). 서버 cron이 돌림.

  python tools/watch_guide.py             각 지역의 공식 공지 페이지(official.url)를 받아 내용 해시를 비교, data/guide_watch.json에 기록
  python tools/watch_guide.py --report    마지막 확인일(checked) 이후 페이지가 바뀐 지역 목록 → 이 지역만 사람이/Claude가 다시 열어 json을 고침
  python tools/watch_guide.py --limit 5   앞에서 5곳만(시험용)

왜: 발행 일정·할인율·한도는 지자체가 회차마다 공지하고, 다음 달 조건은 매월 20~30일에 몰려 올라옴(조사한 공지 게시일 기준).
서버에는 공식 페이지를 읽고 판단할 수 있는 도구가 없으니, 값을 직접 고치지 않고 "바뀐 곳이 어디인가"만 싸게 알려 줌.
주의: 페이지에 방문자 수·시각 같은 움직이는 글이 있으면 헛경보가 날 수 있음(40곳 시험에서 2곳 불안정, 하나는 공백 차이라 공백을 지워 해결)(그래서 앱에는 안 보이고 --report로만 봄).
cron(서버, UTC 기준; KST = UTC+9): 평소 주 1회 + 매월 20일~3일은 매일
  0 19 * * 0        cd /home/ubuntu/dailycut-backend && venv/bin/python tools/watch_guide.py >> data/guide_watch.log 2>&1
  0 19 20-31,1-3 * * cd /home/ubuntu/dailycut-backend && venv/bin/python tools/watch_guide.py >> data/guide_watch.log 2>&1
"""
import hashlib
import html
import json
import os
import re
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUIDE = os.path.join(ROOT, "data", "localcurrency_guide.json")
STATE = os.path.join(ROOT, "data", "guide_watch.json")
UA = "Mozilla/5.0 (compatible; DailyCutGuideWatch/1.0; +mailto:dailycut@itssophie.dev)"
KST = timezone(timedelta(hours=9))


def today() -> str:
    return datetime.now(KST).strftime("%Y-%m-%d")


def targets() -> dict[str, dict]:
    """공식 페이지 주소 → {label, checked}. 한 주소를 여러 지역이 쓰면 먼저 나온 지역 이름으로."""
    out: dict[str, dict] = {}
    regions = json.load(open(GUIDE, encoding="utf-8"))["regions"]

    def walk(label, e):
        url = (e.get("official") or {}).get("url")
        if url and url not in out:
            out[url] = {"label": label, "checked": e.get("checked") or ""}
        for name, sub in (e.get("sigungu") or {}).items():
            walk(f"{label} {name}", sub)

    for code, e in regions.items():
        walk(code, e)
    return out


def normalize(raw: bytes) -> str:
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("euc-kr", "ignore")
    text = re.sub(r"(?is)<(script|style|noscript)\b.*?</\1>", " ", text)
    text = re.sub(r"(?s)<!--.*?-->", " ", text)
    text = re.sub(r"(?s)<[^>]+>", " ", text)
    text = html.unescape(text)
    text = re.sub(r"\d{4}[-./]\d{1,2}[-./]\d{1,2}\s+\d{1,2}:\d{2}(:\d{2})?", " ", text)  # 날짜+시각(방문·갱신 시각) 제거
    text = re.sub(r"(조회|방문자?|접속)\s*:?\s*[\d,]+", " ", text)
    return re.sub(r"\s+", "", text)  # 띄어쓰기 차이로 헛경보가 나지 않게 공백은 전부 지움


def fetch(url: str):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = r.read(2_000_000)
        text = normalize(raw)
        if len(text) < 200:  # 본문이 거의 없으면(자바스크립트로 그리는 페이지·차단 안내) 비교할 수 없음
            return url, None, f"본문 {len(text)}자"
        return url, hashlib.sha256(text.encode("utf-8")).hexdigest()[:16], None
    except Exception as e:  # 연결 거부·인증서·시간 초과 등: 바뀐 게 아니라 못 연 것
        return url, None, type(e).__name__


def run(limit: int | None):
    tg = targets()
    urls = list(tg)[:limit] if limit else list(tg)
    state = json.load(open(STATE, encoding="utf-8")) if os.path.exists(STATE) else {}
    with ThreadPoolExecutor(6) as ex:
        results = list(ex.map(fetch, urls))
    changed = failed = 0
    for url, h, err in results:
        st = state.setdefault(url, {"first_seen": today(), "errors": 0})
        st["label"] = tg[url]["label"]
        st["last_checked"] = today()
        if err:
            st["errors"] = st.get("errors", 0) + 1
            st["last_error"] = err
            failed += 1
            continue
        st["errors"] = 0
        st.pop("last_error", None)
        if st.get("hash") and st["hash"] != h:
            st["last_changed"] = today()
            changed += 1
        st["hash"] = h
    json.dump(state, open(STATE, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"[{datetime.now(KST):%Y-%m-%d %H:%M}] 확인 {len(urls)}곳 · 바뀜 {changed} · 못 연 곳 {failed}")


def report():
    tg = targets()
    state = json.load(open(STATE, encoding="utf-8")) if os.path.exists(STATE) else {}
    rows = []
    for url, info in tg.items():
        st = state.get(url) or {}
        if st.get("last_changed") and st["last_changed"] > info["checked"]:
            rows.append((st["last_changed"], info["label"], info["checked"], url))
    rows.sort(reverse=True)
    print(f"확인일 이후 공식 페이지가 바뀐 곳 {len(rows)}곳")
    for changed, label, checked, url in rows:
        print(f"  {changed} 변경 · 확인일 {checked} · {label} · {url}")
    dead = [(st.get("label"), url, st.get("last_error")) for url, st in state.items() if st.get("errors", 0) >= 3]
    if dead:
        print(f"연속 3번 이상 못 연 곳 {len(dead)}곳")
        for label, url, err in dead:
            print(f"  {label} · {err} · {url}")


if __name__ == "__main__":
    if "--report" in sys.argv:
        report()
    else:
        lim = int(sys.argv[sys.argv.index("--limit") + 1]) if "--limit" in sys.argv else None
        run(lim)
