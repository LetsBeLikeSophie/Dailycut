# 서버·배포·성능·운영

> 웹/API 배포 방법, nginx, DB 백업·정리, 첫 로드 최적화, 출시 전 보안·보관 점검. (시간순, 원문 그대로)
> (루트 `CLAUDE.md`에서 2026-10-28에 주제별로 옮김 — 내용은 그대로, 순서만 정리)

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

- **DB**: SQLite `backend/dailycut.db`(git 제외). 배포본은 서버(`/home/ubuntu/dailycut-backend/`)의
  별도 파일 — 로컬 PC 파일은 개발용 사본이고 서로 동기화 안 됨. 서버 백업: cron 매일 04:30(서버 UTC, 한국 13:30)에 `backup_db.py` → `/home/ubuntu/dailycut-backups/*.db.gz`, 14일 보관(같은 VM 안이라 VM 자체 유실엔 못 막음).
- **첫 로드 개선 (2026-10-12)**: 원인은 ①구글 폰트를 런타임에 통째로(굵기마다 4~6MB) 받던 것 ②새 방문자는 위치 권한 확인(최대 8초)이 끝나야 데이터 요청을 시작하던 것.
  → ①한글 서브셋 폰트(KS X 1001 2,350자, `app/assets/fonts/`, 만든 법 `app/tools/make_fonts.py`)를 앱에 넣고 `google_fonts` 패키지 제거(합계 gzip 약 1.1MB),
  ②`RegionStore.init`이 바로 기본 지역(서울)으로 보여주고 위치는 뒤에서 확인해 바꿈, ③`web/index.html`에 HTML 스플래시(첫 프레임에서 제거).
  서버 nginx: `font/ttf·application/wasm·application/octet-stream` gzip 추가, `assets/assets/fonts/Noto*.ttf`는 30일 immutable 캐시 → **폰트를 바꾸면 파일 이름의 `-rN`을 올릴 것**.
  남은 비용(첫 방문 한 번): canvaskit.wasm(gstatic CDN, 압축 약 2MB)·main.dart.js(gzip 0.85MB). 폰트에 없는 글자(희귀 한자 등)는 폴백 폰트.
  ▾·↻ 같은 기호는 폰트에 없을 수 있어 아이콘으로 그림.

- **첫 화면 지연 수정 (2026-10-14)**: 라이브 `/today`가 19.6초 걸린 적이 있음 — 날씨 캐시(25분)가 만료된 직후 처음 온 방문자가 기상청·에어코리아 호출이 끝날 때까지(콜드 약 20~37초) 기다렸음.
  `sources/_cache.py`의 `cached()`가 이제 stale-while-revalidate: 만료 후 3시간 안이면 옛 값을 바로 주고 새 값은 뒤 스레드에서 받음(락으로 한 번만), 3시간 넘게 지났거나 값이 없으면 예전처럼 기다림.
  기본 지역(서울)은 `weather_warm` 작업(30분마다)이 미리 데워 둠. 처음 부르는 다른 지역의 날씨는 여전히 첫 요청이 수 초~수십 초 걸림(알려진 한계).
- **첫 로드 2차 점검 (2026-10-15, 브라우저 리소스 타이밍으로 측정)**: 첫 방문(캐시 없음) 순서 — 0.3s HTML → 0.5~2.3s main.dart.js(gzip 827KB) → 2.7s 엔진이 뜨고 FontManifest 요청 → 2.8~5.0s 글꼴 4개(세리프 700이 586KB라 가장 늦음)
  → 5.25s에야 API 요청 시작 → 5.6s 첫 화면. 즉 병목은 서버가 아니라 **글꼴이 엔진 부팅 뒤에 직렬로 시작**하는 것. 조치: ①`index.html`에 글꼴 4개 `<link rel="preload" as="font" crossorigin>`(번들과 동시에 받음; 글꼴 파일명 `-rN`을 올리면 여기도 고칠 것)
  ②nginx `listen 443 ssl http2`(원래 HTTP/1.1이라 동시 6연결 제한; 백업 `sites-available/itssophie.dev.bak-*`). 캐시된 재방문은 API 요청이 0.9s에 시작(전엔 5.25s).
  측정 스크립트: 브라우저 콘솔에서 `performance.getEntriesByType('resource')`. **남은 개선 후보**: ①`IndexedStack`이 5개 탭을 시작과 동시에 만들어서 `/market`(130KB)·`/culture`가 투데이 요청과 같이 나감(1코어 서버라 투데이가 0.2→0.5s로 밀림) → 탭을 처음 열 때 만들고 투데이가 뜬 뒤 뒤에서 미리 만들기
  ②투데이가 `today()`+`weather()` 둘 다 기다림 → 날씨 히어로를 먼저 그리고 "오늘의 섹션"은 따로 ③스플래시에 날씨 한 줄 먼저 띄우기(index.html에서 바로 `/weather` 호출) ④서울이 아닌 지역은 날씨 첫 요청이 콜드(수 초~수십 초).
