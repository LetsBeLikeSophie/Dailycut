#!/usr/bin/env bash
# 출시용 빌드(실제 애드몹 ID) — 사용법: bash tools/build_release.sh [appbundle|apk]   (기본: appbundle)
# 2026-10-19: 앱 ID·광고 단위 ID는 비밀 키가 아니라 앱에 그대로 들어가는 공개 값이라 저장소에 둠.
# ※ 테스트로 나눠 주는 APK(dist/·download.html)에는 이 스크립트를 쓰지 말 것 — 실제 광고가 나와서 테스트하다 누르면 무효 트래픽으로 계정이 정지될 수 있음.
#   내 폰에서 실제 ID로 확인할 땐 테스트 기기를 등록하고(--dart-define=ADMOB_TEST_DEVICES=기기ID) 광고를 누르지 말 것.
# 앱 ID는 환경변수(ORG_GRADLE_PROJECT_ADMOB_APP_ID → build.gradle.kts의 manifestPlaceholders), 광고 단위 ID는 --dart-define으로 들어감.
set -euo pipefail
cd "$(dirname "$0")/.."

export ORG_GRADLE_PROJECT_UPLOAD_SIGN=true  # 업로드 키로 서명(android/key.properties)
export ORG_GRADLE_PROJECT_ADMOB_APP_ID="ca-app-pub-6270133261936882~2732521763"
BANNER_ID="ca-app-pub-6270133261936882/2812412814"
TARGET="${1:-appbundle}"

flutter build "$TARGET" --release \
  --dart-define=API_BASE_URL=https://itssophie.dev/dailycut-api \
  --dart-define=ADMOB_BANNER_ID="$BANNER_ID"
