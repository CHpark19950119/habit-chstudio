// DeepLinkService — cheonhong:// scheme 받아 AutoRecordService 분기.
// app_links 패키지 사용 (pubspec ^7.0.0).
// 사용자 지시 (2026-04-28 10:54): 자동 기록 이관.
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'auto_record_service.dart';

class DeepLinkService {
  DeepLinkService._();
  static final _appLinks = AppLinks();
  static StreamSubscription<Uri>? _sub;

  /// main.dart 진입점에서 호출. cold start initial link + runtime stream 모두 처리.
  static Future<void> init() async {
    // cold start
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) await _handle(initial);
    } catch (e) {
      debugPrint('[DeepLink] initial err: $e');
    }
    // runtime stream
    _sub?.cancel();
    _sub = _appLinks.uriLinkStream.listen(_handle, onError: (e) {
      debugPrint('[DeepLink] stream err: $e');
    });
  }

  static Future<void> _handle(Uri uri) async {
    if (uri.scheme != 'cheonhong') return;
    debugPrint('[DeepLink] $uri');
    try {
      switch (uri.host) {
        case 'wake':
          await AutoRecordService.recordWake(note: 'deep link');
          break;
        case 'sleep':
          await AutoRecordService.recordSleep(note: 'deep link');
          break;
        case 'meal':
          await AutoRecordService.toggleMeal();
          break;
        case 'outing':
          final dest = uri.queryParameters['destination'];
          final mode = uri.queryParameters['mode'];
          await AutoRecordService.toggleOuting(destination: dest, mode: mode);
          break;
        case 'focus':
          final subject = uri.queryParameters['subject'] ?? '기타';
          final mode = uri.queryParameters['mode'] ?? 'study';
          await AutoRecordService.appendEvent(
            tag: 'focus',
            note: 'subject=$subject mode=$mode',
          );
          break;
        case 'app':
          // tab 전환 등 UI navigation. 기록 X.
          break;
        case 'order':
          // 결제 화면 이동. 기록 X.
          break;
        default:
          debugPrint('[DeepLink] unknown host: ${uri.host}');
      }
    } catch (e) {
      debugPrint('[DeepLink] handler err: $e');
    }
  }

  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
