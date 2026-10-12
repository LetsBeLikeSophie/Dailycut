import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analytics.dart';
import '../local_prefs.dart';
import '../theme.dart';
import 'components.dart';

/// 정부 지원 "내 조건" — 생년월일(만 나이 계산용)·성별·소득구간·해당 특성. 이 기기에만 저장함(로그인 없음).
/// 생년월일은 기기 안에서 만 나이를 계산하는 데만 쓰고 서버로 보내지 않음 — 서버엔 계산된 나이(숫자)만, 목록을 거를 때
/// 요청 본문으로 보내고, 서버는 저장·로그하지 않음. 그래서 서비스가 개인정보를 "수집"하는 게 아님(동의 절차 불필요).
/// 나중에 로그인·서버 저장을 붙이면 그땐 개인정보 처리방침·동의가 필요해짐.
class SupportProfile extends ChangeNotifier {
  SupportProfile._();
  static final SupportProfile instance = SupportProfile._();

  static const _key = 'support_profile_v1';

  String? birth; // 'YYYY-MM-DD'(이 기기에만 저장)
  int? _legacyAge; // 예전 버전에서 직접 입력해 저장한 나이(생년월일이 없을 때만 씀)
  String? gender; // m | f
  int? income; // 1~5 기준중위소득 구간
  final Set<String> traits = {};
  bool _loaded = false;

  /// 오늘 기준 만 나이(생년월일이 없거나 틀리면 null). 저장하지 않고 쓸 때마다 계산해서 생일이 지나면 자동으로 바뀜.
  int? get age => birth == null ? _legacyAge : ageFromBirth(birth!);

