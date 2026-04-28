import 'package:flutter/material.dart';
import '../theme/theme.dart';
import 'pages/today_page.dart';
import 'pages/records_page.dart';
import 'pages/plan_page.dart';
import 'pages/settings_page.dart';

/// DAILY HomeShell · 4탭 재설계 (사용자 지시 23:22)
/// 오늘 (일상 현황) · 기록 (life_logs 상세) · 인사이트 (주간 패턴) · 설정
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _idx = 0;
  static const _pages = <Widget>[
    TodayPage(),
    RecordsPage(),
    PlanPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _idx, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        backgroundColor: DailyPalette.paper,
        indicatorColor: DailyPalette.goldSurface,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), selectedIcon: Icon(Icons.wb_sunny), label: '오늘'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: '캘린더'),
          NavigationDestination(icon: Icon(Icons.edit_calendar_outlined), selectedIcon: Icon(Icons.edit_calendar), label: '계획'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '설정'),
        ],
      ),
    );
  }
}
