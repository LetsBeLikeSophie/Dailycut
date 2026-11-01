// 공용 부품 — 로딩·빈 목록 안내, 라이선스 점검 표시
// (2026-10-29: 1,787줄짜리 components.dart를 주제별로 나눔. 불러오는 쪽은 그대로 `widgets/components.dart` 하나만 import 하면 됨.)
import 'package:flutter/material.dart';

import '../../theme.dart';

/// 받는 중 표시(작은 원 + 문구). 목록 자리에서 쓰는 공용 모양.
class LoadingNote extends StatelessWidget {
  const LoadingNote({super.key, this.label = '불러오는 중이에요'});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink)),
        if (label != null) ...[
          const SizedBox(height: 14),
          Text(label!, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
        ],
      ],
    );
  }
}

/// 목록이 비었거나 못 받았을 때의 한 줄 안내(가운데, 회색 13). onTap이 있으면 눌러서 다시 시도하는 안내로 쓰임.
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key, this.onTap, this.vertical = 40});

  final String text;
  final VoidCallback? onTap;
  final double vertical;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: vertical),
        child: Center(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.6))),
      ),
    );
  }
}

/// 개발자 점검용: 광고(상업 이용)를 켰을 때 라이선스 문제가 되는 구역에 테두리·꼬리표를 씌움.
/// 주소 뒤에 `?license=1`을 붙였을 때만 보이고, 평소엔 아무 일도 안 함(자식 그대로).
///  - block(빨강): 상업적 이용·제3자 제공이 약관/이용허락으로 막힌 데이터
///  - check(주황): 광고를 켜기 전에 허락·확인이 필요한 데이터
bool get kShowLicenseFlags => Uri.base.queryParameters['license'] == '1';

enum LicenseLevel { block, check }

class LicenseFlag extends StatelessWidget {
  const LicenseFlag({super.key, required this.label, required this.child, this.level = LicenseLevel.block});

  final String label;
  final Widget child;
  final LicenseLevel level;

  @override
  Widget build(BuildContext context) {
    if (!kShowLicenseFlags) return child;
    final color = level == LicenseLevel.block ? const Color(0xFFE5231B) : const Color(0xFFF08A00);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
            decoration: BoxDecoration(border: Border.all(color: color, width: 2), borderRadius: BorderRadius.circular(6)),
            child: child,
          ),
          Positioned(
            top: -9,
            left: 10,
            right: 10,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                color: color,
                child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "출처 · 기준일" 같은 자료 정보를 이름-값 두 칸으로 보여 주는 작은 표(2026-11-01).
/// 줄글 안내("…일 수 있어요 …해 주세요") 대신 언제 기준인지·어디서 온 건지만 짧게 나란히 놓음.
/// [rows]의 값이 비어 있으면 그 줄은 건너뜀. [stale]이 true인 줄은 값 뒤에 "오래됨"을 붙임.
class DataMeta extends StatelessWidget {
  const DataMeta({super.key, required this.rows, this.top = 14});

  final List<DataMetaRow> rows;
  final double top;

  @override
  Widget build(BuildContext context) {
    final shown = [for (final r in rows) if (r.value.isNotEmpty) r];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 64, child: Text(r.label, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft))),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: r.value,
                        children: [if (r.stale) const TextSpan(text: '  오래됨', style: TextStyle(fontWeight: FontWeight.w700))],
                      ),
                      style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class DataMetaRow {
  const DataMetaRow(this.label, this.value, {this.stale = false});

  final String label;
  final String value;
  final bool stale;
}

/// 20261101 / 2026-11-01 / 202611 / 2026 → "2026.11.01" / "2026.11" / "2026년" (못 읽으면 빈 문자열).
String dotDate(String? raw) {
  final d = (raw ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length == 4) return '$d년'; // 공식 페이지에 연도만 적힌 기준일
  if (d.length == 8) return '${d.substring(0, 4)}.${d.substring(4, 6)}.${d.substring(6)}';
  if (d.length == 6) return '${d.substring(0, 4)}.${d.substring(4)}';
  return '';
}

/// 기준일 몇 개 → 하나면 "2026.10", 여러 개면 가장 오래된 달~가장 최근 달 "2025.03 ~ 2026.10".
String dateRange(Iterable<String> ymds) {
  final months = {for (final v in ymds) if (v.replaceAll(RegExp(r'[^0-9]'), '').length >= 6) v.replaceAll(RegExp(r'[^0-9]'), '').substring(0, 6)}.toList()..sort();
  if (months.isEmpty) return '';
  return months.length == 1 ? dotDate(months.first) : '${dotDate(months.first)} ~ ${dotDate(months.last)}';
}
