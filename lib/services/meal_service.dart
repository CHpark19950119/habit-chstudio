import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../utils/study_date_utils.dart';

/// MealService — 식사 독립 추적
class MealService extends ChangeNotifier {
  static final MealService _instance = MealService._internal();
  factory MealService() => _instance;
  MealService._internal();

  bool _isMealing = false;
  bool _initialized = false;

  bool get isMealing => _isMealing;

  void _log(String msg) => debugPrint('[Meal] $msg');

  String _studyDate([DateTime? dt]) => StudyDateUtils.todayKey(dt);

  // ═══════════════════════════════════════════
  //  초기화
  // ═══════════════════════════════════════════

  Future<void> initialize() async {
    if (_initialized) return;
    await _restoreState();
    _initialized = true;
  }

  // ═══════════════════════════════════════════
  //  식사 상태 토글
  // ═══════════════════════════════════════════

  void startMeal() {
    _isMealing = true;
    _saveState();
    notifyListeners();
  }

  void endMeal() {
    _isMealing = false;
    _saveState();
    notifyListeners();
  }

  /// 열린 식사 닫기 (공부 종료/취침 시 호출)
  /// meals 리스트를 수정하고 isMealing을 false로 변경
  /// 반환: 수정된 meals 리스트
  List<MealEntry> closePendingMeals(String timeStr, List<MealEntry> meals) {
    if (!_isMealing) return meals;
    final updated = List<MealEntry>.from(meals);
    final openIdx = updated.lastIndexWhere((m) => m.end == null);
    if (openIdx >= 0) {
      updated[openIdx] = updated[openIdx].withEnd(timeStr);
    }
    _isMealing = false;
    _saveState();
    notifyListeners();
    return updated;
  }

  // ═══════════════════════════════════════════
  //  저장/복원
  // ═══════════════════════════════════════════

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('nfc_is_mealing', _isMealing);
  }

  Future<void> saveState() => _saveState();

  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('nfc_state_date');
    if (savedDate == _studyDate()) {
      _isMealing = prefs.getBool('nfc_is_mealing') ?? false;
      _log('복원: mealing=$_isMealing');
    } else {
      _isMealing = false;
    }
  }
}
