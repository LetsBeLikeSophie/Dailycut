import 'package:flutter/material.dart';
import 'api_client.dart';
import 'screens/today_screen.dart';
import 'screens/section_screens.dart';
import 'analytics.dart';
import 'region.dart';
import 'theme.dart';

void main() {
  runApp(const DailyCutApp());
}

class DailyCutApp extends StatelessWidget {
  const DailyCutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '데일리컷',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  final _api = ApiClient();
  int _index = 0;

  // 2026-09-30: 날씨를 생활에서 빼되, 별도 탭/전용 화면까지는 필요 없고
  // 투데이 카드로만 있으면 충분하다는 피드백 — 탭은 원래 5개로 되돌림
  // (Section.weather 자체는 투데이 카드 테마용으로 theme.dart에 남겨둠).
  static const _tabs = ['투데이', '생활', '문화', '재테크', 'AI'];
  static const _tabKeys = ['today', 'life', 'culture', 'money', 'ai'];

  @override
  void initState() {
    super.initState();
    // 지역(시도)을 정함: 저장된 선택 → 위치 권한(허용 시 내 시도) → 기본 서울
    RegionStore.instance.init(_api);
    Analytics.instance.track('tab_view', 'today');
  }

  /// 지역에 따라 달라지는 화면(투데이·생활·문화)은 지역이 바뀌면 새로 만들어서 다시 받아옴.
  Widget _regional(Widget Function(Region) build) {
    final store = RegionStore.instance;
    if (!store.ready) return const Center(child: CircularProgressIndicator());
    return KeyedSubtree(key: ValueKey('${store.current.code}/${store.current.sgg ?? ''}'), child: build(store.current));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RegionStore.instance,
      builder: (context, _) => _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    final screens = [
      _regional((r) => TodayScreen(api: _api, region: r)),
      _regional((r) => marketScreen(_api, r, context)),
      _regional((r) => cultureScreen(_api, r, context)),
      moneyScreen(_api),
      aiScreen(_api),
    ];

    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _index, children: screens)),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hair)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _index = i);
                        Analytics.instance.track('tab_view', _tabKeys[i]);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _tabs[i],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: i == _index ? FontWeight.w700 : FontWeight.w400,
                              color: i == _index ? AppColors.ink : AppColors.inkSoft,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (i == _index) Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
