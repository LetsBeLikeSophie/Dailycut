# -*- coding: utf-8 -*-
"""소스별 수집기.

전국 공통(백그라운드 주기 수집, jobs.register):
  market  — 농수산식품유통공사 최근일자 소매가 + 가격 이력 저장   (생활)
  gov_support — 행정안전부 공공서비스(혜택) 정보(정부 지원)       (혜택)
  benefits — 청약홈·마이홈·LH 공고, 서민금융 대출상품               (혜택)
  outing — 관광공사 관광지 집중률 예측(이번 주말 한산한 곳, 요청 시 + 24시간 캐시) (문화)
  livestock — 축산물품질평가원 소·돼지 소비자가격                  (생활)
사용자 위치별(요청 시 계산 + 위치 칸 캐시, sources/_cache.py):
  weather — 기상청 단기·중기예보, 에어코리아, 생활기상지수, 출몰시각   (투데이)
  culture — 한국관광공사 축제, 한국문화정보원 전시·공연 (시도별)         (문화)
  markets — 전통시장현황 파일 데이터(정적, 시도별, 키 불필요)             (생활)

각 수집기는 api.py 해당 엔드포인트 응답에 덮어쓸 필드만 돌려줌. 덮어쓰지 않은 필드는
스텁이 그대로 나가고, 응답의 live_keys에 덮어쓴 필드 이름이 들어가서 화면이
"예시 데이터"를 구분할 수 있음.
"""

# 2026-10-13: 광고(상업 이용) 약관 때문에 금융위 지수·상품(money), 금감원 금리(finance), KOBIS(boxoffice)는 등록하지 않음.
# 파일(money.py·finance.py·boxoffice.py)은 남겨 뒀고, 허락을 받으면 아래 import에 다시 넣으면 작업이 등록됨.
from sources import benefits, culture, gov_support, livestock, maintenance, market, markets, outing, places, weather  # noqa: F401  (market 등은 import하면 작업이 등록됨)
