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
    (SectionHeader, HeroCard, StatTile, RankRow, SeasonalHero, ChartCard).
    화면은 이 조합으로만 만듦. ChartCard의 라인 차트는 새 패키지 없이
    CustomPainter로 직접 그림. HeroCard/ChartCard는 `showHeader: false`로
    SectionScreen 안에서 쓸 때 섹션 헤더 중복을 끔(투데이에서만 true 유지).
  - `lib/screens/` — 투데이/시세/문화/머니/AI 다섯 화면.
  - `lib/api_client.dart` — 백엔드 클라이언트. 기본 `http://127.0.0.1:8010`,
    `--dart-define=API_BASE_URL=...`로 오버라이드(이슈팝과 같은 패턴).

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

**다음 할 일**:
1. 공공 API 키 발급 + 상업적 이용/출처 표기 조건 확인 (기획 문서 "확인된 이용
   조건" 항목 참고).
2. 각 backend 엔드포인트의 TODO를 실제 API 호출로 교체.
3. price_history 테이블 설계 + 매일 스냅샷 배치(스케줄러) — 그래프/인사이트의
   전제조건.
4. 배포 인프라 결정 (이슈팝처럼 별도 Oracle Cloud 인스턴스 vs 다른 선택).
5. 품목 상세/글 상세 화면 추가 (기획 문서 "다음 할 일" 항목).

## 톤/작업 스타일

이슈팝과 같은 방식 유지 — 감으로 값 정하지 말고 실제로 돌려서 확인, 코드에
"왜 이렇게 했는지" 날짜와 함께 남기기.
