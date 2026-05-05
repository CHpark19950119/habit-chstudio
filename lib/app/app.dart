import 'package:flutter/material.dart';
import '../theme/theme.dart';
import '../ui/home_shell.dart';
import '../ui/onboarding/onboarding_screen.dart';

class DailyApp extends StatelessWidget {
  const DailyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily',
      debugShowCheckedModeBanner: false,
      theme: buildDailyTheme(brightness: Brightness.light),
      themeMode: ThemeMode.light,
      home: const _RootGate(),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate();
  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool? _showOnboarding;

  @override
  void initState() {
    super.initState();
    shouldShowDailyOnboarding().then((show) {
      if (mounted) setState(() => _showOnboarding = show);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_showOnboarding!) {
      return OnboardingScreen(onDone: () => setState(() => _showOnboarding = false));
    }
    return const HomeShell();
  }
}

/// 사용자 UID 단일 소스 · Firestore users/{uid}/... 경로 베이스
const String kUid = 'sJ8Pxusw9gR0tNR44RhkIge7OiG2';
