import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import '../constants.dart';
import '../theme/botanical_theme.dart';
import '../services/day_service.dart';
import '../services/local_cache_service.dart';
import '../services/wake_service.dart';
import '../models/iot_models.dart';
import '../services/door_sensor_service.dart';
import '../services/routine_service.dart';
import '../services/data_audit_service.dart';
import '../services/write_queue_service.dart';
import '../services/safety_net_service.dart';
import '../services/claude_agent_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _day = DayService();
  final _wake = WakeService();
  static const _notifListenerChannel = MethodChannel('com.cheonhong.cheonhong_studio/notif_listener');
  bool _loading = true;
  String _wakeMode = 'sensor';
  bool _notifListenerEnabled = false;
  bool _safetyNetEnabled = true;
  bool _agentRunning = false;

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;
  Color get _accent => _dk ? BotanicalColors.lanternGold : BotanicalColors.primary;

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else { setState(fn); }
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      await _day.initialize().timeout(const Duration(seconds: 5), onTimeout: () {});
      _wakeMode = _wake.mode;
      _safetyNetEnabled = SafetyNetService().enabled;
      try {
        _notifListenerEnabled = await _notifListenerChannel.invokeMethod<bool>('isNotificationListenerEnabled') ?? false;
      } catch (_) {}
      try {
        _agentRunning = await ClaudeAgentService().isRunning();
      } catch (_) {}
    } catch (_) {
    } finally {
      _safeSetState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('관리', style: BotanicalTypo.heading(size: 18, color: _textMain)),
        backgroundColor: Colors.transparent, elevation: 0,
        foregroundColor: _textMain,
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ─── 자동화 ───
              _automationCard(),
              const SizedBox(height: 16),

              // ─── 기상 감지 ───
              _wakeDetectCard(),
              const SizedBox(height: 16),

              // ─── 안전망 (크리쳐 알림) ───
              _safetyNetCard(),
              const SizedBox(height: 16),

              // ─── 알림 감지 ───
              _notifListenerCard(),
              const SizedBox(height: 16),

              // ─── Agent ───
              _agentCard(),
              const SizedBox(height: 16),

              // ─── 앱 정보 ───
              _infoCard(),
              const SizedBox(height: 16),

              // ─── 쓰기 큐 ───
              _writeQueueCard(),
              const SizedBox(height: 16),

              // ─── 데이터 관리 ───
              _dataManagementCard(),
              const SizedBox(height: 40),
            ]),
          ),
    );
  }

  // ═══ 자동화 카드 ═══
  Widget _automationCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: _dk ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(14)),
          child: Icon(Icons.auto_awesome_rounded, size: 24, color: _accent),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('자동화', style: BotanicalTypo.body(
            size: 15, weight: FontWeight.w700, color: _textMain)),
          const SizedBox(height: 2),
          Text('도어센서, GPS, 안전망, 자동 루틴', style: BotanicalTypo.label(
            size: 11, color: _textMuted)),
        ])),
      ]),
    );
  }

  // ═══ 안전망 (크리쳐 확인 알림) ═══
  Widget _safetyNetCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF8B5CF6).withValues(alpha: _dk ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.pets_rounded, size: 24,
            color: Color(0xFF8B5CF6)),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('안전망 알림', style: BotanicalTypo.body(
            size: 15, weight: FontWeight.w700, color: _textMain)),
          const SizedBox(height: 2),
          Text('기상·외출·식사·홈데이 확인', style: BotanicalTypo.label(
            size: 11, color: _textMuted)),
        ])),
        Switch.adaptive(
          value: _safetyNetEnabled,
          activeTrackColor: const Color(0xFF8B5CF6),
          onChanged: (v) async {
            await SafetyNetService().setEnabled(v);
            _safeSetState(() => _safetyNetEnabled = v);
          },
        ),
      ]),
    );
  }

  // ═══ 기상 감지 카드 ═══
  Widget _wakeDetectCard() {
    final isSensor = _wakeMode == 'sensor';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFf59e0b).withValues(alpha: _dk ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.wb_sunny_rounded, size: 24,
              color: Color(0xFFf59e0b)),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('기상 감지', style: BotanicalTypo.body(
              size: 15, weight: FontWeight.w700, color: _textMain)),
            const SizedBox(height: 2),
            Text(isSensor ? '7시 이후 첫 문 열림 → 자동 기상' : '수동 버튼으로 기상 기록',
              style: BotanicalTypo.label(size: 11, color: _textMuted)),
          ])),
          // 모드 전환 칩
          GestureDetector(
            onTap: () async {
              final newMode = isSensor ? 'manual' : 'sensor';
              await _wake.setMode(newMode);
              _safeSetState(() => _wakeMode = newMode);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (isSensor ? const Color(0xFFf59e0b) : _textMuted).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12)),
              child: Text(isSensor ? '센서' : '수동',
                style: BotanicalTypo.label(size: 11, weight: FontWeight.w800,
                  color: isSensor ? const Color(0xFFf59e0b) : _textMuted)),
            ),
          ),
        ]),
        // 센서 모드 — DayState idle 기반 (시간대 무관)
        if (isSensor) ...[
          const SizedBox(height: 10),
          Row(children: [
            const SizedBox(width: 60),
            Text('7시 이전 문 열림은 무시 (새벽 화장실 등)',
              style: BotanicalTypo.label(size: 11, color: _textMuted)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _toolButton(
                emoji: '🚪', label: '문 열림 테스트',
                color: const Color(0xFFf59e0b),
                onTap: () async {
                  final prevState = _day.state;
                  final routine = RoutineService();
                  routine.forceState(DayState.idle);
                  SensorWakeDetector.resetForTest();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('🔄 idle → 문 열림 테스트 중...'),
                      duration: Duration(seconds: 1)));
                  await Future.delayed(const Duration(milliseconds: 300));
                  DoorSensorService().emitTestEvent(DoorState.open);
                  await Future.delayed(const Duration(seconds: 1));
                  if (!mounted) return;
                  final newState = _day.state;
                  final success = newState == DayState.awake;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(success
                      ? '✅ 기상 감지 성공! (idle → awake)'
                      : '❌ 미감지 (state: ${newState.name})'),
                    duration: const Duration(seconds: 3),
                    backgroundColor: success ? Colors.green : Colors.red));
                  if (prevState != DayState.idle) {
                    routine.forceState(prevState);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _toolButton(
                emoji: '🔍', label: '데이터 감사',
                color: const Color(0xFF10B981),
                onTap: () async {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('🔍 데이터 감사 실행 중...'),
                      duration: Duration(seconds: 2)));
                  final results = await DataAuditService().runForced();
                  if (!mounted) return;
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('데이터 감사 결과 (${results.length}건)'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: results.isEmpty
                          ? const Text('문제 없음')
                          : ListView(
                              shrinkWrap: true,
                              children: results.map((r) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(r, style: const TextStyle(fontSize: 12)),
                              )).toList(),
                            ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('확인')),
                      ],
                    ),
                  );
                },
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  // ═══ 알림 감지 카드 ═══
  Widget _notifListenerCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF10b981).withValues(alpha: _dk ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.notifications_active_rounded, size: 24,
              color: Color(0xFF10b981)),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('알림 감지', style: BotanicalTypo.body(
              size: 15, weight: FontWeight.w700, color: _textMain)),
            const SizedBox(height: 2),
            Text('Tuya 도어센서 기상 감지 + 화면 ON 추적',
              style: BotanicalTypo.label(size: 11, color: _textMuted)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (_notifListenerEnabled
                ? const Color(0xFF10b981)
                : BotanicalColors.error).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10)),
            child: Text(_notifListenerEnabled ? 'ON' : 'OFF',
              style: BotanicalTypo.label(size: 11, weight: FontWeight.w800,
                color: _notifListenerEnabled
                  ? const Color(0xFF10b981) : BotanicalColors.error)),
          ),
        ]),
        const SizedBox(height: 14),
        if (!_notifListenerEnabled)
          GestureDetector(
            onTap: () async {
              try {
                await _notifListenerChannel.invokeMethod('openNotificationListenerSettings');
              } catch (_) {}
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF10b981).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10b981).withValues(alpha: 0.2))),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.settings_rounded, size: 16,
                  color: const Color(0xFF10b981).withValues(alpha: 0.8)),
                const SizedBox(width: 8),
                Text('알림 접근 허용', style: BotanicalTypo.body(
                  size: 13, weight: FontWeight.w600,
                  color: const Color(0xFF10b981))),
              ]),
            ),
          )
        else
          Row(children: [
            const SizedBox(width: 60),
            Text('도어센서 알림 감지 중',
              style: BotanicalTypo.label(size: 11, color: _textMuted)),
          ]),
      ]),
    );
  }

  // ═══ Agent 카드 ═══
  Widget _agentCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: _dk ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.psychology_rounded, size: 24,
            color: Color(0xFF6366F1)),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Agent', style: BotanicalTypo.body(
            size: 15, weight: FontWeight.w700, color: _textMain)),
          const SizedBox(height: 2),
          Text(_agentRunning ? '앱 사용 감시 활성' : '접근성 서비스 비활성',
            style: BotanicalTypo.label(size: 11, color: _textMuted)),
        ])),
        GestureDetector(
          onTap: () async {
            if (!_agentRunning) {
              await ClaudeAgentService().openAccessibilitySettings();
            }
            // 돌아왔을 때 상태 재확인
            await Future.delayed(const Duration(seconds: 1));
            final running = await ClaudeAgentService().isRunning();
            _safeSetState(() => _agentRunning = running);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (_agentRunning
                ? const Color(0xFF6366F1)
                : _textMuted).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10)),
            child: Text(_agentRunning ? 'ON' : 'OFF',
              style: BotanicalTypo.label(size: 11, weight: FontWeight.w800,
                color: _agentRunning ? const Color(0xFF6366F1) : _textMuted)),
          ),
        ),
      ]),
    );
  }

  // ═══ 앱 정보 카드 ═══
  Widget _infoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.info_outline_rounded, size: 18, color: _textMuted),
          const SizedBox(width: 8),
          Text('앱 정보', style: BotanicalTypo.body(
            size: 14, weight: FontWeight.w700, color: _textMain)),
        ]),
        const SizedBox(height: 14),
        _infoRow('버전', 'v10.9.2'),
        const SizedBox(height: 8),
        _infoRow('Firebase UID', kUid),
        const SizedBox(height: 8),
        _infoRow('시험일', '2026-03-07 (5급 PSAT)'),
      ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(children: [
      Text(label, style: BotanicalTypo.label(
        size: 12, weight: FontWeight.w600, color: _textMuted)),
      const SizedBox(width: 12),
      Expanded(child: Text(value,
        style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: _textSub),
        textAlign: TextAlign.end)),
    ]);
  }

  // ═══ 도구 버튼 ═══
  Widget _toolButton({
    required String emoji, required String label,
    required Color color, required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: _dk ? 0.10 : 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(label, style: BotanicalTypo.label(
            size: 11, weight: FontWeight.w700, color: color)),
        ]),
      ),
    );
  }

  // ═══ 쓰기 큐 카드 ═══
  Widget _writeQueueCard() {
    final wq = FirestoreWriteQueue();
    final st = wq.stats;
    final errors = wq.getRecentErrors(limit: 5);
    final hasErrors = st['failed']! > 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.sync_rounded, size: 18, color: _textMuted),
          const SizedBox(width: 8),
          Text('쓰기 큐', style: BotanicalTypo.body(
            size: 14, weight: FontWeight.w700, color: _textMain)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (hasErrors ? BotanicalColors.error : const Color(0xFF10B981))
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8)),
            child: Text(hasErrors ? '${st['failed']} 실패' : '정상',
              style: BotanicalTypo.label(size: 10, weight: FontWeight.w700,
                color: hasErrors ? BotanicalColors.error : const Color(0xFF10B981))),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _statChip('대기', '${st['pending']}', const Color(0xFFf59e0b)),
          const SizedBox(width: 8),
          _statChip('성공', '${st['succeeded']}', const Color(0xFF10B981)),
          const SizedBox(width: 8),
          _statChip('실패', '${st['failed']}', BotanicalColors.error),
        ]),
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...errors.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${e['time']?.toString().substring(11, 19) ?? '?'} '
              '${e['docPath']?.toString().split('/').last ?? '?'} — '
              '${(e['fields'] as List?)?.join(', ') ?? '?'}',
              style: TextStyle(fontSize: 10, fontFamily: 'monospace',
                color: BotanicalColors.error.withValues(alpha: 0.7)),
            ),
          )),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              wq.clearErrors();
              _safeSetState(() {});
            },
            child: Text('에러 로그 초기화', style: BotanicalTypo.label(
              size: 11, weight: FontWeight.w600, color: _accent)),
          ),
        ],
      ]),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _dk ? 0.08 : 0.05),
        borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: BotanicalTypo.label(size: 10, color: _textMuted)),
        const SizedBox(width: 4),
        Text(value, style: BotanicalTypo.label(
          size: 12, weight: FontWeight.w800, color: color)),
      ]),
    );
  }

  // ═══ 데이터 관리 카드 ═══
  Widget _dataManagementCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.storage_rounded, size: 18, color: _textMuted),
          const SizedBox(width: 8),
          Text('데이터 관리', style: BotanicalTypo.body(
            size: 14, weight: FontWeight.w700, color: _textMain)),
        ]),
        const SizedBox(height: 14),

        // Hive 캐시 초기화
        _dangerAction(
          icon: Icons.cached_rounded,
          label: '로컬 캐시 초기화',
          desc: 'Hive 캐시 삭제 (Firestore에서 재동기화)',
          onTap: () => _confirmClear(
            title: '로컬 캐시 초기화',
            message: '모든 로컬 캐시가 삭제됩니다.\nFirestore에서 데이터를 다시 불러옵니다.\n\n계속하시겠습니까?',
            onConfirm: () async {
              try {
                await Hive.deleteBoxFromDisk('chstudio_cache');
                await LocalCacheService().init();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('캐시 초기화 완료. 앱을 재시작하세요.'),
                    backgroundColor: BotanicalColors.success));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('오류: $e'),
                    backgroundColor: BotanicalColors.error));
                }
              }
            },
          ),
        ),
      ]),
    );
  }

  Widget _dangerAction({
    required IconData icon, required String label,
    required String desc, required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: BotanicalColors.error.withValues(alpha: _dk ? 0.06 : 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BotanicalColors.error.withValues(alpha: 0.12))),
        child: Row(children: [
          Icon(icon, size: 20, color: BotanicalColors.error.withValues(alpha: 0.7)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: BotanicalTypo.body(
              size: 13, weight: FontWeight.w600, color: _textMain)),
            const SizedBox(height: 2),
            Text(desc, style: BotanicalTypo.label(size: 10, color: _textMuted)),
          ])),
          Icon(Icons.chevron_right_rounded, color: _textMuted, size: 18),
        ]),
      ),
    );
  }

  void _confirmClear({
    required String title, required String message,
    required VoidCallback onConfirm,
  }) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: _dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: BotanicalColors.error, size: 22),
        const SizedBox(width: 8),
        Text(title, style: BotanicalTypo.heading(size: 16, color: _textMain)),
      ]),
      content: Text(message, style: BotanicalTypo.body(
        size: 13, color: _textSub)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
          child: Text('취소', style: TextStyle(color: _textMuted))),
        ElevatedButton(
          onPressed: () { Navigator.pop(ctx); onConfirm(); },
          style: ElevatedButton.styleFrom(
            backgroundColor: BotanicalColors.error,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('초기화', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
      ],
    ));
  }

}
