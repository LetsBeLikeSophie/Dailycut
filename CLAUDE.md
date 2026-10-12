# 프로젝트 컨텍스트 (Claude Code용)

## 이게 뭔지

**데일리컷** — 공공 데이터(시세·문화·금리)를 매일 모아 카드로 보여주는 큐레이션
앱. 직접 글을 쓰지 않고, 공공 API를 받아 카드로 만들고 AI가 짧은 해설을 붙여요.
이슈팝(뉴스 트렌드 클러스터링 앱, `C:\Users\lllso\Downloads\news-trend-app_1_new`)
을 만들다가 나온 아이디어인데, 콘텐츠 성격·소싱 방식·업데이트 주기가 너무 달라서
완전히 별도 앱으로 분리했어요. 이슈팝 코드는 하나도 재사용 안 함 — 새로 설계.

- 기획 문서: https://claude.ai/artifact/U8h2Ukqj5FfBkLaPGVgtBZ
- 디자인 캔버스: https://claude.ai/artifact/3oFPf9sqBPZKhk5J43bvz5 ("확정안 v6" 페이지가 최신)

**이름**: "데일리컷"으로 확정(2026-09-29). 기획 문서 안에는 아직 시안용 가제목
"moum"으로 남아있는 곳이 있을 수 있음 — 무시하고 데일리컷으로 통일.

## 구조

- `backend/` — FastAPI (`api.py`). `uvicorn api:app --reload --port 8010`으로 실행.
  지금은 전부 스텁 데이터 — 각 엔드포인트 위 TODO 주석에 실제 연동할 공공 API
  적어둠(KAMIS/축산물유통정보/KOSIS/KOBIS/KOPIS/TourAPI/ECOS 등).
- `app/` — Flutter. `flutter run -d chrome` 또는 `.claude/launch.json`의
  `dailycut-web` 설정으로 실행(Browser pane에서 `preview_start name: dailycut-web`).
  - `lib/theme.dart` — 디자인 v6 토큰(색·섹션 테마·폰트). 색 바꾸려면 여기만 고치면 됨.
  - `lib/widgets/components.dart` — 기획 문서 "컴포넌트" 표의 부품들
    (SectionHeader, HeroCard, StatTile, RankRow, WeatherHero, SeasonalHero,
    ChartCard). 화면은 이 조합으로만 만듦. ChartCard의 라인 차트는 새 패키지
    없이 CustomPainter로 직접 그림. HeroCard/ChartCard는 `showHeader: false`로
    SectionScreen 안에서 쓸 때 섹션 헤더 중복을 끔(투데이에서만 true 유지).
  - `lib/screens/` — 투데이/생활/문화/머니/AI 다섯 화면("생활"의 Dart
    파일·함수명은 과거 이름 그대로 market/marketScreen — 화면에 보이는
    한글 라벨만 "생활"로 바꿈, enum 이름은 안 바꿈).
  - `lib/api_client.dart` — 백엔드 클라이언트. 기본 `http://127.0.0.1:8010`,
    `--dart-define=API_BASE_URL=...`로 오버라이드(이슈팝과 같은 패턴).

## 배포 (2026-09-30)

이슈팝과 같은 서버(Oracle Cloud, 168.110.25.49)에 얹음 — GitHub repo(코드)와
배포 서버는 별개: 이 저장소는 `github.com/LetsBeLikeSophie/Dailycut`에 SSH로
푸시, 서버 배포는 아래처럼 별도로 함(포트폴리오의 다른 프로젝트 — Cortex 등 —
와 같은 패턴, `itssophie.dev` 서브패스 방식).

- **웹**: https://itssophie.dev/dailycut/ — 정적 파일을 `/var/www/dailycut-app/`에
  올림. `flutter build web --release --base-href /dailycut/
  --dart-define=API_BASE_URL=https://itssophie.dev/dailycut-api`로 빌드(Git
  Bash에서는 `MSYS_NO_PATHCONV=1`을 꼭 붙여야 함 — 안 붙이면 `/dailycut/`가
  `C:/Program Files/Git/dailycut/`로 잘못 치환돼서 빌드가 실패함).
- **API**: https://itssophie.dev/dailycut-api/ — `/home/ubuntu/dailycut-backend/`
  에서 systemd 서비스 `dailycut-api`(포트 8011, 127.0.0.1 바인딩, nginx가
  `/dailycut-api/` → `http://127.0.0.1:8011/`로 프록시)로 상시 실행. 코드
  갱신 시: `scp backend/api.py`로 덮어쓰고 `sudo systemctl restart
  dailycut-api`.
- **nginx**: `/etc/nginx/sites-available/itssophie.dev`에 `/dailycut/`,
  `/dailycut-api/` location 블록 추가함(Cortex 항목 바로 아래). 수정 전 항상
  백업(`sudo cp ... .bak-$(date +%Y%m%d%H%M%S)`) 후 `sudo nginx -t`로 검증하고
  `sudo systemctl reload nginx`.
