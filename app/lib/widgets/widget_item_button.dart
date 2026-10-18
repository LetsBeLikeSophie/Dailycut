import 'package:flutter/material.dart';

import '../local_prefs.dart';
import '../theme.dart';
import '../widget_bridge.dart';
import 'components.dart';

/// 홈 화면 "장바구니" 위젯에 보일 대표 품목을 하나 고르는 버튼(2026-10-19). 고르지 않으면 위젯은 내 장바구니(없으면 대표 8품목) 합계를 보임.
/// 기기에만 저장(`widget_item`)하고, 위젯이 이 값을 읽어 서버에 "이 품목 가격"을 요청함 — 서버엔 저장·로그 안 함.
class WidgetItemButton extends StatefulWidget {
  const WidgetItemButton({super.key, required this.name});

  final String name;

  static const prefKey = 'widget_item';

  @override
  State<WidgetItemButton> createState() => _WidgetItemButtonState();
}

class _WidgetItemButtonState extends State<WidgetItemButton> {
  late String? _current = LocalPrefs.stringSync(WidgetItemButton.prefKey);

  bool get _picked => _current == widget.name;

  Future<void> _toggle() async {
    if (_picked) {
      await LocalPrefs.remove(WidgetItemButton.prefKey);
      _current = null;
    } else {
      await LocalPrefs.setString(WidgetItemButton.prefKey, widget.name);
      _current = widget.name;
    }
    if (mounted) setState(() {});
    WidgetBridge.refresh(); // 저장이 끝난 뒤에 불러야 위젯이 새 값을 읽음
  }

  @override
  Widget build(BuildContext context) {
    final other = _current != null && !_picked;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ActionButton(
            label: _picked ? '홈 화면 위젯에서 빼기' : '홈 화면 위젯에 이 품목 보이기',
            icon: _picked ? Icons.check : Icons.widgets_outlined,
            filled: _picked,
            vertical: 12,
            onTap: _toggle,
          ),
          const SizedBox(height: 6),
          Text(
            _picked
                ? '위젯에 ${widget.name} 가격이 나와요. 빼면 장바구니 합계로 돌아가요.'
                : other
                    ? '지금은 위젯에 $_current 가격이 나와요. 누르면 ${widget.name}(으)로 바꿔요.'
                    : '홈 화면 "장바구니" 위젯에 이 품목의 가격과 지난주 대비를 보여 줘요.',
            style: const TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.5),
          ),
        ],
      ),
    );
  }
}
