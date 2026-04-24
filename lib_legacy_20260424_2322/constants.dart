/// 앱 전역 상수
// ★ AUDIT FIX: S-01 — TODO: --dart-define-from-file로 이동 (현재 defaultValue로 하위 호환 유지)
// ★ AUDIT FIX: S-03 — TODO: Firebase Anonymous Auth 도입 후 동적 UID로 교체
const String kUid = String.fromEnvironment('FIREBASE_UID', defaultValue: 'sJ8Pxusw9gR0tNR44RhkIge7OiG2');
const String kStudyDoc = 'users/$kUid/data/study';
const String kTodayDoc = 'users/$kUid/data/today';
const String kIotDoc = 'users/$kUid/data/iot';
const String kLiveFocusDoc = 'users/$kUid/data/liveFocus';
const String kMetaDoc = 'users/$kUid/data/meta';
