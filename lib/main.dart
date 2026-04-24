// DAILY (CHSTUDIO) — 일상 · 수면 · 심리 · life_logs 관리
// scratch 재작성 2026-04-24 23:30 · 합의 28 Phase 8
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR', null);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const DailyApp());
}
