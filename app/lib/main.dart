import 'package:flutter/material.dart';
import 'api_client.dart';
import 'screens/today_screen.dart';
import 'screens/section_screens.dart';
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

  static const _tabs = ['투데이', '생활', '문화', '머니', 'AI'];

  @override
  Widget build(BuildContext context) {
    final screens = [
      TodayScreen(api: _api),
      marketScreen(_api),
      cultureScreen(_api),
      moneyScreen(_api),
      aiScreen(_api),
    ];

    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _index, children: screens)),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
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
                      onTap: () => setState(() => _index = i),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _tabs[i],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: i == _index ? FontWeight.w700 : FontWeight.w400,
                              color: i == _index ? AppColors.ink : AppColors.inkSoft,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (i == _index) Container(width: 4, height: 4, color: AppColors.ink),
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
