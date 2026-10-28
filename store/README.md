# store/ — Google Play 스토어 등록 자료

| 파일 | 설명 |
|---|---|
| `listing-ko.md` | 한국어 등록정보 원문(앱 이름·짧은/긴 설명·태그·연락처). **Play Console에 붙여 넣는 원본** — 설명을 고치면 여기도 같이 고칠 것 |
| `icon-512.png` | 스토어 아이콘(512x512). 원본은 `app/assets/icon/app_icon.png` |
| `feature-1024x500.png` | 대표(그래픽) 이미지. 글꼴 NotoSerifKR-**700** 사용(900 서브셋엔 글자가 모자라 네모로 나옴) |
| `screenshots/` | 폰 스크린샷 5장(1080x2154, 상태 표시줄 66px 잘라냄). 광고 칸이 없는 빌드를 에뮬레이터에서 찍음 |
| `*.aab` | 스토어에 올리는 번들 — **git에 올리지 않음**(`.gitignore`). 파일 이름에 버전을 붙임 |

## 번들 만들기
`bash app/tools/build_release.sh appbundle test`  — 비공개 테스트용(광고 단위만 구글 테스트 ID)
`bash app/tools/build_release.sh appbundle`        — 프로덕션용(실제 광고 ID, 버전 코드를 올릴 것)

자세한 내용은 `docs/play-console.md`.
