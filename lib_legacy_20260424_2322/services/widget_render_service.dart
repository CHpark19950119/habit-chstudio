import 'package:flutter/material.dart';

/// Home widget — placeholder after study code removal.
/// D-Day widget was study-specific; daily-life widget TBD.
class WidgetRenderService {
  static final WidgetRenderService _instance = WidgetRenderService._();
  factory WidgetRenderService() => _instance;
  WidgetRenderService._();

  Future<void> updateWidget() async {
    // no-op: study D-Day widget removed in app separation (2026-04-17)
    debugPrint('[Widget] skipped — no daily widget configured');
  }
}
