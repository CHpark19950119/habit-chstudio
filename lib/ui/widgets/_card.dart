import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// 공통 카드 · DAILY 내부 일관 디자인
class DailyCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Color? tint;
  final VoidCallback? onTap;

  const DailyCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.tint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.all(DailySpace.lg),
      decoration: BoxDecoration(
        color: tint ?? DailyPalette.card,
        borderRadius: BorderRadius.circular(DailySpace.radiusL),
        border: Border.all(color: DailyPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: DailyPalette.primary),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: DailyPalette.ink)),
            ],
          ),
          const SizedBox(height: DailySpace.md),
          child,
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(DailySpace.radiusL),
      onTap: onTap,
      child: content,
    );
  }
}
