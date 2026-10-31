# 데일리컷 — 프로젝트 컨텍스트 (Claude Code용)

> 2026-10-28 정리: 예전에 한 파일에 쌓이던 기록(536줄)은 `docs/` 주제별 파일로 옮겼음(내용 그대로). 이 파일은 **매 세션 읽히므로 요약만** 두고, 자세한 건 아래 "문서 지도"의 파일을 열어 볼 것.

## 이게 뭔지

**데일리컷** — 공공데이터(날씨·시세·행사·나들이·정부 혜택)를 매일 모아 보여 주는 생활 큐레이션 앱. 직접 쓴 글이 아니라 공공 API를 받아 보여 줌. 이슈팝에서 나온 아이디어지만 코드는 재사용 안 한 별도 앱.
Flutter(웹 + 안드로이드) + FastAPI(SQLite). 이름은 "데일리컷"으로 확정(2026-09-29, 기획 문서에 남은 "moum"은 무시).
- 기획 문서: https://claude.ai/artifact/U8h2Ukqj5FfBkLaPGVgtBZ · 디자인 캔버스: https://claude.ai/artifact/3oFPf9sqBPZKhk5J43bvz5
- 사이트 https://itssophie.dev/dailycut/ · API https://itssophie.dev/dailycut-api/ · 저장소 `github.com/LetsBeLikeSophie/Dailycut`(SSH, `master`)
- **현재(2026-10-28)**: 실데이터 연동 끝, 웹 배포 중, 안드로이드는 **Play 비공개 테스트 단계**(1.3.5 승인·게시 10/27, 1.3.6 번들 준비). 상세는 "출시 상태" 절.

## 폴더 지도

```
app/            Flutter 앱(웹+안드로이드+iOS)
  lib/            main·boot·region·api_client·analytics … / screens/(탭 화면) / widgets/(공용 부품·기능별 위젯)
    widgets/components.dart = 공용 부품의 **목차(export만)**, 실제 코드는 widgets/components/ 8개 파일
      (basics 서식·색 / text 형광펜·큰 숫자 / hero 화면 맨 위 / charts 차트 / lists 목록 / controls 선택·버튼 / sheets ⓘ·시트 / notes 로딩·라이선스 표시)
  assets/         fonts(한글 서브셋)·icon(원본)·produce(농산물 사진 62장)·shapes(탭 도형)
  android/        매니페스트·위젯(Kotlin)·서명 설정(key.properties는 git 밖)
  web/            index.html·about/privacy/download.html·아이콘(생성물)
  tools/          build_release.sh(스토어 번들)·make_fonts.py(글꼴 서브셋)
  test/           단위·골든 테스트
backend/        FastAPI
  api.py          라우트 / jobs.py·store.py·config.py·geo.py
  sources/        소스별 수집기(weather·market·culture·places·benefits·gov_support·livestock·outing …)
  tools/          일회성 데이터 생성 스크립트 9+1개(build_*·guide_*·photo_candidates·build_nutrition)
  data/           편집·생성 데이터(regions·produce_guide·nutrition·traditional_markets …)
store/          Play 등록 자료(listing-ko.md = 설명 원본, 아이콘·대표 이미지·스크린샷). *.aab는 git 제외 — store/README.md
docs/           주제별 상세 기록(아래 문서 지도)
dist/           (git 제외) 테스트 APK 보관
scratch_fonts/  (git 제외) 글꼴 서브셋을 만들 때 쓰는 원본 variable 폰트
.claude/        launch.json (dailycut-web은 실행 위치가 app/가 아니면 "No pubspec.yaml"로 실패 — 필요하면 app/에서 `flutter run -d chrome --web-port 8620`)
```

## 자주 쓰는 명령 (Windows Git Bash, 작업 위치 주의)

| 하는 일 | 명령 |
|---|---|
| 백엔드 실행 | `cd backend && uvicorn api:app --reload --port 8010` (키 없이도 돎, 키는 `backend/.env` — git 밖) |
| 백엔드 점검 | `python backend/test_jobs.py` · `python backend/test_prune.py` |
| 앱 점검 | `cd app && flutter analyze && flutter test` |
| 웹 빌드 | `cd app && MSYS_NO_PATHCONV=1 flutter build web --release --base-href /dailycut/ --dart-define=API_BASE_URL=https://itssophie.dev/dailycut-api` (`MSYS_NO_PATHCONV=1` 필수) |
| 웹 배포 | `tar czf - -C build/web . \| ssh -i <키> ubuntu@168.110.25.49 "sudo tar xzf - -C /var/www/dailycut-app/"` (덮어쓰기라 `dailycut.apk`는 유지) |
| 백엔드 배포 | 바뀐 파일을 `scp`로 `/home/ubuntu/dailycut-backend/`에 올리고 `sudo systemctl restart dailycut-api`. **`.env`는 사용자 확인 후에만** |
| 테스트 APK | `flutter build apk --release --dart-define=API_BASE_URL=… --dart-define=ADMOB_BANNER_ID=ca-app-pub-3940256099942544/6300978111` → `dist/` → 서버 `/var/www/dailycut-app/dailycut.apk`, 그리고 **`app/web/download.html`의 버전·크기·SHA-256을 먼저 고친 뒤 웹 빌드** |
| 스토어 번들 | `bash app/tools/build_release.sh appbundle test` (비공개 테스트용, 광고 단위만 구글 테스트 ID) / `… appbundle`(프로덕션, 실제 ID). 버전 코드는 올릴 때마다 `pubspec.yaml`의 `+N`을 올릴 것 |
| 아이콘 | `app/assets/icon/*`를 바꾸면 **반드시** `cd app && dart run flutter_launcher_icons` (안 돌려서 옛 아이콘이 나간 적 있음) |
| 글꼴 | `app/tools/make_fonts.py`(원본은 `scratch_fonts/`), 파일 이름의 `-rN`을 올리고 `index.html` preload도 같이 |

