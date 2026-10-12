import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analytics.dart';
import '../local_prefs.dart';
import '../theme.dart';

/// 정부 지원 "내 조건" — 나이·성별·소득구간·해당 특성. 이 기기에만 저장함(로그인 없음).
/// 서버로는 목록을 거를 때 요청 본문으로만 보내고, 서버는 저장·로그하지 않음.
class SupportProfile extends ChangeNotifier {
  SupportProfile._();
  static final SupportProfile instance = SupportProfile._();

  static const _key = 'support_profile_v1';

  int? age;
  String? gender; // m | f
  int? income; // 1~5 기준중위소득 구간
  final Set<String> traits = {};
  bool _loaded = false;

  bool get isSet => age != null || gender != null || income != null || traits.isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await LocalPrefs.getString(_key);
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      age = m['age'] as int?;
      gender = m['gender'] as String?;
      income = m['income'] as int?;
      traits
        ..clear()
        ..addAll(((m['traits'] as List?) ?? const []).cast<String>());
      notifyListeners();
    } catch (_) {}
  }

  Future<void> save({int? age, String? gender, int? income, required Set<String> traits}) async {
    this.age = age;
    this.gender = gender;
    this.income = income;
    this.traits
      ..clear()
      ..addAll(traits);
    await LocalPrefs.setString(_key, jsonEncode(toJson()));
    notifyListeners();
    // 통계는 횟수만: 연령대·성별과, 민감하지 않은 직업·학생 특성만(소득·장애·질병·보훈은 보내지 않음)
    if (age != null || gender != null) {
      Analytics.instance.track('support_profile', '${age == null ? "na" : "${age ~/ 10 * 10}s"}_${gender ?? "na"}');
    }
    for (final k in traits.where(kOpenTraits.contains)) {
      Analytics.instance.track('support_trait', k);
    }
  }

  Future<void> clear() async {
    age = null;
    gender = null;
    income = null;
    traits.clear();
    await LocalPrefs.setString(_key, '');
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {'age': age, 'gender': gender, 'income': income, 'traits': traits.toList()};

  /// 서버로 보낼 본문의 조건 부분(지역은 호출하는 쪽에서 붙임).
  Map<String, dynamic> toRequest() => {
        if (age != null) 'age': age,
        if (gender != null) 'gender': gender,
        if (income != null) 'income': income,
        'traits': traits.toList(),
      };

  /// 칩에 보여줄 한 줄 요약.
  String get summary {
    final parts = <String>[
      if (age != null) '$age세',
      if (gender != null) gender == 'm' ? '남' : '여',
      if (income != null) kIncomeLabels[income! - 1],
      ...traits.map((k) => kTraitLabels[k] ?? k),
    ];
    return parts.join(' · ');
  }
}

/// 통계로 보내도 되는(민감하지 않은) 특성만.
const kOpenTraits = {'farmer', 'fisher', 'livestock', 'forest', 'univ', 'worker', 'jobseeker'};

const kIncomeLabels = ['소득 50%↓', '소득 75%↓', '소득 100%↓', '소득 200%↓', '소득 200%↑'];

const kTraitLabels = {
  'newlywed': '예비·신혼부부',
  'pregnant': '임신 중',
  'birth': '출산·입양',
  'elem': '초등학생',
  'middle': '중학생',
  'high': '고등학생',
  'univ': '대학생',
  'worker': '근로자',
  'jobseeker': '구직자',
  'farmer': '농업인',
  'fisher': '어업인',
  'livestock': '축산업인',
  'forest': '임업인',
  'disabled': '장애인',
  'veteran': '국가보훈',
  'illness': '질병·질환',
};

Future<void> showSupportProfileSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
    builder: (_) => const _ProfileSheet(),
  );
}

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet();

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  final _p = SupportProfile.instance;
  late final TextEditingController _age = TextEditingController(text: _p.age?.toString() ?? '');
  late String? _gender = _p.gender;
  late int? _income = _p.income;
  late final Set<String> _traits = {..._p.traits};

  @override
  void dispose() {
    _age.dispose();
    super.dispose();
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? AppColors.ink : AppColors.background,
            border: Border.all(color: on ? AppColors.ink : AppColors.line),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? Colors.white : AppColors.ink)),
        ),
      );

  Widget _group(String title, Widget body, {String? hint}) => Padding(
        padding: const EdgeInsets.only(top: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTheme.subheading),
            if (hint != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(hint, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft, height: 1.5))),
            const SizedBox(height: 10),
            body,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('내 조건', style: AppTheme.displaySerif(size: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              '고른 항목에 맞는 지원만 추려서 보여줘요. 이 기기에만 저장되고, 서버에는 목록을 거를 때만 전달될 뿐 저장되지 않아요. 비워 둔 항목은 따지지 않아요.',
              style: TextStyle(fontSize: 12, color: AppColors.inkSoft, height: 1.6),
            ),
            _group(
              '만 나이',
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _age,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                  decoration: const InputDecoration(isDense: true, hintText: '예: 34', suffixText: '세', border: OutlineInputBorder()),
                ),
              ),
            ),
            _group(
              '성별',
              Wrap(spacing: 8, runSpacing: 8, children: [
                _chip('남', _gender == 'm', () => setState(() => _gender = _gender == 'm' ? null : 'm')),
                _chip('여', _gender == 'f', () => setState(() => _gender = _gender == 'f' ? null : 'f')),
              ]),
            ),
            _group(
              '소득 수준',
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var i = 1; i <= 5; i++) _chip(const ['50% 이하', '75% 이하', '100% 이하', '200% 이하', '200% 초과'][i - 1], _income == i, () => setState(() => _income = _income == i ? null : i)),
              ]),
              hint: '기준 중위소득 대비(가구원 수 기준)예요. 잘 모르겠으면 비워 두세요.',
            ),
            _group(
              '해당되는 것 (여러 개 선택)',
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in kTraitLabels.entries) _chip(e.value, _traits.contains(e.key), () => setState(() => _traits.contains(e.key) ? _traits.remove(e.key) : _traits.add(e.key))),
              ]),
              hint: '특정 대상만 받는 지원(학생·농업인 등)은 여기서 고른 것에만 나와요.',
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                if (_p.isSet)
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final nav = Navigator.of(context);
                        await _p.clear();
                        nav.pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(8)),
                        child: const Text('조건 지우기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                if (_p.isSet) const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () async {
                      final nav = Navigator.of(context);
                      final a = int.tryParse(_age.text);
                      await _p.save(age: a != null && a <= 120 ? a : null, gender: _gender, income: _income, traits: _traits);
                      nav.pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(8)),
                      child: const Text('이 조건으로 보기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('실제로 받을 수 있는지는 기관의 심사로 정해져요. 여기선 가능성이 있는 것만 추려 보여줘요.', style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.6)),
          ],
        ),
      ),
    );
  }
}
