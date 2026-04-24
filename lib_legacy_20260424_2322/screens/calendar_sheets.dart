part of 'calendar_screen.dart';

/// ═══════════════════════════════════════════════════
/// CALENDAR — 바텀시트 (일정/메모 추가)
/// ═══════════════════════════════════════════════════

// ══════════════════════════════════════════
//  바텀시트: 일정/메모 추가
// ══════════════════════════════════════════

class _AddEventMemoSheet extends StatefulWidget {
  final DateTime selectedDate;
  final VoidCallback onAdded;
  const _AddEventMemoSheet({required this.selectedDate, required this.onAdded});
  @override
  State<_AddEventMemoSheet> createState() => _AddEventMemoSheetState();
}

class _AddEventMemoSheetState extends State<_AddEventMemoSheet> {
  final _titleCtrl = TextEditingController();
  bool _isMemo = true;
  String _emoji = '📋';
  late DateTime _date;

  @override
  void initState() { super.initState(); _date = widget.selectedDate; }
  @override
  void dispose() { _titleCtrl.dispose(); super.dispose(); }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }
  bool get _dk => Theme.of(context).brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: sheetBottomPad(context, extra: 0)),
      decoration: BoxDecoration(
        color: _dk ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Row(children: [
            _typeChip('📝 메모', true),
            const SizedBox(width: 8),
            _typeChip('📅 일정', false),
            const Spacer(),
            Text(DateFormat('M/d').format(_date), style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: _dk ? Colors.white70 : Colors.grey.shade600)),
          ]),
          const SizedBox(height: 14),
          if (!_isMemo)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: ['📋', '📚', '🎯', '📊', '🧩', '🔥', '🎉', '💪'].map((e) =>
                GestureDetector(
                  onTap: () => _safeSetState(() => _emoji = e),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: _emoji == e
                        ? BotanicalColors.primary.withValues(alpha: 0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8)),
                    child: Text(e, style: const TextStyle(fontSize: 20))),
                )).toList()),
            ),
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500,
              color: _dk ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: _isMemo ? '메모 내용 입력...' : '일정 제목 입력...',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true,
              fillColor: _dk ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
          ),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: BotanicalColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: Text(_isMemo ? '메모 저장' : '일정 추가',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          )),
        ]),
      ),
    );
  }

  Widget _typeChip(String label, bool isMemoType) {
    final selected = _isMemo == isMemoType;
    return GestureDetector(
      onTap: () => _safeSetState(() => _isMemo = isMemoType),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
            ? BotanicalColors.primary.withValues(alpha: _dk ? 0.15 : 0.1)
            : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected
            ? BotanicalColors.primary.withValues(alpha: 0.3) : Colors.grey.shade300)),
        child: Text(label, style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700,
          color: selected ? BotanicalColors.primary
               : _dk ? Colors.white54 : Colors.grey.shade500)),
      ),
    );
  }

  Future<void> _save() async {
    final text = _titleCtrl.text.trim();
    if (text.isEmpty) return;
    widget.onAdded();
    if (mounted) Navigator.pop(context);
  }
}

class _TRField {
  final String emoji, label, key;
  final String? value;
  const _TRField(this.emoji, this.label, this.key, this.value);
}
