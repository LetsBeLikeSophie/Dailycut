"""data/localcurrency_guide.json에서 확인일(checked)이 오래된 항목을 뽑아 줌 — 다시 공식 페이지를 열어 확인할 목록.
  python tools/check_guide_age.py [일수=90]
2026-11-01: 발행 일정·할인율·한도는 회차마다 바뀌어서 확인일을 항목마다 남기고, 이 스크립트로 주기적으로 훑음.
"""
import json
import os
import sys
from datetime import date

FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "localcurrency_guide.json")
LIMIT = int(sys.argv[1]) if len(sys.argv) > 1 else 90


def walk(label, e, out):
    c = e.get("checked")
    if c:
        age = (date.today() - date.fromisoformat(c)).days
        n = e.get("notice") or {}
        out.append((age, label, c, n.get("date", "")))
    for name, sub in (e.get("sigungu") or {}).items():
        walk(f"{label} {name}", sub, out)


def main():
    data = json.load(open(FILE, encoding="utf-8"))
    rows = []
    for code, e in data["regions"].items():
        walk(code, e, rows)
    rows.sort(reverse=True)
    old = [r for r in rows if r[0] >= LIMIT]
    print(f"전체 {len(rows)}곳 중 확인한 지 {LIMIT}일 이상: {len(old)}곳")
    for age, label, c, nd in old:
        print(f"  {age:>4}일  {label}  (확인 {c}, 최근 공지 {nd or '-'})")


if __name__ == "__main__":
    main()
