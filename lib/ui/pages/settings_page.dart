import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyPalette.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            const Text('설정', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: DailyPalette.ink)),
            const SizedBox(height: DailySpace.xl),
            _row('앱 버전', 'DAILY v2.0.0 (scratch 2026-04-24)'),
            _row('Firestore', 'cheonhong-studio'),
            _row('UID', 'sJ8Pxusw9gR0tNR44RhkIge7OiG2'),
            _row('역할', '일상·수면·심리·life_logs (공부는 STUDY)'),
            _row('HB 텔레그램', '@Chhabitbot_bot'),
            const SizedBox(height: DailySpace.xl),
            const Text('데이터는 HB 텔레그램으로 기입하세요. 앱은 조회·시각화 전용.',
                style: TextStyle(fontSize: 11, color: DailyPalette.ash)),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(DailySpace.md),
        decoration: BoxDecoration(
          color: DailyPalette.card,
          borderRadius: BorderRadius.circular(DailySpace.radius),
          border: Border.all(color: DailyPalette.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(k, style: const TextStyle(fontSize: 12, color: DailyPalette.ash))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13, color: DailyPalette.ink))),
          ],
        ),
      );
}