- **포트폴리오 카드**: `C:\Projects\dailycut`와는 별개 저장소인
  `C:\Projects\portfolio`(github.com/LetsBeLikeSophie/portfolio, 기본 브랜치
  `main`)의 `index.html`에 Dailycut 카드를 추가함(Cortex처럼 "🚧 개발 중"
  태그 — 아직 전부 스텁 데이터라서 "Live"라고 하기엔 이름). 카드 갱신 시 그
  저장소에서 커밋+푸시하고, `/var/www/portfolio/index.html`로도 따로 scp해야
  실제 사이트에 반영됨(포트폴리오 자체 README의 "배포" 항목 참고).

## 화면 디자인 규칙 (2026-10-10, 카드 → 규칙 기반 전면 개편)

카드 상자 방식(헤더 블록/테두리)은 폐기. 생활 탭 시안(`A 큰 도형 + 문장 제목`을
다듬은 한 화면)을 앱 전체에 적용함. 여섯 가지 규칙(`widgets/components.dart` 상단
주석에도 있음):
1. 상자 없음 — 여백과 가는 선(`AppColors.hair`)으로만 구분, 목록 맨 위만 진한 선.
2. 그래픽은 화면 맨 위 큰 도형(`PageHero`의 `_Blob`, 섹션 색 PNG를 200px로 오른쪽
   위에 잘라서 깔고 아주 느리게 흔듦) 하나뿐.
3. 섹션 색은 도형·제목 형광펜(`HighlightText`)·차트 끝점에만. 오르내림은 의미색
   (`AppColors.up/down`).
4. 세리프는 한 문장 제목과 큰 숫자(`BigNumber`)에만. 나머지 전부 산세리프.
5. 목록은 `ListLine`(이름·작은 추이 `MiniSpark`·값/변동) 한 가지 + `RankRow`,
   `SeasonRow`(제철 12개 점, 간트차트 대체). 묶음은 `ListSection`.
6. 글자 크기 11/13/16/24/60 다섯 단계.
각 탭 화면은 `PageHero`(+ 선택적 뒷면 `back`: 누르면 뒤집힘) + `ListSection` 조합.
문화는 TOP3, 머니는 다른 통화가 뒷면. 제철 간트차트가 안 어울린다는 문제는 점
12개로 해결함. 시안 아티팩트: claude.ai/artifact/EknNS7NKWunXRfVFg9rSym

## 실데이터 연동 구조 (2026-10-10)

공공데이터포털 승인분 21건이 나와서 백엔드에 수집 구조를 붙임. 키는 `backend/.env`
(git 추적 안 함, `.env.example`에 이름만)에 있고, 서버에선 환경변수로 넣음.
- `config.py` .env 읽기(환경변수 우선). `get_key/has_keys`로 "있는지"만 확인, 값은
  어떤 응답·로그에도 안 냄(requests 오류 메시지도 키가 든 URL을 빼고 던짐 — `sources/_http.py`).
- `store.py` SQLite(`dailycut.db`, git 제외): `cache`(소스별 마지막 성공 응답), `price_history`
  (품목·날짜별 가격 — 이번 달 추이의 원천), `job_status`.
- `jobs.py` 소스 1개 = `Job`. 서버 시작 시 백그라운드 스레드가 주기 실행해서 결과를 캐시에
  저장. 키가 없으면 건너뛰고 스텁이 그대로 나감. 실패해도 마지막 성공값(last-good) 유지.
  API 요청마다 외부 API를 부르지 않음(하루 한도가 100~1만 회).
- `api.py`의 `@live_merge(이름)`이 스텁 응답 위에 수집 필드를 덮어쓰고 `live_keys`에 덮어쓴
  필드 이름을 넣음 → 앱이 스텁 구간을 "예시 데이터"로 표시(`ListSection(stub: ...)`,
  출처 문구). `GET /status`에서 작업별 live/waiting/stub 확인.
- 소스(`backend/sources/`): `weather`(기상청 단기·중기예보+에어코리아+특일, 서울 고정),
  `market`(농수산식품유통공사 최근일자 소매가, 배추 등 6품목 — **일별 과거값이 비어서 매 실행
  때 조사일·1일 전·1주 전 값을 price_history에 쌓음, 이번 달 점이 서버 켠 날부터 늘어남**),
  `culture`(TourAPI 축제 + 문화정보 전시·공연, 서울), `money`(금융위 코스피·코스닥·금·유가,
  영업일 종가·공공누리 4유형 상업이용금지 주의).
