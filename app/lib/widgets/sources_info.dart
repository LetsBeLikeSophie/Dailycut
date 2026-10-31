import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../analytics.dart';
import '../local_prefs.dart';
import '../theme.dart';
import '../widget_bridge.dart';
import 'ad_slot.dart';
import 'components.dart' show CheckToggle, PillChip;

/// 앱이 쓰는 공공데이터·외부 데이터 출처(이용 조건 표기 포함). 화면마다 출처를 길게 적는 대신
/// 작은 ⓘ → 이 시트에서 한 번에 보여줌. 새 데이터를 붙이면 여기에 한 줄 추가.
///
/// 2026-10-21: 구글 플레이 "혼동을 야기하는 주장" 검토에서 "정부 정보의 원본 출처 링크 누락"으로 거부돼, 기관마다 공식 사이트 주소를 붙이고
/// (세 번째 값, 눌러서 열림) 시트 맨 위에 "정부·공공기관과 관계없는 민간 서비스" 안내를 둠. 새 데이터를 붙일 땐 공식 사이트 주소도 같이 적을 것.
const kAllSources = <(String, String, String)>[
  ('기상청', '단기예보·중기예보·초단기실황 (공공누리 1유형: 출처표시)', 'https://www.weather.go.kr'),
  ('한국환경공단 에어코리아', '실시간 대기오염 측정값 — 측정소 한 곳의 값과 등급을 가공 없이 표시 (공공누리 3유형: 출처표시·변경금지)', 'https://www.airkorea.or.kr'),
  ('한국천문연구원', '특일(공휴일)·24절기·일출몰 정보', 'https://www.kasi.re.kr'),
  ('한국농수산식품유통공사(aT)', '농축수산물 소매가격(상품 등급 평균)', 'https://www.at.or.kr'),
  ('행정안전부 공공서비스(혜택) 정보', '정부24·보조금24의 지원 서비스 정보와 지원조건', 'https://www.gov.kr'),
  ('한국부동산원 청약홈', 'APT·무순위·오피스텔·공공지원 민간임대 분양공고', 'https://www.applyhome.co.kr'),
  ('국토교통부 마이홈포털', '공공임대 입주자 모집공고', 'https://www.myhome.go.kr'),
  ('한국토지주택공사(LH)', '공공임대·분양 공고(LH청약플러스)', 'https://apply.lh.or.kr'),
  ('서민금융진흥원', '대출상품 한눈에(서민금융 상품 정보)', 'https://www.kinfa.or.kr'),
  ('식품의약품안전처 식품영양성분DB', '장보기 품목의 열량·영양(생것, 100g 기준)', 'https://www.mfds.go.kr'),
  ('축산물품질평가원', '축산물유통정보 — 소·돼지 부위별 소비자가격(평년 대비)', 'https://www.ekape.or.kr'),
  ('한국관광공사', '축제·행사, 캠핑(고캠핑), 반려동물 동반 여행, 웰니스 관광, 걷기길(두루누비), 전통시장 사진', 'https://korean.visitkorea.or.kr'),
  ('한국관광공사 관광지 집중률 방문자 추이 예측', '관광지별 예상 방문 집중도(오늘부터 약 30일 뒤까지)', 'https://knto.or.kr'),
  ('한국문화정보원 문화포털', '전시·공연 정보(사진은 쓰지 않음)', 'https://www.culture.go.kr'),
  ('소상공인시장진흥공단', '전통시장 현황', 'https://www.semas.or.kr'),
  ('지역정보개발원', '공공도서관 정보와 열람실 남은 좌석', 'https://www.klid.or.kr'),
  ('Wikimedia Commons', '채소·과일 사진 (작가·라이선스는 사진 아래에 표시)', 'https://commons.wikimedia.org'),
  ('공공데이터포털', '위 데이터를 내려받는 정부 공식 포털(개방된 공공데이터의 원본 목록)', 'https://www.data.go.kr'),
];

