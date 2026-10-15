import 'package:flutter/foundation.dart';

/// 투데이 첫 화면(날씨)이 그려졌는지. 켜지면 main.dart가 다른 탭을 뒤에서 하나씩 미리 만들기 시작함(2026-10-15).
final ValueNotifier<bool> kFirstScreenReady = ValueNotifier<bool>(false);