- 아직 스텁: 박스오피스(KOBIS), 환율·기준금리(ECOS), 예·적금(금융상품 한눈에), 음악(Spotify·
  YouTube), 축산물·생필품·전통시장, 제철(편집 데이터), AI 섹션. 전력수급(KPX)은 키 등록 오류
  (resultCode 30) — 승인 반영 지연일 수 있어 다시 시도해볼 것. 축산물품질평가원은 경로 404.
- 서버 배포: 코드는 scp로 올리되 `.env`는 따로(권한 600) — 키 파일을 서버로 보내는 건 사용자
  확인 후에.
- 점검: `python backend/test_jobs.py`(키 없이 돌아감).

**지역 = 시도 17곳으로 통일(2026-10-11)**: 위경도 단위(처음 구현)는 폐기하고 앱 전체가 시도 코드
(행정표준코드 앞 2자리, `backend/geo.py`의 `REGIONS` = 앱 `region.dart`의 `kRegions`)로 동작함.
- 앱: `RegionStore`(region.dart)가 지역을 정함 — 저장된 선택(shared_preferences) → 없으면 위치 권한(허용 시
  좌표를 `/region`에 딱 한 번 보내 시도를 얻고 이후엔 코드만 씀) → 거부/실패면 기본 서울. 화면 맨 위
  "오늘 · 서울 ▾"를 누르면 시도 선택 시트(`showRegionPicker`), 고르면 투데이·생활·문화가 새로 받아옴.
- 백엔드: `/today`·`/weather`·`/culture`·`/market`이 `?sido=11` 같은 코드를 받음(없으면 서울). `/regions`(목록),
  `/region?lat&lon`(좌표→시도, 가까운 측정소 주소 우선 → 못 찾으면 가까운 시도청). 날씨는 시도청 소재지 격자,
  중기예보는 가까운 예보 도시, 미세먼지는 시도 안 측정소 평균(등급), 자외선·꽃가루는 시도 단위 그대로,
  축제는 주소 접두어로 시도 필터, 전시·공연은 한국문화정보원 전국 목록(2시간 캐시, 페이지 numOfrows=100)을
  `area` 필드로 거름, 전통시장은 파일 데이터(`backend/data/traditional_markets.json`, `tools_build_markets.py`로
  CSV에서 생성). 위치별 소스는 job이 아니라 요청 시 계산 + 시도별 TTL 캐시(`sources/_cache.py`).
- **시도 단위로 안 되는 것(알려진 한계)**: 큰 도(경북·강원·전남 등)는 도내 날씨가 시도청 소재지 기준이라 실제와 다를
  수 있음 / 강원 영동·영서, 경남 서부 등 예보 구역이 갈리는 곳 / 기상특보는 지점이 서울(108)뿐이라 서울·인천·경기에서만 /
  생활 시세(aT 소매가)는 전국 평균(API에 지역 구분 없음) / 전통시장은 휴장일·좌표 없음(파일에 없음) /
  판매점별 가격(한국소비자원 참가격)은 매장·상품 목록은 되지만 가격 조회가 어떤 날짜·상품으로도 0건이라 못 붙임.

**시군구 지역 마스터(2026-10-11)**: 지역은 시도 + 선택적 시군구(230곳, `backend/data/regions.json`, 에어코리아 측정소 주소·좌표에서
`tools_build_regions.py`로 생성; 측정소 없는 군은 빠짐). 앱 `region.dart`가 시도→시군구 선택·검색·"시도 전체"를 지원하고
`/today·/weather·/culture·/market`이 `sido`+`sgg`를 받음. 날씨는 시군구 중심 좌표 격자, 미세먼지는 그 시군구 측정소 평균(시도 전체 실시간을
시도별로 25분 캐시), 자외선·꽃가루·특보는 시도 단위(화면 근거 문구에 "시도 단위" 표시), 문화·전통시장은 시군구 우선 + 같은 시도 나머지로 채움.

**생활 탭(2026-10-11)**: 맨 위 "장바구니 지수"(BASKET 8품목 지난주 대비 평균, 지난주=100) + 품목 칩으로 보는 이번 달 추이(`BasketBody`),
아래 "장보기 시세"(`ShoppingCatalog`): aT 최근일자 API 전 품목(채소·과일·수산·축산·곡물)을 카테고리 칩 + 제철만 보기로, 누르면 상세(사진·
제철 12개월·고르는 법·보관법). 제철·고르는 법은 편집 데이터 `backend/data/produce_guide.json`(31품목, 일반 상식·노지 기준 대략),
사진은 위키미디어 공용(CC0/CC BY/CC BY-SA)에서 `tools_build_produce_images.py` + `tools_cache_produce_images.py`로 받아 16:10 JPEG로
`app/assets/produce/`에 넣음(출처·라이선스를 화면에 표시, 라이선스는 `data/produce_images.json`). 가격 이력은 매 실행 때 조사일·1일 전·1주 전
값을 DB에 쌓는 중(KAMIS 키 신청해 둠 → 오면 `AT`처럼 `KAMIS_CERT_KEY/ID`로 과거 일별 이력 채울 것). 포털 aT 일별 API는 전 기간 0건이라 못 씀.
전통시장(`MarketList`): 시설 필터·정렬(시설 많은 순/가나다/시군구)·상세(주소·시설·네이버/카카오 지도 링크, 한국관광공사 키워드 검색으로
사진은 Type1(출처표시) 있을 때만, `/market/detail` + `/proxy/image` 허용 호스트 프록시).

