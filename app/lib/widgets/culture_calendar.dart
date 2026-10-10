import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../theme.dart';
import 'components.dart';

String _md(String iso) {
  final d = DateTime.parse(iso);
  return '${d.month}.${d.day}';
}

String periodText(Map<String, dynamic> e) {
  final s = e['start'] as String, en = e['end'] as String;
  return s == en ? _md(s) : '${_md(s)}~${_md(en)}';
}

/// 행사 목록 한 줄(달력 아래 목록·목록 구간 공통). 누르면 상세.
Widget eventLine(BuildContext context, ApiClient api, Map<String, dynamic> e) {
  final bits = [e['kind'], if ((e['place'] as String?)?.isNotEmpty ?? false) e['place'], periodText(e)];
  return ListLine(
    name: e['title'] as String,
    badge: e['local'] == true ? '우리 동네' : null,
    sub: bits.join(' · '),
    onTap: () => showEventSheet(context, api, e),
  );
}

/// 이번 달·다음 달 행사 달력. 날짜마다 점(그날 열리는 행사 수, 최대 3개, 선택한 시군구 행사가 있으면 진하게)을
/// 찍고, 날짜를 누르면 그날 행사가 아래에 나와요. 처음엔 오늘이 선택돼 있어요.
class CultureCalendar extends StatefulWidget {
  const CultureCalendar({super.key, required this.api, required this.events, required this.scopeLabel});

  final ApiClient api;
  final List<Map<String, dynamic>> events;
  final String scopeLabel; // 예: "서울 종로구" — 달력 제목 옆에 범위 표시

  @override
  State<CultureCalendar> createState() => _CultureCalendarState();
}

class _CultureCalendarState extends State<CultureCalendar> {
  static const _limit = 8;
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  bool _showAll = false;

  String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<Map<String, dynamic>> _on(DateTime d) {
    final k = _iso(d);
    return widget.events.where((e) => (e['start'] as String).compareTo(k) <= 0 && (e['end'] as String).compareTo(k) >= 0).toList();
  }

  bool get _hasNext {
    final next = DateTime(_month.year, _month.month + 1);
    final k = _iso(next);
    return widget.events.any((e) => (e['end'] as String).compareTo(k) >= 0);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = DateTime(_month.year, _month.month);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday % 7; // 일요일 시작
    final rows = ((lead + days) / 7).ceil();
    final isThisMonth = _month.year == today.year && _month.month == today.month;
    final dayEvents = _on(_selected);
    final shown = _showAll ? dayEvents : dayEvents.take(_limit).toList();

    return ListSection(
      title: '행사 달력',
      trailing: widget.scopeLabel,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              _NavButton(label: '‹', enabled: !isThisMonth, onTap: () => setState(() => _month = DateTime(_month.year, _month.month - 1))),
              Expanded(
                child: Center(
                  child: Text('${_month.year}년 ${_month.month}월', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              _NavButton(label: '›', enabled: _hasNext && isThisMonth, onTap: () => setState(() => _month = DateTime(_month.year, _month.month + 1))),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final w in const ['일', '월', '화', '수', '목', '금', '토'])
              Expanded(
                child: Center(
                  child: Text(w, style: TextStyle(fontSize: 11, color: w == '일' ? AppColors.up : AppColors.inkSoft)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++) Expanded(child: _cell(r * 7 + c - lead + 1, days, today)),
            ],
          ),
        const SizedBox(height: 12),
        Container(height: 1, color: AppColors.ink),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '${_selected.month}월 ${_selected.day}일 · 행사 ${dayEvents.length}개',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        if (dayEvents.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text('이 날 열리는 행사가 없어요.', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
          ),
        for (final e in shown) eventLine(context, widget.api, e),
        if (!_showAll && dayEvents.length > _limit)
          GestureDetector(
            onTap: () => setState(() => _showAll = true),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(child: Text('${dayEvents.length - _limit}개 더 보기', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
            ),
          ),
      ],
    );
  }

  Widget _cell(int day, int days, DateTime today) {
    if (day < 1 || day > days) return const SizedBox(height: 52);
    final d = DateTime(_month.year, _month.month, day);
    final evs = _on(d);
    final selected = d == _selected;
    final isToday = d == today;
    final hasLocal = evs.any((e) => e['local'] == true);
    final dots = evs.length.clamp(0, 3);
    return GestureDetector(
      onTap: () => setState(() {
        _selected = d;
        _showAll = false;
      }),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.ink : null,
                border: isToday && !selected ? Border.all(color: AppColors.ink, width: 1.5) : null,
              ),
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected || isToday ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? Colors.white : (d.weekday == DateTime.sunday ? AppColors.up : AppColors.ink),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 5,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < dots; i++)
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: hasLocal ? sectionThemes[Section.culture]!.color : AppColors.inkSoft),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.label, required this.enabled, required this.onTap});

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 44,
        height: 36,
        child: Center(
          child: Text(label, style: TextStyle(fontSize: 22, color: enabled ? AppColors.ink : AppColors.line)),
        ),
      ),
    );
  }
}

