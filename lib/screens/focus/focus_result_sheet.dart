import 'package:flutter/material.dart';
import '../../theme/botanical_theme.dart';
import '../../models/models.dart';

/// 세션 완료 결과 다이얼로그
void showFocusResultDialog({
  required BuildContext context,
  required FocusCycle cycle,
  required bool dk,
  required Color textMain,
  required Color textSub,
  required Color textMuted,
}) {
  final c = BotanicalColors.subjectColor(cycle.subject);

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dCtx) => AlertDialog(
      backgroundColor: dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        const Text('🎉', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('세션 완료!', style: BotanicalTypo.heading(size: 20, color: textMain)),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Text('순공 ${cycle.effectiveMin}분', style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.w800, color: c)),
            const SizedBox(height: 8),
            Text('${SubjectConfig.subjects[cycle.subject]?.emoji ?? '📚'} ${cycle.subject}',
              style: BotanicalTypo.body(size: 14, color: textSub)),
            const SizedBox(height: 8),
            Text('공부 ${cycle.studyMin}분 · 강의 ${cycle.lectureMin}분 · 휴식 ${cycle.restMin}분',
              style: BotanicalTypo.label(size: 12, color: textMuted)),
          ]),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dCtx),
          child: Text('확인', style: TextStyle(
            fontWeight: FontWeight.w700, color: c)),
        ),
      ],
    ),
  );
}
