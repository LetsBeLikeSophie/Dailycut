import 'package:flutter/material.dart';
import 'api_client.dart';
import 'boot.dart';
import 'location_flow.dart';
import 'widgets/swipe.dart';
import 'screens/today_screen.dart';
import 'screens/section_screens.dart';
import 'analytics.dart';
import 'local_prefs.dart';
import 'my_basket.dart';
import 'widgets/support_profile.dart';
import 'region.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 저장된 설정(지역·장바구니·내 조건·마지막 구역)을 첫 프레임 전에 읽어 둠 → 화면이 기본값으로 그렸다가 다시 그리지 않음
  await LocalPrefs.init();
  MyBasket.instance.loadSync();
  SupportProfile.instance.loadSync();
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
  // 2026-10-15: 5개 탭을 시작과 동시에 다 만들면 생활·문화 요청이 투데이 요청과 겹쳐 첫 화면이 밀림 → 투데이만 먼저,
  // 첫 화면이 그려진 뒤 나머지를 0.7초 간격으로 뒤에서 만들어 둠(탭을 먼저 누르면 그 탭은 바로 만듦).
  final Set<int> _visited = {0};

  // 2026-09-30: 날씨를 생활에서 빼되, 별도 탭/전용 화면까지는 필요 없고
  // 투데이 카드로만 있으면 충분하다는 피드백 — 탭은 원래 5개로 되돌림
  // (Section.weather 자체는 투데이 카드 테마용으로 theme.dart에 남겨둠).
  // 2026-10-14: AI 탭은 아직 전부 예시 데이터라 배포본에선 뺌(개발 때만 `--dart-define=SHOW_AI_TAB=true`).
  static const _showAi = bool.fromEnvironment('SHOW_AI_TAB');
  static const _tabs = ['투데이', '생활', '문화', '나들이', '혜택', if (_showAi) 'AI'];
  static const _tabKeys = ['today', 'life', 'culture', 'place', 'money', if (_showAi) 'ai'];

  @override
  void initState() {
    super.initState();
    // 지역(시도)을 정함: 저장된 선택 → 위치 권한(허용 시 내 시도) → 기본 서울
    RegionStore.instance.init(_api);
    Analytics.instance.track('tab_view', 'today');
    kFirstScreenReady.addListener(_warmOtherTabs);
    swipeToTab = _swipeTab;
  }

  @override
  void dispose() {
    kFirstScreenReady.removeListener(_warmOtherTabs);
    swipeToTab = null;
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      _visited.add(i);
    });
    Analytics.instance.track('tab_view', _tabKeys[i]);
  }

  void _swipeTab(int step) {
    final next = _index + step;
    if (next >= 0 && next < _tabs.length) _select(next);
  }

  void _warmOtherTabs() {
    if (!kFirstScreenReady.value) return;
    // 첫 화면을 먼저 보여 준 뒤(0.8초) 위치 안내를 띄움 — 켜자마자 권한 창이 불쑥 뜨지 않게
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (mounted) offerLocationOnFirstRun(context);
    });
    for (var i = 1; i < _tabs.length; i++) {
      Future<void>.delayed(Duration(milliseconds: 700 * i), () {
        if (mounted) setState(() => _visited.add(i));
      });
    }
  }

  /// 지역에 따라 달라지는 화면(투데이·생활·문화)은 지역이 바뀌면 새로 만들어서 다시 받아옴.
  /// [keyed]가 false면 지역이 바뀌어도 화면을 새로 만들지 않고 그 화면이 스스로 새 지역을 받게 함(투데이: 로딩 원 깜빡임 방지).
  Widget _regional(Widget Function(Region) build, {bool keyed = true}) {
    final store = RegionStore.instance;
    if (!store.ready) return const Center(child: CircularProgressIndicator());
    if (!keyed) return build(store.current);
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
    final builders = <Widget Function()>[
      () => _regional((r) => TodayScreen(api: _api, region: r), keyed: false),
      () => _regional((r) => marketScreen(_api, r, context)),
      () => _regional((r) => cultureScreen(_api, r, context)),
      () => _regional((r) => placesScreen(_api, r, context)),
      () => _regional((r) => benefitsScreen(_api, r, context)),
      if (_showAi) () => aiScreen(_api),
    ];
    final screens = [for (var i = 0; i < builders.length; i++) _visited.contains(i) ? builders[i]() : const SizedBox.shrink()];

    return Scaffold(
      // 옆으로 밀면 이웃 탭(기본 동작). 달력·하위 구분 본문은 안쪽에서 먼저 받음(widgets/swipe.dart)
      body: SafeArea(child: SwipeDetector(onSwipe: _swipeTab, child: IndexedStack(index: _index, children: screens))),
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
                      onTap: () => _select(i),
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