**문화 탭(2026-10-11)**: 맨 위는 "이번 주말 N개 행사"(실데이터일 때, 박스오피스는 KOBIS 키 전까지 예시라 아래로), 그 아래 행사 달력
(`CultureCalendar`: 이번 달·다음 달, 날짜별 점·선택일 목록, 시군구 행사 "우리 동네" 뱃지), 목록, 행사 상세(`/culture/detail`: 문화정보원 detail2
· 관광공사 detailCommon2/Intro2). 전국 행사 목록(관광공사 + 문화정보원 10여 쪽)은 `culture_warm` job이 100분마다 미리 캐시.

**머니 탭**: 예·적금·대출 순위(금감원 금융상품한눈에) 한 줄 = 상품명·금융회사·업권·금리, 누르면 금리표·우대조건·가입 방법·금융상품한눈에 링크(`finance_sheet.dart`).
뒤집는 첫 카드의 시장 지표는 뒷면에만(아래 반복 목록 제거), 앞뒷면 높이는 IndexedStack으로 통일.

**날씨 개편**: 시간대별 오늘 0시~모레 0시 1시간 간격 가로 스크롤(`HourlyStrip`, "지금" 강조·지난 시각은 예보값 흐리게), 주간은 오늘 포함 7일
(기상청이 단기·중기 사이 하루를 안 줘서 그날은 "예보 없음"), 생활지수는 줄마다 근거·출처(빨래/세차·옷차림은 "데일리컷 기준, 공식 아님").

**개발용 표시(2026-10-10)**: 실데이터가 아닌 영역은 앱에서 분홍 배경 + 빨간 왼쪽 선(`StubMark`,
`components.dart`의 `kShowStubMarks`로 한 번에 끔)으로 보임. 판단은 서버 응답의 `live_keys`
(`/today`는 `live_sections`). 소스를 새로 붙이면 이 표시는 자동으로 사라짐.

**API 사용 현황 점검**: 승인된 API 중 뭘 쓰고 안 쓰는지는 아티팩트
claude.ai/artifact/17gytwYuXMFkF4vx8tWv65 (사용 중 · 일부만 · 미사용 · 막힘 · 키 없음)에 적어둠 —
수집기를 추가/수정할 때마다 이 목록도 같이 갱신할 것(사용자가 계속 확인해달라고 함). 미사용 중
쓸 만한 것: 기상특보(특보 있을 때만 표시), 대기정체지수, 소비자원 생필품가격(생필품 자리),
축산물유통정보(계란·돼지, 경로 확인 필요), 전력수급(키 오류 재시도), aT 일별가격(과거 이력).

## 지금 상태 (2026-09-29)

뼈대만 있음 — 백엔드는 전부 스텁 데이터, 실제 공공 API 연동 안 됨. Flutter는
5탭 네비게이션 + 컴포넌트 기반 화면까지 만들어서 로컬에서 실제로 돌려서
확인함(백엔드 stub → 화면 렌더링까지 엔드투엔드 확인 완료).

**시세 섹션 범위 넓힘(2026-09-29 피드백)**: 처음엔 품목 가격 순위만 보여주는
좁은 지표였는데, "장 볼 때 필요한 생활 물가" 전체로 넓힘 — 제철 과일·채소를
캡션 한 줄에서 카드 목록으로 승격, 축산물 시세/생필품 물가지수/우리 동네
전통시장 세 카테고리 추가함(모두 아직 스텁).

**시세 화면 구조 2차 개편(2026-09-29)**: "가격 순위(전주 대비 -18%)보다 지금
뭐가 제철인지가 장보기 결정에 더 도움된다"는 피드백 — SeasonalHero(제철 목록)
를 화면 맨 위로 올리고, 단일 텍스트 대신 ChartCard(배추 14일 가격 추이)로
바꿈. 같은 ChartCard를 머니 탭 환율 카드에도 재사용. `price_trend`는 아직
`_mock_daily_series()`로 만든 결정론적 가짜 데이터 — 실제로는
**price_history 테이블 + 매일 스냅샷 배치**가 있어야 진짜 추이/인사이트가
나옴(사용자가 "쌓아서 인사이트 발견에 활용"하고 싶다고 명시함 — 이건 API
연동보다 먼저 설계해둘 만한 부분).

