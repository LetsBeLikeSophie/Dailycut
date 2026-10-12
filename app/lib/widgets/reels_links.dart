import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'components.dart';

/// 릴스·숏폼에서 뜨는 음악: 인스타그램 릴스는 순위를 공개하지 않고 공식 API도 없어서, 앱 안에 순위를 넣지 않고
/// 순위를 볼 수 있는 바깥 서비스로 바로 보내는 통로만 둠(각 서비스의 약관을 지키려고 가져오지 않음).
class ReelsLinksSection extends StatelessWidget {
  const ReelsLinksSection({super.key});

  static const _links = [
    ('유튜브 인기 쇼츠 음악', '유튜브 차트 · 한국 일별', 'https://charts.youtube.com/charts/TopShortsSongs/kr'),
    ('틱톡 인기 음악', '틱톡 크리에이티브 센터 · 지역을 한국으로', 'https://ads.tiktok.com/business/creativecenter/inspiration/popular/music/pc/en'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListSection(
      title: '릴스·숏폼에서 뜨는 음악',
      trailing: '바깥 사이트로 이동',
      children: [
        for (final (name, sub, url) in _links)
          ListLine(
            name: name,
            sub: sub,
            leading: const SizedBox(width: 24, child: Icon(Icons.north_east, size: 18)),
            onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text('인스타그램 릴스는 순위를 공개하지 않아서, 순위가 있는 서비스로 연결해 드려요.', style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.6)),
        ),
      ],
    );
  }
}
