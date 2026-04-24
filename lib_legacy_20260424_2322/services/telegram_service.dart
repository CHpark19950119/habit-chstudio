import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// 텔레그램 서비스
/// - sendNfc: NFC 활동 알림 (양쪽 모두 전송)
/// - sendToMe: 나에게 시스템/배포/알람 알림
class TelegramService {
  static final TelegramService _instance = TelegramService._internal();
  factory TelegramService() => _instance;
  TelegramService._internal();

  // ★ AUDIT FIX: S-01 — TODO: --dart-define-from-file 또는 환경변수로 이동
  // 빌드: flutter build apk --dart-define-from-file=.env.json
  static const _myToken  = String.fromEnvironment('TG_MY_TOKEN', defaultValue: '8253264860:AAE8mKRSNN31ubdOvk4KPghOYcOmnXg0v50');
  static const _myChatId = String.fromEnvironment('TG_MY_CHAT', defaultValue: '8724548311');
  static const _gfToken  = String.fromEnvironment('TG_GF_TOKEN', defaultValue: '8613977898:AAEuuoTVARS-a9nrDp85NWHHOYM0lRvmZmc');
  static const _gfChatId = String.fromEnvironment('TG_GF_CHAT', defaultValue: '8624466505');

  // ─── 나에게 (배포 알림 등) ───
  Future<void> sendToMe(String message) async {
    await _send(_myToken, _myChatId, message);
  }

  // ─── NFC 활동 알림 (양쪽 모두) ───
  Future<void> sendNfc(String message) async {
    await Future.wait([
      _send(_myToken, _myChatId, message),
      _send(_gfToken, _gfChatId, message),
    ]);
  }

  Future<void> _send(String token, String chatId, String text) async {
    try {
      await http.post(
        Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({'chat_id': chatId, 'text': text}),
      ).timeout(const Duration(seconds: 10));
      debugPrint('[Telegram] sent: $text');
    } catch (e) {
      debugPrint('[Telegram] send failed: $e');
    }
  }
}
