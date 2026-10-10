# -*- coding: utf-8 -*-
"""소스별 수집기. 파일 하나가 jobs.register(Job(...)) 한 번.

각 수집기는 `run() -> dict`가 api.py 해당 엔드포인트 응답에 덮어쓸 필드만
돌려줌. 덮어쓰지 않은 필드는 스텁이 그대로 나가고, 응답의 live_keys에 덮어쓴
필드 이름이 들어가서 화면이 "예시 데이터"를 구분할 수 있음.

  weather — 기상청 단기·중기예보, 에어코리아, 특일정보          (투데이)
  market  — 농수산식품유통공사 최근일자 소매가 + 가격 이력 저장   (생활)
  culture — 한국관광공사 축제, 한국문화정보원 공연              (문화)
  money   — 금융위원회 지수시세(코스피·코스닥)·일반상품(금·유가)  (머니)
"""

from sources import culture, market, money, weather  # noqa: F401  (import하면 작업이 등록됨)