SSH 키·서버 정보는 사용자 전역 CLAUDE.md에 있음. 서버·nginx·DB 백업·성능 상세는 `docs/ops-server.md`.

## 꼭 지킬 것

**디자인**(`docs/design-rules.md`): 상자 없이 여백·가는 선 / 큰 도형은 화면 맨 위 하나 / 섹션 색은 도형·형광펜·차트 끝점에만 / 세리프는 한 문장 제목과 큰 숫자에만 / 목록은 `ListLine`·`RankRow` / 글자 크기 **11·13·16·24·60**만.
UI 약속: 여러 개 중 고르기 = `PillChip`, 하나 켜고 끄기 = `CheckToggle`(Material Switch 금지), 부가 설명은 ⓘ(`InfoIconButton`·`SheetFrame.infoLines`), 상세 시트 틀은 `SheetFrame`, 새 가로 제스처는 `SwipeDetector`.
저장값은 `LocalPrefs.stringSync/listSync`로 첫 프레임부터(비동기 읽고 setState 금지), 같은 요청은 `ApiClient._memoGet`으로 합침.

**데이터·법**(`docs/licensing.md`, `docs/data-sources.md`):
- 광고(상업 이용) 때문에 **뺀 소스는 허락 없이 되살리지 말 것**: 금융위 지수·상품, 금감원 금융상품, KOBIS, 문화포털 사진. 사진은 위키미디어 CC·관광공사 Type1만.
- 에어코리아(3유형)는 **가공 금지** — 측정소 한 곳의 원값·등급을 그대로.
- 위치 좌표는 저장·로그 금지(`/region`은 POST 본문). 통계는 익명 카운터만, 서버에 개인·기기 ID 안 둠. 생년월일·"내 조건"은 기기에만.
- **새 공공데이터 소스를 붙이면 세 곳을 같이 고칠 것**: ①`store/listing-ko.md`(+Play Console 설명) ②앱 출처 시트 `widgets/sources_info.dart`(`kAllSources`, 공식 사이트 주소 포함) ③`app/web/about.html`. (플레이가 "설명에 모든 출처를 나열하라"며 세 번 거부함)
- 지역 규칙: 나들이는 시군구에 없으면 상위 지역으로 채우지 않음, 혜택 청약·공공임대는 시도 전체로 채움. UTC 서버라 날짜는 `sources/_kst.py`.

## 출시 상태 (Play) — 상세는 `docs/play-console.md`·`docs/android-release.md`

- 패키지 `com.dailycut.dailycut`, 배포 국가 **대한민국만**, 개인 계정 → 프로덕션 신청 전 **테스터 12명 이상이 14일 참여**(참여한 날부터 셈). 비공개 트랙 "Alpha", 테스터 이메일 목록 44명 + 의견 채널 dailycut@itssophie.dev.
- **1.3.5(코드 13)**: 실제 애드몹 ID, 10/27 승인·게시. 1.3.6·1.3.7 번들은 테스트 광고 ID — 업로드는 사용자가 직접(크롬 확장은 10MB·파일 선택창 제한으로 번들 첨부 불가).
- **1.3.6(코드 14)은 승인·게시됨**(사용자 확인 2026-10-31). **1.3.7(코드 15)**: 아침 날씨 알림(로컬 알림, FCM 아님)·저장한 지역 3곳(`docs/android-release.md`). 테스트 광고 ID 번들 `store/dailycut-release-1.3.7.aab`(59.3MB)와 테스트 APK(링크 `dailycut.apk`, SHA `b95be482…286ca9`)·웹은 2026-10-31에 만들어 배포함. **번들 업로드는 사용자가 직접** → 승인 뒤 테스터 링크 전달. 프로덕션 번들 코드는 **16 이상**.
- **순서**: 1.3.7 업로드·승인 → **그 뒤에** 테스터에게 참여 링크 전달(승인 전에 보내면 실제 광고가 깔림) → 14일 → 프로덕션 신청(번들은 `real`, 코드 16 이상).
- 정책: "혼동을 야기하는 주장"으로 **세 번 거부 후 통과**(정부 정보 출처 링크 누락 → 출처 불충분 ×2). 정부 앱 선언은 "아니요"가 맞음. 설명문 원본은 `store/listing-ko.md`.
- 제출("검토를 위해 변경사항 제출")·번들 업로드·테스터 링크 전달은 **사용자가 직접**. 제 쪽은 입력·저장·확인까지.
- 광고는 **앱에서만 애드몹**(웹 없음). 실제 광고 ID로 빌드한 걸 나눠 주지 말 것(테스트하다 누르면 무효 클릭 → 계정 제한).