/// 행사 상세 시트: 서버에서 상세(설명·요금·누리집·전화)를 받아 보여주고, 받는 동안엔 목록의 기본 정보만 보여줌.
Future<void> showEventSheet(BuildContext context, ApiClient api, Map<String, dynamic> e) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
    builder: (_) => _EventSheet(api: api, event: e),
  );
}

class _EventSheet extends StatelessWidget {
  const _EventSheet({required this.api, required this.event});

  final ApiClient api;
  final Map<String, dynamic> event;

  Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[Section.culture]!;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: FutureBuilder<Map<String, dynamic>>(
          future: api.cultureDetail(event['id'] as String),
          builder: (context, snap) {
            final d = snap.data;
            final ok = d != null && d['found'] == true;
            final image = ok ? d['image'] as String? : null;
            Widget row(String label, String? value) {
              if (value == null || value.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 56, child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft))),
                    Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 16, height: 1.5))),
                  ],
                ),
              );
            }

            final period = ok ? (d['period'] as String? ?? '') : '${event['start']} ~ ${event['end']}';
            final place = ok ? (d['place'] as String?) ?? (event['place'] as String?) : event['place'] as String?;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (image != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child: Image.network(
                        '${api.baseUrl}$image',
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => ColoredBox(color: t.highlight, child: Center(child: Image.asset(t.shapeAsset, width: 72, height: 72))),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('사진: ${d!['credit']}', style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(999)),
                      child: Text(event['kind'] as String, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                    if (event['local'] == true) ...[
                      const SizedBox(width: 6),
                      const Text('우리 동네', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(ok ? (d['title'] as String) : event['title'] as String, style: AppTheme.displaySerif(size: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                row('기간', period),
                if (ok) row('시간', d['time'] as String?),
                row('장소', place),
                if (ok) row('주소', d['address'] as String?),
                if (ok) row('요금', d['price'] as String?),
                if (ok) row('문의', d['tel'] as String?),
                if (snap.connectionState != ConnectionState.done)
                  const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: CircularProgressIndicator()))
                else if (!ok)
                  const Padding(
                    padding: EdgeInsets.only(top: 22),
                    child: Text('자세한 설명을 불러오지 못했어요.', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
                  ),
                if (ok && (d['text'] as String?) != null) ...[
                  const SizedBox(height: 22),
                  Text('소개', style: AppTheme.subheading),
                  const SizedBox(height: 6),
                  SelectableText(d['text'] as String, style: const TextStyle(fontSize: 16, height: 1.7)),
                ],
                if (ok && (d['homepage'] as String?) != null) ...[
                  const SizedBox(height: 22),
                  GestureDetector(
                    onTap: () => _open(d['homepage'] as String),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(border: Border.all(color: AppColors.ink), borderRadius: BorderRadius.circular(8)),
                      child: const Text('누리집에서 자세히 보기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
                if (ok) ...[
                  const SizedBox(height: 18),
                  Text('출처: ${d['credit']}', style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
