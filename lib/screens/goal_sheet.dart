import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/target.dart';
import '../state/app_state.dart';
import '../utils/format.dart';

/// A friendly bottom sheet to set a monthly **goal** (savings target + spending
/// limit). Enhancements over the old plain dialog:
///  • quick-suggestion chips (save 10/20/30% of this month's income),
///  • spending-limit shortcuts (this month's income, last month's spend),
///  • a live preview of where you stand right now against the entered goal,
///  • "copy last month's goal", and
///  • a Delete option for a goal set by mistake.
Future<void> showGoalSheet(
  BuildContext context, {
  required int year,
  required int month,
  Target? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GoalSheet(year: year, month: month, existing: existing),
  );
}

class _GoalSheet extends StatefulWidget {
  final int year;
  final int month;
  final Target? existing;
  const _GoalSheet(
      {required this.year, required this.month, this.existing});

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late final TextEditingController _savings;
  late final TextEditingController _limit;
  late final TextEditingController _notes;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _savings = TextEditingController(
        text: (e != null && e.savingsTarget > 0)
            ? e.savingsTarget.toStringAsFixed(0)
            : '');
    _limit = TextEditingController(
        text: (e != null && e.spendingLimit > 0)
            ? e.spendingLimit.toStringAsFixed(0)
            : '');
    _notes = TextEditingController(text: e?.notes ?? '');
  }

  @override
  void dispose() {
    _savings.dispose();
    _limit.dispose();
    _notes.dispose();
    super.dispose();
  }

  double get _savingsGoal => double.tryParse(_savings.text.trim()) ?? 0;
  double get _spendLimit => double.tryParse(_limit.text.trim()) ?? 0;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final s = context.read<AppState>();
    await s.setTarget(Target(
      id: widget.existing?.id ?? newId('tgt'),
      year: widget.year,
      month: widget.month,
      savingsTarget: _savingsGoal,
      spendingLimit: _spendLimit,
      notes: _notes.text.trim(),
    ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove goal?'),
        content: Text(
            'The goal for ${Fmt.monthYear(widget.year, widget.month)} will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<AppState>().deleteTarget(widget.year, widget.month);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cur = s.currency;
    final theme = Theme.of(context);

    final income = s.incomeForMonth(widget.year, widget.month);
    final expense = s.expenseForMonth(widget.year, widget.month);
    final savings = income - expense;

    // Last month's goal (for the "copy" shortcut).
    final prev = widget.month == 1
        ? s.targetFor(widget.year - 1, 12)
        : s.targetFor(widget.year, widget.month - 1);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.flag, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_isEdit ? 'Edit' : 'Set'} goal · ${Fmt.monthYear(widget.year, widget.month)}',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (prev != null &&
                    (prev.savingsTarget > 0 || prev.spendingLimit > 0))
                  TextButton.icon(
                    onPressed: () => setState(() {
                      if (prev.savingsTarget > 0) {
                        _savings.text = prev.savingsTarget.toStringAsFixed(0);
                      }
                      if (prev.spendingLimit > 0) {
                        _limit.text = prev.spendingLimit.toStringAsFixed(0);
                      }
                    }),
                    icon: const Icon(Icons.copy_all, size: 16),
                    label: const Text('Copy last'),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // --- Savings goal ----------------------------------------------
            Text('Savings goal', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            TextField(
              controller: _savings,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'How much to save this month',
                prefixText: '${Fmt.currency(0, code: cur).replaceAll('0.00', '')} ',
              ),
            ),
            if (income > 0) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final pct in [10, 20, 30, 40])
                    ActionChip(
                      label: Text('$pct% of income'),
                      onPressed: () => setState(() => _savings.text =
                          (income * pct / 100).toStringAsFixed(0)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // --- Spending limit --------------------------------------------
            Text('Spending limit', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            TextField(
              controller: _limit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Soft cap on this month’s spending',
                prefixText: '${Fmt.currency(0, code: cur).replaceAll('0.00', '')} ',
              ),
            ),
            if (income > 0) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final pct in [60, 70, 80])
                    ActionChip(
                      label: Text('$pct% of income'),
                      onPressed: () => setState(() => _limit.text =
                          (income * pct / 100).toStringAsFixed(0)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // --- Live preview ----------------------------------------------
            if (_savingsGoal > 0 || _spendLimit > 0) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Where you stand now',
                          style: theme.textTheme.labelLarge),
                      const SizedBox(height: 8),
                      if (_savingsGoal > 0)
                        _previewBar(
                          context,
                          'Saved',
                          savings < 0 ? 0 : savings,
                          _savingsGoal,
                          cur,
                          higherIsBetter: true,
                        ),
                      if (_spendLimit > 0)
                        _previewBar(
                          context,
                          'Spent',
                          expense,
                          _spendLimit,
                          cur,
                          higherIsBetter: false,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isEdit ? 'Save goal' : 'Set goal'),
            ),
            if (_isEdit) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _delete,
                icon: Icon(Icons.delete_outline,
                    color: theme.colorScheme.error, size: 18),
                label: Text('Remove goal',
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _previewBar(BuildContext context, String label, double actual,
      double goal, String cur,
      {required bool higherIsBetter}) {
    final theme = Theme.of(context);
    final ratio = goal == 0 ? 0.0 : (actual / goal).clamp(0.0, 1.0).toDouble();
    final good = higherIsBetter ? actual >= goal : actual <= goal;
    final color = good ? Colors.green : Colors.orange;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                '${Fmt.currency(actual, code: cur)} / ${Fmt.currency(goal, code: cur)}',
                style: TextStyle(fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
                value: ratio, minHeight: 8, color: color),
          ),
        ],
      ),
    );
  }
}
