import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../analytics.dart';
import '../local_prefs.dart';
import '../theme.dart';
import 'components.dart';
import 'zoom_image.dart';

String _md(String iso) {
  final d = DateTime.parse(iso);
  return '${d.month}.${d.day}';
}

String periodText(Map<String, dynamic> e) {
  final s = e['start'] as String, en = e['end'] as String;
  return s == en ? _md(s) : '${_md(s)}~${_md(en)}';
}

/// 행사 종류(서버 kind: 축제 / 전시 / 연극 / 뮤지컬·오페라 / 음악·콘서트 / 교육·체험 …)를 4묶음으로.
/// 알약·아이콘·달력 점의 색이 이 묶음을 따라가서, 한눈에 종류를 구분함.
String kindGroup(String kind) {
  if (kind.contains('축제')) return '축제';
  if (kind.contains('전시') || kind.contains('미술')) return '전시';
  if (kind.contains('연극') || kind.contains('뮤지컬') || kind.contains('오페라') || kind.contains('무용') || kind.contains('음악') || kind.contains('콘서트') || kind.contains('공연') || kind.contains('국악')) return '공연';
  if (kind.contains('교육') || kind.contains('체험')) return '체험';
  return '기타';
}

({IconData icon, Color color}) kindStyle(String kind) => switch (kindGroup(kind)) {
      '축제' => (icon: Icons.celebration_outlined, color: const Color(0xFFC4472B)),
      '전시' => (icon: Icons.palette_outlined, color: const Color(0xFF2F6FB0)),
      '공연' => (icon: Icons.theater_comedy_outlined, color: const Color(0xFF7B4FA3)),
      '체험' => (icon: Icons.extension_outlined, color: const Color(0xFF2E8B57)),
      _ => (icon: Icons.event_outlined, color: AppColors.inkSoft),
    };

/// 행사 목록 한 줄(달력 아래 목록·목록 구간 공통). 누르면 상세.
Widget eventLine(BuildContext context, ApiClient api, Map<String, dynamic> e) {
  final bits = [e['kind'], if ((e['place'] as String?)?.isNotEmpty ?? false) e['place'], periodText(e)];
  final st = kindStyle(e['kind'] as String);
  return ListLine(
    leading: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(color: st.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Icon(st.icon, size: 19, color: st.color),
    ),
    name: e['title'] as String,
    badge: e['local'] == true ? '우리 동네' : null,
    sub: bits.join(' · '),
    onTap: () => showEventSheet(context, api, e),
  );
}

/// 이번 달·다음 달 행사 달력. 날짜마다 점(그날 열리는 행사 수, 최대 3개, 선택한 시군구 행사가 있으면 진하게)을
/// 찍고, 날짜를 누르면 그날 행사가 아래에 나와요. 처음엔 오늘이 선택돼 있어요.
class CultureCalendar extends StatefulWidget {
  const CultureCalendar({
    super.key,
    required this.api,
    required this.events,
  });

  final ApiClient api;
  final List<Map<String, dynamic>> events; // 이미 범위(우리 동네 / 시도 전체)로 걸러진 행사

  @override
  State<CultureCalendar> createState() => _CultureCalendarState();
}

class _CultureCalendarState extends State<CultureCalendar> {
  static const _limit = kListLimit;
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  bool _showAll = false;
  String _kind = '전체';

  @override
  void initState() {
    super.initState();
    // 마지막으로 고른 종류(축제·전시 등)를 기억해서 다음에도 그 종류로 열어 줌
    LocalPrefs.getString('culture_kind').then((v) {
      if (v != null && mounted && _kinds.contains(v)) setState(() => _kind = v);
    });
  }

  String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<Map<String, dynamic>> _on(DateTime d) {
    final k = _iso(d);
    return _filtered.where((e) => (e['start'] as String).compareTo(k) <= 0 && (e['end'] as String).compareTo(k) >= 0).toList();
  }

  List<Map<String, dynamic>> get _filtered =>
      _kind == '전체' ? widget.events : widget.events.where((e) => kindGroup(e['kind'] as String) == _kind).toList();

  /// 지금 범위에 실제로 있는 묶음만 칩으로(순서 고정)
  List<String> get _kinds {
    final present = {for (final e in widget.events) kindGroup(e['kind'] as String)};
    return ['전체', for (final k in const ['축제', '전시', '공연', '체험', '기타']) if (present.contains(k)) k];
  }

  bool get _hasNext {
    final next = DateTime(_month.year, _month.month + 1);
    final k = _iso(next);
    return _filtered.any((e) => (e['end'] as String).compareTo(k) >= 0);
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
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 10,
            children: [
              for (final k in _kinds)
                _Chip(
                  label: k,
                  dotColor: k == '전체' ? null : kindStyle(k).color,
                  selected: _kind == k,
                  onTap: () => setState(() {
                    _kind = k;
                    LocalPrefs.setString('culture_kind', k);
                    Analytics.instance.track('culture_kind', k);
                    _showAll = false;
                  }),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
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
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            const Text('날짜 아래 점 =', style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
            for (final k in _kinds.where((k) => k != '전체'))
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: kindStyle(k).color)),
                  const SizedBox(width: 4),
                  Text(k, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                ],
              ),
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
          ShowMoreButton(count: dayEvents.length - _limit, onTap: () => setState(() => _showAll = true)),
      ],
    );
  }

  Widget _cell(int day, int days, DateTime today) {
    if (day < 1 || day > days) return const SizedBox(height: 52);
    final d = DateTime(_month.year, _month.month, day);
    final evs = _on(d);
    final selected = d == _selected;
    final isToday = d == today;
    // 점 = 그날 열리는 행사의 종류별 색(축제·전시·공연·체험) — 개수가 아니라 "무슨 종류가 있는지"를 보여줌
    final groups = [for (final g in const ['축제', '전시', '공연', '체험', '기타']) if (evs.any((e) => kindGroup(e['kind'] as String) == g)) g];
    final dots = groups.length.clamp(0, 4);
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
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: kindStyle(groups[i]).color),
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
  Analytics.instance.track('culture_open', kindGroup((e['kind'] as String?) ?? ''));
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
        // 정보가 위, 사진은 맨 아래(스크롤해서 보기). 상세가 도착해도 시트가 다시 커지지 않게 처음부터 넉넉한 높이로 엶.
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height * 0.62),
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: kindStyle(event['kind'] as String).color, borderRadius: BorderRadius.circular(999)),
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
                if (image != null) ...[
                  const SizedBox(height: 22),
                  _imageFlag(
                    d!['credit'] as String?,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ZoomImage(
                          provider: NetworkImage('${api.baseUrl}$image'),
                          background: t.highlight,
                          onError: ColoredBox(color: t.highlight, child: SizedBox(height: 140, child: Center(child: Image.asset(t.shapeAsset, width: 72, height: 72)))),
                        ),
                        const SizedBox(height: 6),
                        Text('사진: ${d['credit']}', style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                      ],
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
      ),
    );
  }
}


class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap, this.dotColor});

  final Color? dotColor; // 종류 칩 앞의 색 점
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.background,
          border: Border.all(color: selected ? AppColors.ink : AppColors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor)), const SizedBox(width: 6)],
            Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Colors.white : AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}
/// 점검 모드(?license=1)에서만: 문화포털(한국문화정보원) 사진은 저작권 구분이 없어 광고 전 확인 필요로 표시.
Widget _imageFlag(String? credit, Widget child) => (credit ?? '').contains('문화포털')
    ? LicenseFlag(level: LicenseLevel.check, label: '문화포털 사진 - 포스터 저작권 확인 안 됨', child: child)
    : child;
