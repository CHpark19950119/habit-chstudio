// DAILY (CHSTUDIO) — 일상 · 수면 · 심리 · life_logs 관리
// scratch 재작성 2026-04-24 23:30 · 합의 28 Phase 8
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'app/app.dart';
import 'data/deep_link_service.dart';
import 'data/auto_record_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR', null);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 사용자 지시 (2026-04-28 10:54): 자동 기록 이관.
  // 1) deep link → AutoRecordService 분기
  // 2) 앱 실행 자체 = 07-15시 wake 후보 등재
  await DeepLinkService.init();
  // 비동기 fire-and-forget: 첫 화면 그리기 차단 X.
  unawaited(AutoRecordService.autoWakeCandidate());

  runApp(const DailyApp());
}

void unawaited(Future<void> _) {}