- **첫 로드 3차: 먼저 띄우기 3종 (2026-10-15, 위 "남은 개선 후보" ①②③ 처리)**: ①탭 지연 생성 — `main.dart`가 투데이만 먼저 만들고, 투데이가 그려지면(`boot.dart`의 `kFirstScreenReady`) 나머지 탭을 0.7초 간격으로 뒤에서 차례로 만들며, 탭을 먼저 누르면 그 탭은 바로 만듦(`_visited`).
  ②투데이 분리 — `/weather` 응답이 `headline`까지 줘서(`api.py weather_route`, 안쪽 `weather()`는 그대로) 날씨 히어로·주간·생활지수는 이것만으로 그려지고, "오늘의 섹션"은 `/today`를 따로 받아 오면 보임(느리거나 실패하면 그 구역만 빔).
  ③스플래시 날씨 — `index.html`이 앱 부팅과 별개로 `/dailycut-api/weather`를 바로 불러(배포 경로 `/dailycut/`에서만, 저장된 지역 `flutter.region_code/region_sgg` 사용, 8초 지나면 포기) 로고 아래에 "14° 맑음 · 낮 최고/최저 · 옷차림"을 먼저 보임.
  라이브 측정(캐시 있음): 날씨 한 줄 약 1.0초, 앱 본체의 날씨 요청 3.0초(번들 새로 받음), 이어서 market 5.2s·culture 6.5s·혜택 8.7s로 차례로 뒤에서 받음. 서버 반영 순서 주의: `/weather` headline이 먼저 배포돼 있어야 새 앱이 제목을 못 받는 일이 없음.
- **전체 최적화: 두 번·세 번 하던 일 정리 (2026-10-16)**
  ①**저장값 두 번 그리기 제거**: `main()`이 `LocalPrefs.init()`으로 설정을 먼저 읽고 `MyBasket.loadSync()`·`SupportProfile.loadSync()`를 부른 뒤 `runApp` — 지역(`RegionStore`)·내 장바구니·마지막 구역(`SegmentedHost`)·숨긴 생활지수·달력 종류 칩·통계 스위치·내 조건이 **첫 프레임부터 저장값**으로 시작.
  예전엔 기본값으로 한 번 그리고(요청까지 보내고) 저장값으로 다시 그려서, 정부 지원이 조건 없이 한 번·조건으로 또 한 번 요청하고, 구역 전환이 첫 구역 요청을 먼저 보내고, 장바구니 히어로가 "대표 → 내 것"으로 깜빡였음. 새 저장값을 화면에서 읽을 땐 `LocalPrefs.stringSync/listSync`를 쓸 것(비동기로 읽어 `setState`하지 말 것).
  ②**요청 기억을 한 곳으로**: 화면마다 따로 있던 TTL 메모 6개(장소·혜택·정부 지원·한산한 곳·장바구니 카드·날씨 문장)를 `ApiClient._memoGet`으로 합침(같은 조건은 ttl 동안 재요청 없음, 받는 중인 요청도 공유, 실패는 기억 안 함). 그 덕에 투데이와 나들이 날씨 문장이 `/weather`를, 생활과 투데이 장바구니가 `/market`을 **한 번만** 받음.
  ③**스플래시가 받은 날씨를 앱이 재사용**: `index.html`이 `window.__dcEarly = {key:'시도|시군구', p: Promise<본문>}`을 만들고 `splash_web.dart takeEarlyWeather`가 같은 지역이면 첫 `weather()`에 한 번 꺼내 씀 → 시작할 때 `/weather`가 2번 → 1번(라이브 확인: 시작 요청은 weather·today 둘).
  ④작은 것들: 투데이의 스플래시 걷기·준비 신호는 한 번만(`kFirstScreenReady` 확인), `keepAllWrap`은 같은 글·폭이면 다시 재지 않음(`_wrapMemo`), `SegmentToggle`의 후처리 예약은 처음 한 번.
  ⑤**서버**: `store.load_cache(name, shared=True)`가 파싱한 JSON을 기억(저장 시각이 같으면 재사용, 최대 8개 LRU)하고 `_cache.cached(..., shared=True)`로 큰 읽기 전용 캐시(캠핑 3,000곳·도서관·반려동물·웰니스·한산한 곳)에 적용 — 따뜻한 상태에서 캠핑 145→26ms, 한산한 곳 28→11ms, 응답은 같음.
  **`shared=True`로 받은 값은 읽기만 할 것**(여러 요청이 같은 객체를 씀). 측정: 서버 응답은 대부분 35ms 이하라 병목은 서버가 아니라 앱의 중복 요청·재렌더였음.