/// 눌러서 외부(브라우저)로 여는 밑줄 링크 한 줄.
class SourceLink extends StatelessWidget {
  const SourceLink(this.label, this.url, {super.key, this.size = 13, this.bold = false});

  final String label;
  final String url;
  final double size;
  final bool bold;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Analytics.instance.track('life_open', 'source-link');
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(label, style: TextStyle(fontSize: size, color: AppColors.ink, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, decoration: TextDecoration.underline, height: 1.4)),
        ),
      );
}

/// 정부 정보를 보여 주는 구역 맨 아래에 두는 "원본 확인" 링크 모음 + 민간 서비스 안내.
class OfficialSourceLinks extends StatelessWidget {
  const OfficialSourceLinks({super.key, required this.links});

  /// (이름, 공식 사이트 주소)
  final List<(String, String)> links;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('원본은 공식 사이트에서 확인하세요', style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.6)),
            const SizedBox(height: 2),
            Wrap(
              spacing: 16,
              children: [for (final (name, url) in links) SourceLink(name, url)],
            ),
            const SizedBox(height: 4),
            const Text('데일리컷은 정부·공공기관과 관계없는 민간 서비스예요.', style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.6)),
          ],
        ),
      );
}

/// [current]가 있으면 "이 화면" 출처를 맨 위에, 그 아래 앱 전체 출처 목록.
Future<void> showSourcesSheet(BuildContext context, {String? current}) {
  Analytics.instance.track('sources_open');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('데이터 출처', style: AppTheme.displaySerif(size: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              '데일리컷은 정부·공공기관과 관계없는 민간 서비스예요. 정부·공공기관이 제공하거나 보증하는 앱이 아니고, 공개된 공공데이터를 모아 보여 드려요. 원본은 아래 각 기관의 공식 사이트에서 확인할 수 있어요.',
              style: TextStyle(fontSize: 13, color: AppColors.ink, height: 1.6),
            ),
            if (current != null) ...[
              const SizedBox(height: 16),
              Text('이 화면', style: AppTheme.subheading),
              const SizedBox(height: 6),
              Text(current, style: const TextStyle(fontSize: 16, height: 1.6)),
            ],
            const SizedBox(height: 22),
            Text('데일리컷이 쓰는 데이터', style: AppTheme.subheading),
            const SizedBox(height: 8),
            for (final (name, desc, url) in kAllSources)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 2026-10-24: 기관 이름 자체가 공식 사이트 링크(주소 글자를 한 줄 더 보여 주지 않음 — 항목당 두 줄 차지해서)
                    SourceLink(name, url, bold: true),
                    Text(desc, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.5)),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            const Text(
              '공공데이터포털(data.go.kr)에서 제공하는 공공데이터를 가공해 보여드려요. 이용 조건은 데이터마다 달라요.',
              style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.6),
            ),
            if (kAdsEnabled) ...[
              const SizedBox(height: 22),
              Text('광고', style: AppTheme.subheading),
              const SizedBox(height: 6),
              const Text(
                '화면에 "광고"라고 표시된 배너는 구글 애드몹이 제공해요. 광고 제공을 위해 광고 식별자 같은 기기 정보를 쓸 수 있고(폰 설정에서 광고 맞춤설정을 끌 수 있어요), 이는 위 익명 통계와 별개예요.',
                style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.6),
              ),
            ],
            if (WidgetBridge.supported) ...[
              const SizedBox(height: 22),
              Text('아침 날씨 알림', style: AppTheme.subheading),
              const SizedBox(height: 6),
              const Text(
                '정한 시각에 지금 지역의 날씨·옷차림·미세먼지를 알려 줘요. 이 기기 안에서 예약하는 알림이라 서버에 기기 정보를 보내지 않아요. 폰의 배터리 절약 상태에 따라 몇 분 늦을 수 있어요.',
                style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.6),
              ),
              const _BriefingSetting(),
            ],
            const SizedBox(height: 22),
            Text('앱 개선을 위한 익명 통계', style: AppTheme.subheading),
            const SizedBox(height: 6),
            const Text(
              '어느 화면·기능이 많이 쓰이는지만 익명으로 집계해요. 이름·위치·기기 정보·검색어는 모으지 않고, 개인을 구분할 수도 없어요. 내 장바구니 같은 설정은 이 기기에만 저장돼요.',
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.6),
            ),
            const _AnalyticsSwitch(),
            const SizedBox(height: 14),
            Row(children: [
              _LegalLink('서비스 소개', 'about.html'),
              const SizedBox(width: 18),
              _LegalLink('개인정보처리방침', 'privacy.html'),
            ]),
          ],
        ),
      ),
    ),
  );
}


