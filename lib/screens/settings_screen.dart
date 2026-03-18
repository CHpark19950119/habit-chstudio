import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import '../constants.dart';
import '../theme/botanical_theme.dart';
import '../services/day_service.dart';
import '../services/local_cache_service.dart';
import '../services/sleep_detect_service.dart';
import '../services/wake_service.dart';
import '../models/iot_models.dart';
import '../services/door_sensor_service.dart';
import '../services/routine_service.dart';
import '../services/data_audit_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nfc = DayService();
  final _sleepDetect = SleepDetectService();
  final _wake = WakeService();
  static const _bixbyChannel = MethodChannel('com.cheonhong.cheonhong_studio/bixby');
  bool _loading = true;
  bool _sleepDetectEnabled = false;
  String _wakeMode = 'sensor';
  bool _notifListenerEnabled = false;

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
      await _nfc.initialize().timeout(const Duration(seconds: 5), onTimeout: () {});
      _sleepDetectEnabled = _sleepDetect.enabled;
      _wakeMode = _wake.mode;
      try {
        _notifListenerEnabled = await _bixbyChannel.invokeMethod<bool>('isNotificationListenerEnabled') ?? false;
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
              // ─── NFC & 자동화 진입 ───
              _nfcEntryCard(),
              const SizedBox(height: 16),

              // ─── 기상 감지 ───
              _wakeDetectCard(),
              const SizedBox(height: 16),

              // ─── 수면 자동 감지 ───
              _sleepDetectCard(),
              const SizedBox(height: 16),

              // ─── 빅스비 연동 ───
              _bixbyCard(),
              const SizedBox(height: 16),

              // ─── 앱 정보 ───
              _infoCard(),
              const SizedBox(height: 16),

              // ─── 데이터 관리 ───
              _dataManagementCard(),
              const SizedBox(height: 40),
            ]),
          ),
    );
  }

  // ═══ 자동화 카드 ═══
  Widget _nfcEntryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: _accent.withOpacity(_dk ? 0.12 : 0.08),
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
              color: const Color(0xFFf59e0b).withOpacity(_dk ? 0.12 : 0.08),
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
                color: (isSensor ? const Color(0xFFf59e0b) : _textMuted).withOpacity(0.12),
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
            const SizedBox(width: 60),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFf59e0b).withOpacity(0.15),
                foregroundColor: const Color(0xFFf59e0b),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Text('🚪', style: TextStyle(fontSize: 14)),
              label: Text('문 열림 테스트',
                style: BotanicalTypo.label(size: 11, weight: FontWeight.w700,
                  color: const Color(0xFFf59e0b))),
              onPressed: () async {
                final prevState = _nfc.state;
                final routine = RoutineService();
                // ① 강제 idle + 기상기록 리셋
                routine.forceState(DayState.idle);
                SensorWakeDetector.resetForTest();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🔄 idle → 문 열림 테스트 중...'),
                    duration: Duration(seconds: 1)));
                await Future.delayed(const Duration(milliseconds: 300));
                // ② 직접 이벤트 발행 (Firestore/디바운스 우회)
                DoorSensorService().emitTestEvent(DoorState.open);
                // ③ 결과 확인
                await Future.delayed(const Duration(seconds: 1));
                if (!mounted) return;
                final newState = _nfc.state;
                final success = newState == DayState.awake;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(success
                    ? '✅ 기상 감지 성공! (idle → awake)'
                    : '❌ 미감지 (state: ${newState.name})'),
                  duration: const Duration(seconds: 3),
                  backgroundColor: success ? Colors.green : Colors.red));
                // ★ 테스트 후 항상 원래 상태 복원
                if (prevState != DayState.idle) {
                  routine.forceState(prevState);
                }
              },
            ),
          ]),
          const SizedBox(height: 12),
          // ── 데이터 감사 ──
          Row(children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981).withOpacity(_dk ? 0.12 : 0.08),
                foregroundColor: const Color(0xFF10B981),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Text('🔍', style: TextStyle(fontSize: 14)),
              label: Text('데이터 감사',
                style: BotanicalTypo.label(size: 11, weight: FontWeight.w700,
                  color: const Color(0xFF10B981))),
              onPressed: () async {
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
          ]),
        ],
      ]),
    );
  }

  // ═══ 수면 자동 감지 카드 ═══
  Widget _sleepDetectCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF6366f1).withOpacity(_dk ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.bedtime_rounded, size: 24,
            color: Color(0xFF6366f1)),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('수면 자동 감지', style: BotanicalTypo.body(
            size: 15, weight: FontWeight.w700, color: _textMain)),
          const SizedBox(height: 2),
          Text('야간 화면 30분 꺼짐 → 취침 확인 알림', style: BotanicalTypo.label(
            size: 11, color: _textMuted)),
        ])),
        Switch.adaptive(
          value: _sleepDetectEnabled,
          activeColor: const Color(0xFF6366f1),
          onChanged: (v) async {
            await _sleepDetect.setEnabled(v);
            _safeSetState(() => _sleepDetectEnabled = v);
          },
        ),
      ]),
    );
  }

  // ═══ 빅스비 연동 카드 ═══
  Widget _bixbyCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF10b981).withOpacity(_dk ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.notifications_active_rounded, size: 24,
              color: Color(0xFF10b981)),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('빅스비 연동', style: BotanicalTypo.body(
              size: 15, weight: FontWeight.w700, color: _textMain)),
            const SizedBox(height: 2),
            Text('알림 감지 → 자동 외출/귀가 (20분 확정)',
              style: BotanicalTypo.label(size: 11, color: _textMuted)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (_notifListenerEnabled
                ? const Color(0xFF10b981)
                : BotanicalColors.error).withOpacity(0.12),
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
                await _bixbyChannel.invokeMethod('openNotificationListenerSettings');
              } catch (_) {}
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF10b981).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10b981).withOpacity(0.2))),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.settings_rounded, size: 16,
                  color: const Color(0xFF10b981).withOpacity(0.8)),
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
            Text('CHSTUDIO_OUT / CHSTUDIO_HOME 알림 감지 중',
              style: BotanicalTypo.label(size: 11, color: _textMuted)),
          ]),
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
          color: BotanicalColors.error.withOpacity(_dk ? 0.06 : 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BotanicalColors.error.withOpacity(0.12))),
        child: Row(children: [
          Icon(icon, size: 20, color: BotanicalColors.error.withOpacity(0.7)),
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