- **출시 전 점검 후 정리 5종 (2026-10-19, APK 1.3.4)** — 전체 점검(성능·데이터 보관·권한·법·구조)에서 나온 고칠 것 중 1~5를 처리:
  ①**개인정보처리방침**(`app/web/privacy.html`, 시행일 10-19): 위젯(저장된 지역·품목을 읽어 약 30분마다 백그라운드로 서버에 요청, 본문으로만 보내고 저장 안 함, GPS 안 읽음), 앱 권한 표(위치 선택·인터넷/네트워크 상태·광고 ID), 국외 이전·처리 표(구글 LLC 미국: 광고 식별자·IP·기기 정보 / Oracle 일본: 접속 기록 14일), 자동 백업 미사용을 추가. **법률 자문 아님 — 위치정보법상 위치기반서비스 신고 필요 여부는 별도 확인 필요(좌표는 저장 안 함).** 동작을 바꾸면 방침도 같이 고칠 것.
  ②**자동 백업 끔**(`android:allowBackup="false"`): 기기에 저장한 생년월일·내 조건·장바구니가 구글 드라이브로 복사돼 "기기에만 저장" 문구와 어긋나던 것. 폰을 바꾸면 이 값은 안 옮겨짐(의도).
  ③**포그라운드 서비스 권한·서비스 제거**(매니페스트 `tools:node="remove"`: `FOREGROUND_SERVICE`, `androidx.work…SystemForegroundService`): 위젯용 WorkManager가 끌고 온 것인데 안 쓰고, 남기면 플레이 콘솔이 포그라운드 서비스 선언을 요구할 수 있음. 제거 뒤에도 `WidgetSyncWorker` 성공 확인. 남은 권한: INTERNET·ACCESS_COARSE_LOCATION·ACCESS_NETWORK_STATE·WAKE_LOCK + 애드몹 쪽(AD_ID·ACCESS_ADSERVICES_*).
  ④**데이터 보관 기준과 정리 작업**(`sources/maintenance.py` → `store.prune`, 하루 한 번, 단위 점검 `python backend/test_prune.py`): 요청 때 계산한 캐시(이름에 ':' 또는 '/')는 7일 안 갱신되면 삭제(날짜가 키인 `culture:kcisa:YYYYMMDD`가 하루 600KB씩 쌓이던 것 — 1년 약 220MB), 작업 이름과 같은 칸(last-good)은 유지, 익명 통계 24개월, **가격 이력은 계속 보관**(인사이트용 자산)하되 400일 넘게 기록이 끊긴 품목(2010년 조사값 등)만 삭제, 삭제가 있으면 VACUUM.
  적용 결과: DB 44→32MB, 캐시 228→197행, 가격 이력 죽은 품목 15행 삭제. 나머지 보관: nginx 접속 로그 14일(logrotate), DB 백업 14일(같은 서버 안이라 서버 자체 유실엔 못 막음 → 다른 곳 보관은 TODO).
  ⑤**nginx 요청 제한·보안 헤더**(`/etc/nginx/sites-available/itssophie.dev`, 백업 `.bak-20261019004916`): `/dailycut-api/`에 IP당 초당 20회·순간 60회(`limit_req zone=dc_api`, 초과 시 429 — 400회 동시 요청 시험에서 288회 차단되고 잠깐 쉬면 풀림), `/dailycut/`에 HSTS(180일, 호스트 전체에 적용되지만 모든 프로젝트가 HTTPS 전용)·nosniff·Referrer-Policy·X-Frame-Options·Permissions-Policy(geolocation=self). CSP는 CanvasKit(wasm)·구글 CDN 때문에 일부러 안 넣음. 같은 서버의 다른 프로젝트(포트폴리오·Cortex 등)엔 안 걸리게 데일리컷 구간에만 적용.
  **아직 남은 것(점검 보고)**: 실제 애드몹 ID 교체(지금 테스트 ID)·EEA 배포 시 UMP·"정부와 무관" 문구, 소스별 최대 허용 나이(갱신이 오래 실패해도 옛 값을 계속 보여 줌), `components.dart` 1,752줄 분리·상세 시트 틀 통일(SheetFrame 미사용 4종)·하드코딩 색 21곳·핵심 계산 테스트(현재 5개), AAB 서명 키스토어, `--obfuscate --split-debug-info`, DB 백업 외부 보관.