  bool get isSet => age != null || gender != null || income != null || traits.isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await LocalPrefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      birth = m['birth'] as String?;
      _legacyAge = birth == null ? m['age'] as int? : null;
      gender = m['gender'] as String?;
      income = m['income'] as int?;
      traits
        ..clear()
        ..addAll(((m['traits'] as List?) ?? const []).cast<String>());
      notifyListeners();
    } catch (_) {}
  }

  Future<void> save({String? birth, String? gender, int? income, required Set<String> traits}) async {
    this.birth = birth;
    _legacyAge = null;
    this.gender = gender;
    this.income = income;
    this.traits
      ..clear()
      ..addAll(traits);
    await LocalPrefs.setString(_key, jsonEncode(toJson()));
    notifyListeners();
    // 통계는 횟수만: 연령대·성별과, 민감하지 않은 직업·학생 특성만(소득·장애·질병·보훈은 보내지 않음)
    final a = age; // 생년월일 자체는 보내지 않고 10살 단위 연령대만
    if (a != null || gender != null) {
      Analytics.instance.track('support_profile', '${a == null ? "na" : "${a ~/ 10 * 10}s"}_${gender ?? "na"}');
    }
    for (final k in traits.where(kOpenTraits.contains)) {
      Analytics.instance.track('support_trait', k);
    }
  }

  Future<void> clear() async {
    birth = null;
    _legacyAge = null;
    gender = null;
    income = null;
    traits.clear();
    await LocalPrefs.setString(_key, '');
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {'birth': birth, 'gender': gender, 'income': income, 'traits': traits.toList()};

  /// 서버로 보낼 본문의 조건 부분(지역은 호출하는 쪽에서 붙임).
  Map<String, dynamic> toRequest() => {
        if (age != null) 'age': age,
        if (gender != null) 'gender': gender,
        if (income != null) 'income': income,
        'traits': traits.toList(),
      };

  /// 한 줄 요약(예: "34세 · 여 · 근로자").
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

/// 'YYYY-MM-DD' → 오늘 기준 만 나이. 형식이 틀리거나 미래면 null.
int? ageFromBirth(String iso, {DateTime? today}) {
  final b = DateTime.tryParse(iso);
  if (b == null) return null;
  final t = today ?? DateTime.now();
  var age = t.year - b.year;
  if (t.month < b.month || (t.month == b.month && t.day < b.day)) age--;
  return age < 0 || age > 120 ? null : age;
}

/// 연·월·일 숫자 → 'YYYY-MM-DD'. 없는 날짜(2월 30일 등)·미래·1900년 이전이면 null.
String? birthFromParts(String y, String m, String d, {DateTime? today}) {
  final yy = int.tryParse(y), mm = int.tryParse(m), dd = int.tryParse(d);
  if (yy == null || mm == null || dd == null || y.length != 4 || yy < 1900) return null;
  final date = DateTime(yy, mm, dd);
  if (date.year != yy || date.month != mm || date.day != dd) return null; // 2월 30일 → 3월 2일로 넘어가는 경우 걸러냄
  if (date.isAfter(today ?? DateTime.now())) return null;
  return '${y.padLeft(4, '0')}-${mm.toString().padLeft(2, '0')}-${dd.toString().padLeft(2, '0')}';
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
  late final TextEditingController _y = TextEditingController(text: _p.birth?.substring(0, 4) ?? '');
  late final TextEditingController _m = TextEditingController(text: _p.birth == null ? '' : int.parse(_p.birth!.substring(5, 7)).toString());
  late final TextEditingController _d = TextEditingController(text: _p.birth == null ? '' : int.parse(_p.birth!.substring(8, 10)).toString());
  late String? _gender = _p.gender;
  late int? _income = _p.income;
  late final Set<String> _traits = {..._p.traits};

  @override
  void dispose() {
    _y.dispose();
    _m.dispose();
    _d.dispose();
    super.dispose();
  }

  String? get _birth => birthFromParts(_y.text, _m.text, _d.text);
  bool get _birthTyped => _y.text.isNotEmpty || _m.text.isNotEmpty || _d.text.isNotEmpty;

  Widget _numField(TextEditingController c, String hint, String suffix, double width, int maxLen) => SizedBox(
        width: width,
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(maxLen)],
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          cursorColor: AppColors.ink,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w400, color: AppColors.line),
            suffixText: suffix,
            suffixStyle: const TextStyle(fontSize: 14, color: AppColors.inkSoft),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.line)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.ink, width: 2)),
          ),
        ),
      );

  /// 묶음: 소제목(+ 오른쪽 작은 보충 글) 아래에 선택지. 다른 목록의 소제목과 같은 글자 크기.
  Widget _group(String title, Widget body, {String? note}) => Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(title, style: AppTheme.subheading),
                if (note != null) ...[
                  const SizedBox(width: 8),
                  Text(note, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                ],
              ],
            ),
            const SizedBox(height: 14),
            body,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 28 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('내 조건', style: AppTheme.displaySerif(size: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('이 기기에만 저장되고, 서버로는 계산된 만 나이만 전달돼요', style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
            _group(
              '생년월일',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _numField(_y, '1990', '년', 86, 4),
                      const SizedBox(width: 18),
                      _numField(_m, '5', '월', 60, 2),
                      const SizedBox(width: 18),
                      _numField(_d, '12', '일', 60, 2),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _birth != null
                        ? '만 ${ageFromBirth(_birth!)}세'
                        : (_birthTyped && _y.text.length == 4 && _m.text.isNotEmpty && _d.text.isNotEmpty ? '날짜를 다시 확인해 주세요' : ''),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _birth != null ? AppColors.ink : AppColors.up),
                  ),
                ],
              ),
              note: '만 나이를 계산하는 데만 쓰여요',
            ),
            _group(
              '성별',
              Wrap(spacing: 8, runSpacing: 10, children: [
                PillChip(label: '남', selected: _gender == 'm', vertical: 9, onTap: () => setState(() => _gender = _gender == 'm' ? null : 'm')),
                PillChip(label: '여', selected: _gender == 'f', vertical: 9, onTap: () => setState(() => _gender = _gender == 'f' ? null : 'f')),
              ]),
            ),
            _group(
              '소득',
              Wrap(spacing: 8, runSpacing: 10, children: [
                for (var i = 1; i <= 5; i++)
                  PillChip(
                    label: const ['50% 이하', '75% 이하', '100% 이하', '200% 이하', '200% 초과'][i - 1],
                    selected: _income == i,
                    vertical: 9,
                    onTap: () => setState(() => _income = _income == i ? null : i),
                  ),
              ]),
              note: '기준 중위소득 대비',
            ),
            _group(
              '해당되는 것',
              Wrap(spacing: 8, runSpacing: 10, children: [
                for (final e in kTraitLabels.entries)
                  PillChip(
                    label: e.value,
                    selected: _traits.contains(e.key),
                    vertical: 9,
                    onTap: () => setState(() => _traits.contains(e.key) ? _traits.remove(e.key) : _traits.add(e.key)),
                  ),
              ]),
              note: '여러 개 선택',
            ),
            const SizedBox(height: 36),
            GestureDetector(
              onTap: () async {
                final nav = Navigator.of(context);
                await _p.save(birth: _birth, gender: _gender, income: _income, traits: _traits);
                nav.pop();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(8)),
                child: const Text('이 조건으로 보기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
            if (_p.isSet)
              Center(
                child: GestureDetector(
                  onTap: () async {
                    final nav = Navigator.of(context);
                    await _p.clear();
                    nav.pop();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
                    child: Text('조건 지우기', style: TextStyle(fontSize: 13, color: AppColors.inkSoft, decoration: TextDecoration.underline)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
