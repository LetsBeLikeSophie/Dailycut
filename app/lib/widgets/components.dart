// 2026-10-10: "카드 상자 대신 한 화면 전체를 규칙으로 디자인"하는 방향으로
// 전면 개편(디자인 시안: 생활 탭 한 화면). 규칙 여섯 가지 —
//  1) 카드 상자 없음, 여백과 가는 선으로만 구분(목록 맨 위만 진한 선)
//  2) 그래픽은 화면 맨 위의 큰 도형 하나뿐
//  3) 섹션 색은 도형·제목 형광펜·차트 끝점에만, 오르내림은 의미색(파랑/빨강)
//  4) 세리프는 한 문장 제목과 큰 숫자에만, 나머지는 전부 산세리프
//  5) 목록은 "이름 · 작은 추이 · 값과 변동" 한 가지 모양(ListLine)
//  6) 글자 크기는 11 / 13 / 16 / 24 / 60 다섯 단계
// 화면은 이 부품의 조합으로만 만들고, 색은 SectionTheme만 고치면 바뀜.

// 2026-10-29: 파일 하나가 1,787줄이라 주제별로 나눔(components/). 화면·위젯은 예전처럼 이 파일만 import 하면 됨.
export 'components/basics.dart';
export 'components/text.dart';
export 'components/hero.dart';
export 'components/charts.dart';
export 'components/lists.dart';
export 'components/controls.dart';
export 'components/sheets.dart';
export 'components/notes.dart';