/// 같은 사이트의 정적 안내 페이지(web/about.html, web/privacy.html)를 새 탭으로 엶
class _LegalLink extends StatelessWidget {
  const _LegalLink(this.label, this.page);

  final String label;
  final String page;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 웹은 같은 사이트의 상대 주소, 설치형 앱은 배포 사이트의 절대 주소(앱에서는 Uri.base가 파일 경로라 깨짐)
      onTap: () => launchUrl(kIsWeb ? Uri.base.resolve(page) : Uri.parse('https://itssophie.dev/dailycut/$page'), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft, decoration: TextDecoration.underline)),
      ),
    );
  }
}

class _AnalyticsSwitch extends StatefulWidget {
  const _AnalyticsSwitch();

  @override
  State<_AnalyticsSwitch> createState() => _AnalyticsSwitchState();
}

class _AnalyticsSwitchState extends State<_AnalyticsSwitch> {
  bool _on = Analytics.instance.enabled;

  @override
  Widget build(BuildContext context) {
    return CheckToggle(
      label: '익명 통계 보내기',
      on: _on,
      onTap: () {
        setState(() => _on = !_on);
        Analytics.instance.setEnabled(_on);
      },
    );
  }
}

/// 아침 날씨 알림 켜기·끄기와 시각(2026-10-31). 저장값 `brief_time`("07:30", 없으면 꺼짐)을 안드로이드 쪽(Briefing.kt)이 읽음.
const kBriefTimes = ['06:30', '07:00', '07:30', '08:00', '08:30', '09:00'];

class _BriefingSetting extends StatefulWidget {
  const _BriefingSetting();

  @override
  State<_BriefingSetting> createState() => _BriefingSettingState();
}

class _BriefingSettingState extends State<_BriefingSetting> {
  String? _time = LocalPrefs.stringSync('brief_time');
  String? _note;

  Future<void> _toggle() async {
    if (_time != null) {
      setState(() {
        _time = null;
        _note = null;
      });
      await LocalPrefs.remove('brief_time');
      await WidgetBridge.briefApply();
      Analytics.instance.track('brief', 'off');
      return;
    }
    final ok = await WidgetBridge.notifRequest();
    if (!mounted) return;
    if (!ok) {
      setState(() => _note = '알림이 꺼져 있어요. 폰 설정 > 앱 > 데일리컷 > 알림에서 켜 주세요.');
      return;
    }
    setState(() {
      _time = '07:30';
      _note = null;
    });
    await LocalPrefs.setString('brief_time', '07:30');
    await WidgetBridge.briefApply();
    Analytics.instance.track('brief', 'on');
  }

  Future<void> _pick(String t) async {
    setState(() => _time = t);
    await LocalPrefs.setString('brief_time', t);
    await WidgetBridge.briefApply();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckToggle(label: '아침 날씨 알림 받기', on: _time != null, onTap: _toggle),
        if (_note != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(_note!, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.5)),
          ),
        if (_time != null) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final t in kBriefTimes) PillChip(label: t, selected: t == _time, onTap: () => _pick(t))],
          ),
        ],
      ],
    );
  }
}
