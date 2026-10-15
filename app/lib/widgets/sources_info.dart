import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../analytics.dart';
import '../theme.dart';
import 'ad_slot.dart';

/// 앱이 쓰는 공공데이터·외부 데이터 출처(이용 조건 표기 포함). 화면마다 출처를 길게 적는 대신
/// 작은 ⓘ → 이 시트에서 한 번에 보여줌. 새 데이터를 붙이면 여기에 한 줄 추가.
const kAllSources = <(String, String)>[
  ('기상청', '단기예보·중기예보·초단기실황 (공공누리 1유형: 출처표시)'),
  ('한국환경공단 에어코리아', '실시간 대기오염 측정값 (공공누리 3유형: 출처표시·변경금지)'),
  ('한국천문연구원', '특일(공휴일)·24절기·일출몰 정보'),
  ('한국농수산식품유통공사(aT)', '농축수산물 소매가격(상품 등급 평균)'),
  ('행정안전부 공공서비스(혜택) 정보', '정부24·보조금24의 지원 서비스 정보와 지원조건'),
  ('한국부동산원 청약홈', 'APT·무순위·오피스텔·공공지원 민간임대 분양공고'),
  ('국토교통부 마이홈포털 · 한국토지주택공사', '공공임대 입주자 모집공고'),
  ('서민금융진흥원', '대출상품 한눈에(서민금융 상품 정보)'),
  ('식품의약품안전처 식품영양성분DB', '장보기 품목의 열량·영양(생것, 100g 기준)'),
  ('축산물품질평가원', '축산물유통정보 — 소·돼지 부위별 소비자가격(평년 대비)'),
  ('한국관광공사 TourAPI', '축제·행사 정보, 시장 사진'),
  ('한국관광공사 관광지 집중률 방문자 추이 예측', '관광지별 예상 방문 집중도(오늘부터 약 30일 뒤까지)'),
  ('한국문화정보원 문화포털', '전시·공연 정보(사진은 쓰지 않음)'),
  ('소상공인시장진흥공단', '전통시장 현황'),
  ('Wikimedia Commons', '채소·과일 사진 (작가·라이선스는 사진 아래에 표시)'),
];

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
            if (current != null) ...[
              const SizedBox(height: 16),
              Text('이 화면', style: AppTheme.subheading),
              const SizedBox(height: 6),
              Text(current, style: const TextStyle(fontSize: 16, height: 1.6)),
              const SizedBox(height: 4),
              const Text('분홍색으로 표시된 부분은 아직 예시 데이터예요.', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            ],
            const SizedBox(height: 22),
            Text('데일리컷이 쓰는 데이터', style: AppTheme.subheading),
            const SizedBox(height: 8),
            for (final (name, desc) in kAllSources)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
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
                '화면에 "광고"라고 표시된 배너는 카카오 애드핏이 제공해요. 광고 사업자가 광고 제공을 위해 기기 정보나 쿠키를 사용할 수 있고, 이는 위 익명 통계와 별개예요.',
                style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.6),
              ),
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
      onTap: () => launchUrl(Uri.base.resolve(page), mode: LaunchMode.externalApplication),
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
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('익명 통계 보내기', style: TextStyle(fontSize: 13)),
      value: _on,
      activeThumbColor: AppColors.ink,
      onChanged: (v) {
        setState(() => _on = v);
        Analytics.instance.setEnabled(v);
      },
    );
  }
}
