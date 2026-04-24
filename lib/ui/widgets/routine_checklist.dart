import 'package:flutter/material.dart';
import '../../data/routine_service.dart';
import '../../theme/theme.dart';

/// DAILY 의 핵심 위젯 — 오늘 순서 TODO 체크리스트
/// 사용자 지시 2026-04-24 23:40: "투두리스트처럼 · 직관적이고 쉽게 · 매일 순서 크게"
class RoutineChecklist extends StatefulWidget {
  const RoutineChecklist({super.key});

  @override
  State<RoutineChecklist> createState() => _RoutineChecklistState();
}

class _RoutineChecklistState extends State<RoutineChecklist> {
  @override
  void initState() {
    super.initState();
    RoutineService.seedIfMissing();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RoutineStep>>(
      stream: RoutineService.todayStream(),
      builder: (ctx, snap) {
        final steps = snap.data ?? defaultRoutine();
        final doneCount = steps.where((s) => s.done).length;
        final total = steps.length;

        final active = currentBlock();
        // 블록별 그루핑
        final byBlock = <RoutineBlock, List<RoutineStep>>{};
        for (final s in steps) {
          final b = s is RoutineStepWithBlock ? s.block : RoutineBlock.morning;
          byBlock.putIfAbsent(b, () => []).add(s);
        }

        return Container(
          padding: const EdgeInsets.all(DailySpace.lg),
          decoration: BoxDecoration(
            color: DailyPalette.card,
            borderRadius: BorderRadius.circular(DailySpace.radiusL),
            border: Border.all(color: DailyPalette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('오늘의 순서',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: DailyPalette.ink)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: doneCount == total ? DailyPalette.success : DailyPalette.goldSurface,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$doneCount / $total',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: doneCount == total ? Colors.white : DailyPalette.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: total == 0 ? 0 : doneCount / total,
                minHeight: 6,
                backgroundColor: DailyPalette.line,
                valueColor: const AlwaysStoppedAnimation<Color>(DailyPalette.primary),
              ),
              const SizedBox(height: DailySpace.md),
              ...RoutineBlock.values.where((b) => byBlock.containsKey(b)).map((b) {
                final isActive = b == active;
                final blockSteps = byBlock[b]!;
                return _BlockSection(
                  block: b,
                  isActive: isActive,
                  steps: blockSteps,
                  allSteps: steps,
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _BlockSection extends StatelessWidget {
  final RoutineBlock block;
  final bool isActive;
  final List<RoutineStep> steps;
  final List<RoutineStep> allSteps;

  const _BlockSection({
    required this.block,
    required this.isActive,
    required this.steps,
    required this.allSteps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: DailySpace.md),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isActive ? DailyPalette.goldSurface : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isActive ? Border.all(color: DailyPalette.gold, width: 1.5) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                block.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isActive ? DailyPalette.primary : DailyPalette.ash,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                block.range,
                style: const TextStyle(fontSize: 10, color: DailyPalette.ash),
              ),
              if (isActive) ...[
                const SizedBox(width: 6),
                const Icon(Icons.circle, size: 8, color: DailyPalette.primary),
              ],
            ],
          ),
          ...steps.map((s) => _StepTile(step: s, allSteps: allSteps, isInActiveBlock: isActive)),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final RoutineStep step;
  final List<RoutineStep> allSteps;
  final bool isInActiveBlock;
  const _StepTile({required this.step, required this.allSteps, this.isInActiveBlock = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => RoutineService.toggle(step.id, allSteps),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: step.done ? DailyPalette.cream : (isInActiveBlock ? Colors.white : DailyPalette.paper),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: step.done ? DailyPalette.gold : DailyPalette.line),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(step.icon, style: const TextStyle(fontSize: 20)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: step.done ? DailyPalette.ash : DailyPalette.ink,
                      decoration: step.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (step.doneAt != null && step.done)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('✓ ${step.doneAt}',
                          style: const TextStyle(fontSize: 11, color: DailyPalette.ash)),
                    ),
                ],
              ),
            ),
            Icon(
              step.done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: step.done ? DailyPalette.success : DailyPalette.fog,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}
