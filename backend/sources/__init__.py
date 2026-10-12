# -*- coding: utf-8 -*-
"""소스별 수집기.

전국 공통(백그라운드 주기 수집, jobs.register):
  market  — 농수산식품유통공사 최근일자 소매가 + 가격 이력 저장   (생활)
  money   — 금융위원회 지수시세·일반상품시세, 소비자물가           (머니)
  gov_support — 행정안전부 공공서비스(혜택) 정보(정부 지원)       (머니)
  livestock — 축산물품질평가원 소·돼지 소비자가격                  (생활)
  boxoffice — 영화진흥위원회 KOBIS 일별 박스오피스                  (문화)
사용자 위치별(요청 시 계산 + 위치 칸 캐시, sources/_cache.py):
  weather — 기상청 단기·중기예보, 에어코리아, 생활기상지수, 출몰시각   (투데이)
  culture — 한국관광공사 축제, 한국문화정보원 전시·공연 (시도별)         (문화)
  markets — 전통시장현황 파일 데이터(정적, 시도별, 키 불필요)             (생활)

각 수집기는 api.py 해당 엔드포인트 응답에 덮어쓸 필드만 돌려줌. 덮어쓰지 않은 필드는
스텁이 그대로 나가고, 응답의 live_keys에 덮어쓴 필드 이름이 들어가서 화면이
"예시 데이터"를 구분할 수 있음.
"""

from sources import boxoffice, culture, finance, gov_support, livestock, market, markets, money, weather  # noqa: F401  (market·money는 import하면 작업이 등록됨)