- **로딩 뼈대 (2026-11-03)**: 웹 스플래시가 걷힌 뒤(또는 앱에는 스플래시가 없어서) 탭 내용을 받는 동안 흰 화면에 큰 로딩 원만 돌던 것을 `ScreenSkeleton`(`widgets/components/notes.dart`)으로 바꿈 — 맨 위 큰 도형·날짜·지역 줄은 바로 그리고 내용 자리에 옅은 줄이 깜빡임. 투데이·`SectionScreen`(생활·문화·나들이·혜택)·지역 준비 전(`main.dart _regional`)에 적용. 다른 탭을 뒤에서 미리 만드는 간격도 0.7초 → 0.45초. 웹 스플래시는 투데이 날씨가 오면 걷는 기존 방식 그대로(20초 지나면 어쨌든 걷음). 가짜로 느린 API(25초 지연)를 붙여 뼈대가 뜨는 것을 확인.


## 전체 점검: 정리 안 된 것·남은 것 (2026-11-08)
앱 코드·저장소·서버를 읽어서(앱 코드와 저장소는 하위 점검 두 개 + 직접 확인, 서버는 SSH로 읽기만) 확인된 것만 적음.

**고친 것(앱 1.3.10부터, 웹은 11/8 배포)**
- `CurvedAnimation`을 build 안에서 매번 만들어 리스너가 쌓이던 3곳(TrendChart·_Blob·ScreenSkeleton) → State에서 한 번만 만들고 dispose.
- `ApiClient._memo`가 실패 때만 지워져 지역·검색을 바꿀수록 쌓이던 것 → 150개 넘으면 오래된 것부터 지움(`_evict`). `WeekendWeatherLine._done`도 12개로 제한.
- 통계를 "눌러서 다시 시도"해도 가게 찾기의 동네 고르기가 안 돌아오던 것(`StoreFinder`가 처음 future만 읽음) → `didUpdateWidget`.
- `sources_open` 통계가 나들이 ⓘ에서 두 번 세지던 것, 지역 시트에서 위치 찾는 동안 시트를 닫으면 엉뚱한 화면이 닫히던 것(`context.mounted`).
- 안 쓰는 `cupertino_icons` 패키지(글꼴 250KB), 죽은 코드(`livestockLine`·`placeKindLabel`·`AppColors.sectionDivider`·`LocalPrefs.getList`) 삭제.
- 서버: 지역화폐 통계 미리 데우기(`docs/data-sources.md` 맨 아래).
- 저장소: `.env.example`에 빠진 주소 11개 추가·뺀 소스(FSC·KOBIS 등) 줄 제거, CLAUDE.md 낡은 숫자(사진 68장·tools 10+2·web/sources.html·현재 상태) 정정, `.gitignore`에 `*.apk`·`*.aab`.

**확인했지만 일부러 안 건드린 것(사용자 결정 필요 또는 위험)**
- `LicenseFlag`(`?license=1` 점검 표시)는 쓰는 곳이 없지만 `docs/licensing.md`가 "위젯만 남겨 둠"이라고 한 것이라 둠.
- `backend/sources/{money,finance,boxoffice}.py`(693줄): 어디서도 import 안 돼 돌지 않음(licensing.md와 일치). 그러나 `.env`에 값이 남아 있어 import 한 줄이면 되살아남 → 지울지 사용자 결정. 서버 DB `cache`에도 10/13의 `finance`·`boxoffice`·`money` 행이 남아 있음(화면엔 안 나감, 백업에도 들어감).
- **고침(2026-11-08, 앱 1.3.10부터)**: `AdSlot`의 "다른 탭이 앞이면 광고 숨김" 검사가 `TickerMode`에 기대는데 `IndexedStack`은 TickerMode를 끄지 않아(SDK 3.47.1 소스) 늘 "앞에 있음"으로 나왔음 → `Visibility.of(context)`로 교체. 같은 이유로 안 보이는 탭의 애니메이션도 계속 돌던 것을 `RootShell`에서 탭마다 `TickerMode(enabled: 앞에 있는 탭만)`로 멈춤. `test/visibility_test.dart`가 두 동작을 지킴(폰에서 직접 보지는 못했고, 플러터 위젯 테스트로 확인).
- 서버: 옛 `api.py.bak-*` 4개, nginx `itssophie.dev.bak-*` 8개, systemd 로그 453MB, 메모리 954MB에 스왑 1.8GB 사용(이슈팝과 같이 씀).
- 낮은 우선: `localCurrency` 폴링을 취소 못 함(최대 160초), `MyBasketToday`·`_SavedRegionLine`이 지역을 바꿔도 다시 안 받음, 안 쓰는 `FlipCard`·`ListLine.nameIcon`·`TrendChart` 옵션들, `/ai`·`/culture`의 `spotify_top`·`youtube_trending`·`/market`의 `essentials` 스텁, 쓰이지 않는 통계 이름 3개, 문서·도구 안 `tools_*.py` 옛 이름, `viewport-test.html`(디버그 페이지가 웹에 배포됨), 안 쓰는 `ic_launcher.png`, macos/linux/windows 폴더.