## 다음 할 일 (우선순위 순)

1. 1.3.7 업로드·승인 → 테스터 링크 전달(안내문에 "광고는 누르지 마세요"·"14일 참여 유지") → 12명 참여 확인.
2. 프로덕션용 번들(`real`, 코드 16 이상) → 프로덕션 신청. 애드몹 결제·세금 정보, 앱 게시 후 애드몹↔Play 연결, `app-ads.txt`는 이미 올림.
3. **콘텐츠 보강(2026-10-31 사용자 요청)**: 전월세 시세(혜택 탭)·박물관·미술관·문예회관·문화센터(나들이 칩 2개)를 만들어 서버·웹 배포 완료(앱은 1.3.8부터, Play 설명에 "전월세 시세·박물관·미술관·문예회관 + 국토부 실거래가·문화정보원 출처" 추가 필요 — `store/listing-ko.md`엔 반영). 남은 것: 지역화폐 장보기(조폐공사 가맹점 API 주소·키 미확인)·캠핑 "가기 좋은 날" 점수(없음, 캠핑 목록만 있음). 기상특보는 서울 지점뿐이라 제외. 자세히 `docs/data-sources.md` 맨 아래.
4. 건강 공공데이터 추가 검토(`docs/todo-ideas.md`) — 현재 거부 이력을 넘긴 뒤. "건강 앱" 선언·출처 나열 부담이 커짐에 주의.
5. 코드 정리: 하드코딩 색, 핵심 계산 테스트 보강, 상세 시트 틀(`SheetFrame`) 통일(`docs/ops-server.md` 점검 보고). (`components.dart` 분리는 2026-10-29에 끝남)
6. DB 백업 외부 보관, 소스별 최대 허용 나이(갱신이 오래 실패해도 옛 값을 보여 줌).
7. **공공데이터포털 API 활용신청은 2년마다 갱신**(사용자 말, 2026-10-31): 승인이 2026-09~10-13이라 **가장 이른 만료는 2028-09 전후**(정확한 날짜는 포털 마이페이지 "활용기간"에서 확인). **2028-07 이후 세션이면 먼저 사용자에게 알릴 것.**

## 작업 방식

- 감으로 정하지 말고 **실제로 돌려서 확인**하고, 코드에는 "왜 이렇게 했는지"를 날짜와 함께 남김. 큰 변화는 `docs/`의 해당 파일 맨 아래에 날짜와 함께 한 덩어리로 추가(이 파일엔 요약만).
- 사용자 계정(Play Console·서버)에 닿는 일은 하기 전에 알리고, 되돌리기 어려운 건 확인받기. 제 쪽에서 연 크롬 탭은 끝나면 닫고, 사용자가 다른 탭을 보고 있으면 백그라운드라 화면이 안 그려질 수 있음.
- 커밋 메시지 끝에 `Co-Authored-By` 줄, 푸시는 요청받았을 때(지금은 "다 해도 좋다"는 허락이 있었음 — 그래도 큰 변경은 알리고).

## 문서 지도 (`docs/`)

| 파일 | 내용 | 언제 열어 보나 |
|---|---|---|
| `design-rules.md` | 디자인 6규칙, 톤앤매너, ⓘ·스와이프·토글 | 새 화면·부품을 만들 때 |
| `data-sources.md` | 수집 구조, 소스별 메모, 지역 규칙, 탭별 데이터 | 데이터·API 작업, 한계 확인 |
| `features-log.md` | 탭별 기능 변천(시간순) | "이거 왜 이렇게 돼 있지?" |
| `licensing.md` | 이용허락 점검, 제거한 데이터, 사진 라이선스 | 소스를 붙이거나 되살릴 때, 광고 관련 |
| `android-release.md` | APK/AAB, 서명, 애드몹 ID, 위젯, 위치 흐름, 아이콘 | 빌드·위젯·광고 작업 |
| `play-console.md` | 등록 절차, 거부 3회 이력과 대응, 자동화 한계 | 스토어·심사 작업 |
| `ops-server.md` | 배포, nginx, DB·백업·정리, 성능 측정, 출시 전 점검 | 서버·성능 |
| `todo-ideas.md` | 나중에 할 일·아이디어 | 다음 작업 고를 때 |
| `archive-early.md` | 초기 개요·메모(일부 낡음) | 역사가 궁금할 때만 |