**기획 문서 "섹션 구성 확정" 반영(2026-09-29)**: 기획 문서에 "시세→생활" 확장이
공식화되며 담을 내용 목록이 크게 늘어남(날씨/미세먼지, "예상 vs 실제" 투표,
공휴일·이번 달 달라지는 것·연휴 병원약국, 김장·차례상 물가 등 — 생활; 도서관
인기대출, 무료 전시, 흥행 속도 비교, 개봉 N주년, 연휴 극장가, 단풍×축제 등 —
문화). 사용자 요청으로 **섹션별로 하나씩, 공통 데이터부터** 구현 중 — 첫
타자로 날씨(WeatherHero: 오늘 기온/체감/최고최저, 옷차림 추천, 주말 전망,
빨래·세차 좋은 날, 미세먼지)를 `/weather` 별도 엔드포인트로 구현함(문화 섹션의
"맑은 곳 축제만" 등 다른 기능도 같은 데이터를 쓸 예정이라 market()에 안 얹음).
**아직 안 만든 생활 항목**: 장보기 레시피, "예상 vs 실제" 투표, 공휴일/이번 달
달라지는 것/연휴 병원약국, 차례상 물가. **문화 섹션은 아직 기획 문서 확장분
반영 전**(박스오피스/공연/축제만 있음).

또한 눈여겨볼 결정: 기획 문서에 **"이슈팝 연결"**이 추가됨 — 이슈팝의 생활
관련 기사를 한 줄 요약+링크로 가져와 데이터 카드 아래 보조 한 칸으로 둠(본문은
안 가져옴). 아직 구현 안 함 — 두 앱 백엔드가 처음으로 서로 통신하게 되는
지점이라, 배포 아키텍처 정할 때 같이 설계해야 함.

**음악(문화 섹션, 2026-09-29 추가)**: "순위 데이터 받을 곳 있나" 질문 — 멜론/
지니/벅스/가온(써클차트) 전부 공식 오픈 API 없음(스크래핑은 이용약관 위반
소지 있어 제외). 공식 API가 있는 **Spotify Web API**(Top 50 - South Korea
플레이리스트)와 **YouTube Data API v3**(mostPopular, videoCategoryId=10)만
근사치로 넣기로 함. Spotify는 국내 점유율이 멜론보다 낮아서 실제 국내 인기
순위와 차이 날 수 있음 — UI 라벨에 "(Spotify 기준)"이라고 명시해서 "국내
공식 차트"로 오해 안 하게 함(`cultureScreen`의 스포티파이 목록 참고).

