import 'package:flutter/material.dart';
import '../theme/theme.dart';
import 'pages/today_page.dart';
import 'pages/records_page.dart';
import 'pages/plan_page.dart';
import 'pages/settings_page.dart';

/// DAILY HomeShell · 3탭 v13.1 (사용자 5/5 14:35 명시 = 일기 X / 더 단순)
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
  ];

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: DailyV14.bg,
        elevation: 0,
        title: const Text('Daily', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: _openSettings,
            tooltip: '설정',
          ),
        ],
      ),
      body: IndexedStack(index: _idx, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        backgroundColor: DailyV14.bg,
        indicatorColor: DailyV14.peachSoft,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.check_box_outlined), selectedIcon: Icon(Icons.check_box), label: '오늘'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: '기록'),
          NavigationDestination(icon: Icon(Icons.timeline_outlined), selectedIcon: Icon(Icons.timeline), label: '계획'),
        ],
      ),
    );
  }
}
