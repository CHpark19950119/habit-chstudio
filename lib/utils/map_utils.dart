// ★ AUDIT FIX: P-03 — _setNestedValue 유틸 통합 (3곳 → 1곳)
// ★ AUDIT FIX: B-01 — FieldValue.increment toString 파싱 제거, 명시적 delta 사용

/// dot-notation path로 중첩 Map에 값을 설정하는 유틸리티.
/// FieldValue.increment 등은 지원하지 않음 — 호출부에서 delta를 계산해 일반 값으로 전달할 것.
class MapUtils {
  MapUtils._();

  /// [map]에 [dotPath]로 지정된 경로에 [value]를 설정한다.
  /// 예: setNestedValue(map, 'a.b.c', 42) → map['a']['b']['c'] = 42
  ///
  /// [localDelta]가 주어지면 기존 값에 delta를 더한 결과를 설정한다 (FieldValue.increment 대체).
  static void setNestedValue(
    Map<String, dynamic> map,
    String dotPath,
    dynamic value, {
    num? localDelta,
  }) {
    // ★ AUDIT FIX: B-01 — localDelta가 있으면 기존 값에 더해서 설정
    if (localDelta != null) {
      final existing = getNestedValue(map, dotPath);
      final base = existing is num ? existing : 0;
      value = base + localDelta;
    }

    final parts = dotPath.split('.');
    if (parts.length == 1) {
      map[parts.first] = value;
      return;
    }

    Map<String, dynamic> current = map;
    for (int i = 0; i < parts.length - 1; i++) {
      final existing = current[parts[i]];
      if (existing is Map<String, dynamic>) {
        current = existing;
      } else if (existing is Map) {
        // 타입이 안 맞는 Map → in-place 교체 후 참조 유지
        final typed = <String, dynamic>{};
        for (final e in existing.entries) {
          typed[e.key.toString()] = e.value;
        }
        current[parts[i]] = typed;
        current = typed;
      } else {
        final fresh = <String, dynamic>{};
        current[parts[i]] = fresh;
        current = fresh;
      }
    }
    current[parts.last] = value;
  }

  /// dot-notation path로 중첩 Map에서 값을 읽는다.
  static dynamic getNestedValue(Map<String, dynamic> map, String dotPath) {
    dynamic current = map;
    for (final part in dotPath.split('.')) {
      if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }
}
