import 'package:flutter/foundation.dart';

/// 투데이 첫 화면(날씨)이 그려졌는지. 켜지면 main.dart가 다른 탭을 뒤에서 하나씩 미리 만들기 시작함(2026-10-15).
final ValueNotifier<bool> kFirstScreenReady = ValueNotifier<bool>(false);

/// 하위 구분(나들이·혜택)에서 첫/마지막 구분을 넘어 밀면 이웃 탭으로 이어짐 — RootShell이 연결해 둠(+1 다음 탭, -1 이전 탭).
void Function(int step)? swipeToTab;