**구독료 비교 (아이디어, 2026-09-29 메모만)**: 넷플릭스·디즈니+·멜론·유튜브
프리미엄 등 구독료를 한 곳에 모아 비교하면 좋겠다는 아이디어 — 통합 API는
없어서 직접 모아 넣어야 함(기획 문서의 "차례상 물가"처럼 "발표 인용/자체
계산" 카테고리와 같은 성격). 사용자가 대안으로 "LLM한테 각 서비스 요금제
페이지를 읽어와 주기적으로 갱신시키면 어떨까"를 제안함 — 수동 하드코딩보다
나을 수 있는 방향이라 여기 기록만 해둠(아직 스코프/우선순위 미정, 구현 전).
머니 섹션에 "예·적금 금리 순위"와 같은 RankRow 형식으로 들어가면 자연스러울
듯.

**다음 할 일**:
1. 생활 섹션 나머지 항목(장보기 레시피, 투표, 공휴일 등) 계속 구현.
2. 문화 섹션에 기획 문서 확장분(도서관 인기대출, 무료 전시 등) 반영.
3. 공공 API 키 발급 + 상업적 이용/출처 표기 조건 확인 (기획 문서 "확인된 이용
   조건" 항목 참고). Spotify/YouTube는 별도로 개발자 계정·API 키 발급 필요.
4. 각 backend 엔드포인트의 TODO를 실제 API 호출로 교체.
5. price_history 테이블 설계 + 매일 스냅샷 배치(스케줄러) — 그래프/인사이트의
   전제조건.
6. 이슈팝 연결(생활 관련 기사 요약+링크) — 두 앱 간 첫 통신 지점, 아키텍처
   설계 필요.
7. 배포 인프라 결정 (이슈팝처럼 별도 Oracle Cloud 인스턴스 vs 다른 선택).
8. 품목 상세/글 상세 화면 추가 (기획 문서 "다음 할 일" 항목).
9. 구독료 비교 — 스코프/방식(수동 입력 vs LLM 주기적 수집) 정하고 시작할지
   결정.

## 2차 피드백 반영 (2026-10-11)

- **차트**: `TrendChart`는 누르거나 좌우로 끌면 그 날짜 값이 나오고(선택점+세로선), 아래에
  "최고 ○(n일) · 최저 ○(n일)" 요약. `xMax/ticks/xLabel`로 월별 축(물가 13개월)도 가능.
- **머니**: 뒤집는 카드 폐기(실데이터일 때). `money.py`가 `chart_items`
  (코스피·코스닥·금·물가: 값/단위/시계열)를 주고 `metric_chart.dart`의 `MetricBody`가
  칩으로 고름. 물가는 KOSIS 25개월을 받아 최근 13개월의 전년 동월 대비 상승률 계열.
- **생활 차트 기준**: 기본 "장바구니"는 서버 `BASKET` 8품목(많이 사는 대표 품목)의 지난주 대비
  평균. `chart_items`는 이제 전 품목(조사일이 최신보다 10일 넘게 오래된 품목은 제외 — 2010년
  조사값 같은 게 섞여 있었음). 품목 상세 시트의 "내 장바구니에 담기"(`my_basket.dart`,
  shared_preferences)로 칩·지수를 내 품목 기준으로 바꿈(지수는 클라이언트에서 계산).
- **고르는 법·보관법**: 줄글 → 짧은 항목 목록(`produce_guide.json`의 `pick_list`/`storage_list`,
  `tools_guide_lists.py`로 생성, 줄글은 호환용으로 유지).
- **문화**: 범위 토글 `[시군구][시도 전체]`를 히어로와 달력이 함께 씀(`ScopedColumn`). 달력 점 =
  그날 열리는 행사 수(최대 3, 설명 문구 있음), 종류 칩(전체/축제/전시·공연), 날짜 누르면 그 날
  행사만 아래 한 목록으로. 중복이던 "진행 중인 전시·공연"/"곧 열리는 축제" 목록은 실데이터일 때
  제거. 사진은 `ZoomImage`(contain + 누르면 전체화면 확대).
- **전통시장 필터**: "주차장 있음" → "주차장"만.
- **날씨**: 아이콘(`weather_icon.dart`), 생활지수 아이콘 행 + 누르면 근거 시트(`life_index.dart`),
  빨래 기준 완화(비 예보/강수 50%↑ 별로, 30%↑·습도 70%↑·미세먼지 나쁨 보통, 그 외 좋음).
  기상특보는 서울·인천·경기만 제공, 그 외 "제공 안 함".
- **사진 라이선스**: 위키미디어 커먼즈(CC0/PD/CC BY/CC BY-SA)만 사용, 시트에 원본·라이선스 링크와
  "크기 줄이고 일부 잘라 사용" 표기. (법률 자문 아님 — CC BY-SA는 변경 표기 필요.)
- **개인정보(좌표)**: `/region`은 POST 본문으로만 받음(2026-10-11) — GET 쿼리는 nginx 접속 로그에 좌표가 남아서 바꿨고, 기존 로그의 좌표도 지움. 좌표는 DB·로그에 저장 안 함(소수 2자리로 뭉개서 지역만 구함).
- **DB**: SQLite `backend/dailycut.db`(git 제외). 배포본은 서버(`/home/ubuntu/dailycut-backend/`)의
  별도 파일 — 로컬 PC 파일은 개발용 사본이고 서로 동기화 안 됨. 서버 백업: cron 매일 04:30(서버 UTC, 한국 13:30)에 `backup_db.py` → `/home/ubuntu/dailycut-backups/*.db.gz`, 14일 보관(같은 VM 안이라 VM 자체 유실엔 못 막음).
- **TODO**: 전 품목 사진 DB(싱싱해 보이는 사진으로 큐레이션), KAMIS 키 오면 가격 이력 백필,
  머니 확장(DART 공시·청약·실거래가·환율·기준금리 등).

## 3차 피드백 반영 (2026-10-11)

- **품목 가이드 v2** (`backend/data/produce_guide.json`, 생성: `tools_guide_v2.py`): 63개 aT 품목 + 딸기·단감·참외·복숭아·쇠고기·우유(69개).
  항목 구조 = `season, good[], avoid[], storage[], note`(각 항목 `[라벨, 짧은 문구]`). 시트에서 ✓ "이렇게 고르세요"
  / ⚠ "이런 건 피하세요" / 보관법으로 나눠 보여줌. 신규 36품목은 일반 상식 수준의 편집 정보(의학·법적 조언 아님).
- **사진 62장** (`produce_images.json`, 에셋 `app/assets/produce/pNN.jpg`): 위키미디어 커먼즈 검색 → 컨택트 시트로 눈으로 골라
  (`tools_photo_candidates.py` → picks → `tools_build_photos.py`). 못 구한 7품목(참깨·콩·팽이버섯·얼갈이배추·열무·명태·미나리)은
  사진 없이 표시. 화면은 "사진 · 작가" 한 줄 + ⓘ(작가·라이선스 링크·원본·"크기 줄이고 일부 잘라 사용" 안내).
- **개인화(기기 저장)**: 마지막으로 본 머니 지표·기간, 문화 종류 칩(`local_prefs.dart`), 숨길 생활지수(`LifeIndexSection`),
  내 장바구니. 로그인 없음.
- **익명 이용 통계** (`analytics.dart` → `POST /events` → `usage_events`): (날짜, 이벤트, 값)별 횟수만 저장. 사용자·기기 ID·좌표·
  검색어 없음. 허용 이벤트 이름 화이트리스트(`api._USAGE_NAMES`) + 값은 짧은 문자만. 사용자가 끌 수 있음(출처 시트의 스위치).
  리포트는 서버 DB에서 `SELECT name, prop, SUM(n) FROM usage_events GROUP BY 1,2`로 직접 조회. 개인정보처리방침 문구는
  정식 출시 전에 법무 확인 필요.

- **4차 정리 (2026-10-11)**: 가이드에 `tips`(팁) 분류 추가(`tools_guide_tips.py`; note·'팁' 항목을 옮김 — 가이드를 `tools_guide_v2.py`로
  다시 만들면 이 스크립트를 이어서 돌릴 것). 장보기 시세 분류를 채소·과일·수산·곡물·두류·양념으로 재편(`market.py NAME_CATEGORY`:
  수박·멜론→과일, 감자·고구마·버섯→채소, 쌀·콩·땅콩→곡물·두류, 마늘·고추·깨→양념), "제철만/담은 것만"은 분류 알약이 아니라
  체크 필터로 분리. 긴 목록은 앱 공통 `kListLimit=6` + `ShowMoreButton`/`ExpandableList`(맨 처음 화면의 날짜·기간 목록 제외).
  생활지수 설정은 제목 줄 톱니바퀴. 주간 날씨는 18시 발표분이 5일 뒤부터라 하루 비는 문제를 직전 발표분으로 채움(`_mid`).

- **KOBIS 영화 (2026-10-12)**: `sources/boxoffice.py` — 일별·주간·주말 × 전체·한국·외국·독립예술 박스오피스(3시간마다 12번 호출),
  지역별(요청 시 3시간 캐시)·영화 상세(7일 캐시, `/movie/detail?code=`)·최근 개봉(박스오피스에 든 것만; 영화목록 API의 개봉예정은
  성인물이 섞여서 일부러 안 씀). 화면: `widgets/box_office.dart`. 포스터는 KOBIS에 없음 — KMDb(한국영상자료원) 키 신청 후 한국영화만
  붙이는 안, TMDB는 상업 이용 시 별도 계약 필요. 키는 `.env`의 `KOBIS_KEY`(서버 .env에도 추가함).

- **축산물 시세 (2026-10-12)**: `sources/livestock.py` — 축산물품질평가원 `/grade/consumerPriceDaily?standYmd=&judgeKind=4301|4304`
  (소·돼지 부위별 100g당 소비자가격 + 평년 대비). 경로는 공공데이터포털의 API 상세(`POST /tcs/dss/selectApiDetailFunction.do`,
  oprtinSeqNo 53662~53670)에서 찾음 — 월별 `consumerPriceMonth`, 순별 `consumerPriceTenDays`, 연도별 `consumerPriceYear`,
  재고 `grade/LPStock`, 검수확인 `confirm/…`. **계란·닭은 소비자가격이 없음**(검수확인정보뿐). aT 소매가의 축산물은 2017~2022년에서 멈춤.
  소비자원 참가격(생필품)은 상품목록(`getProductInfoSvc.do`)만 되고 가격 조회는 아직 0건.
- **문화 탭 구역 전환**: 지역 줄 아래 `행사·전시 / 영화 / 음악(예시)` 분할 버튼(`SegmentToggle`, `SegmentedHost`, 마지막 선택 기억).

- **정부 지원·혜택 (머니 탭 맨 아래, 2026-10-12)**: `sources/gov_support.py` + `widgets/gov_support.dart`. 행안부 「대한민국 공공서비스(혜택) 정보」
  (data.go.kr/data/15113968, 개발계정 일 10,000건·자동승인) — 엔드포인트 `https://api.odcloud.kr/api/gov24/v3/serviceList`.
  **활용신청 승인됨(2026-10-12)** — 총 10,965건(마감 지난 것 제외 약 10,491건, 응답 ~5.9MB). 한글 필드 이름(`F`)은 실응답으로 확인 완료. 12시간마다 전체를 받아
  DB 캐시(`support_all`)에 저장하고, `/support`는 그걸 메모리(5분)에 두고 거름. 정렬: 우리 시군구 → 시도 → 중앙부처, 같은 단계에선 조회수 순.
  서버 재시작 직후엔 첫 수집이 끝나기 전까지 섹션이 숨겨짐(빈 결과는 메모리에 안 기억함). 지역(시도·시군구)만으로 거르고 개인 조건은 받지 않음.
  같은 승인 때 같이 받은 API(2026-10-12 호출 확인): 청약홈 분양정보(odcloud `getAPTLttotPblancDetail`, OK), 마이홈 공공임대 공고(`rsdtRcritNtcList`, OK),
  복지로 지자체복지(`LcgvWelfarelist`, XML·OK, 4,821건). LH 공고·서민금융 대출상품은 env의 URL로 호출하면 "NO_OPENAPI_SERVICE_ERROR"(경로 확인 필요).
  아직 화면에 붙이지 않음 — 청약 일정/공공주택 공고 섹션 후보.
  비슷한 API: 중앙부처복지서비스(15090532, 100건), 지자체복지서비스(15108347, 1,000건), 온통청년 청년정책(15143273).

- **정부 혜택 "내 조건" 필터 (2026-10-12)**: 행안부 API의 `/supportConditions`(서비스 전체에 연령·성별·소득구간·대상특성이 코드로 붙어 있음)를 같이 받아
  `gov_support.py`가 서비스에 줄여서 붙여 둠(`c`). 코드 뜻은 서비스명 키워드와 대조해서 확정(모듈 docstring 참고; JA04xx 가구유형·사업체 조건은 뜻 미확인이라 안 씀).
  `POST /support/search`(지역+나이·성별·소득 1~5·특성들)가 거르고 "나를 콕 집은 서비스"(좁은 연령대·내 특성 전용)를 위로 올림. 조건은 **본문으로만** 받고 저장·로그 안 함.
  앱은 `widgets/support_profile.dart`(SupportProfile: 기기 로컬 저장, 시트 UI) — 조건은 서버 통계에 보내지 않고, 연령대·성별과 직업·학생 특성(농업인·근로자 등)의 횟수만
  `support_profile`/`support_trait` 이벤트로 셈(소득·장애·질병·보훈은 안 보냄). 실제 자격 심사가 아니라 "가능성 있는 것만 추림"이라고 화면에 밝힘.
- **머니 탭 아래쪽 구역 전환 (2026-10-12)**: 차트·기름값 아래를 `SegmentedHost`로 `금리·대출 / 정부 혜택` 둘로 나눔(마지막 선택 기억, 문화 탭과 같은 방식).
- **첫 로드 개선 (2026-10-12)**: 원인은 ①구글 폰트를 런타임에 통째로(굵기마다 4~6MB) 받던 것 ②새 방문자는 위치 권한 확인(최대 8초)이 끝나야 데이터 요청을 시작하던 것.
  → ①한글 서브셋 폰트(KS X 1001 2,350자, `app/assets/fonts/`, 만든 법 `app/tools/make_fonts.py`)를 앱에 넣고 `google_fonts` 패키지 제거(합계 gzip 약 1.1MB),
  ②`RegionStore.init`이 바로 기본 지역(서울)으로 보여주고 위치는 뒤에서 확인해 바꿈, ③`web/index.html`에 HTML 스플래시(첫 프레임에서 제거).
  서버 nginx: `font/ttf·application/wasm·application/octet-stream` gzip 추가, `assets/assets/fonts/Noto*.ttf`는 30일 immutable 캐시 → **폰트를 바꾸면 파일 이름의 `-rN`을 올릴 것**.
  남은 비용(첫 방문 한 번): canvaskit.wasm(gstatic CDN, 압축 약 2MB)·main.dart.js(gzip 0.85MB). 폰트에 없는 글자(희귀 한자 등)는 폴백 폰트.
  ▾·↻ 같은 기호는 폰트에 없을 수 있어 아이콘으로 그림.

- **광고(카카오 애드핏, 웹) 준비됨 (2026-10-12)**: `widgets/ad_slot.dart`의 `AdSlot` + `web/ad.html`(애드핏 스크립트 페이지, 같은 도메인 iframe).
  광고 단위 ID가 없으면 칸이 아예 안 그려짐. 켜는 법: 애드핏에서 사이트(itssophie.dev/dailycut) 등록·승인 → 광고 단위(320x100 등) 생성 →
  `flutter build web … --dart-define=ADFIT_UNIT=DAN-xxxx --dart-define=ADFIT_SIZE=320x100`. 칸 위치: 생활(장보기 시세 아래)·문화(행사/영화 구역 아래)·머니(금리 아래).
  켜지면 출처 시트에 "광고(애드핏이 기기 정보를 쓸 수 있음)" 안내가 자동으로 붙음. 앱스토어 출시 땐 애드몹으로 `ad_view_stub.dart` 자리를 대체.

## 톤/작업 스타일

이슈팝과 같은 방식 유지 — 감으로 값 정하지 말고 실제로 돌려서 확인, 코드에
"왜 이렇게 했는지" 날짜와 함께 남기기.
