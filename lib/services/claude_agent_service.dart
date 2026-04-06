import 'package:flutter/services.dart';

/// ClaudeAgentService — 접근성 서비스 기반 폰 감시/제어 Flutter 래퍼
///
/// Kotlin ClaudeAgentService와 MethodChannel "claude_agent"로 통신.
/// 싱글톤 패턴.
class ClaudeAgentService {
  ClaudeAgentService._();
  static final ClaudeAgentService _instance = ClaudeAgentService._();
  factory ClaudeAgentService() => _instance;

  static const _channel = MethodChannel('com.cheonhong.cheonhong_studio/claude_agent');

  /// 접근성 서비스 실행 중인지 확인
  Future<bool> isRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isRunning') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 접근성 설정 화면 열기 (사용자가 수동으로 활성화)
  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  /// 현재 상태 조회
  Future<Map<String, dynamic>> getStatus() async {
    try {
      final result = await _channel.invokeMethod<Map>('getStatus');
      if (result == null) return {'running': false};
      return Map<String, dynamic>.from(result);
    } catch (_) {
      return {'running': false};
    }
  }

  /// 오버레이 경고 표시
  Future<bool> showOverlay(String message, {int durationMs = 8000}) async {
    try {
      return await _channel.invokeMethod<bool>('showOverlay', {
        'message': message,
        'duration': durationMs,
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 화면 텍스트 읽기
  Future<String> getScreenText() async {
    try {
      return await _channel.invokeMethod<String>('getScreenText') ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 앱 사용 로그 Firestore 기록
  Future<void> flushLog() async {
    try {
      await _channel.invokeMethod('flushLog');
    } catch (_) {}
  }
}
