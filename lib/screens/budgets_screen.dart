import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/category_icons.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Set a monthly spending limit per category. The dashboard raises an alert
/// for the selected month when any category goes over its budget.
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);
    final cur = s.currency;
    final spend = s.categoryBreakdown(s.selectedYear, s.selectedMonth);
    final names = <String>{...s.categoryNames, ...s.budgets.map((b) => b.category)}
        .toList()
      ..sort();
    final over = s.overBudget;

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: ResponsiveCenter(
        maxWidth: 640,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          children: [
            Text(
              'Monthly spending limits for ${Fmt.monthYear(s.selectedYear, s.selectedMonth)}. '
              'Tap a category to set or change its budget.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (over.isNotEmpty)
              Card(
                color: theme.colorScheme.errorContainer.withOpacity(0.5),
                child: ListTile(
                  leading: Icon(Icons.warning_amber_rounded,
                      color: theme.colorScheme.error),
                  title: Text('${over.length} categor'
                      '${over.length == 1 ? 'y is' : 'ies are'} over budget'),
                  subtitle: Text(over.map((e) => e.category).take(4).join(', ')),
                ),
              ),
            if (names.isEmpty)
              const EmptyState(
                  icon: Icons.savings_outlined,
                  message: 'Add expense categories first, then set budgets.')
            else
              ...names.map((n) => _row(context, s, n, spend[n] ?? 0, cur)),
          ],
        ),
      ),
    );
  }

  Widget _row(
      BuildContext context, AppState s, String name, double spent, String cur) {
    final theme = Theme.of(context);
    final limit = s.budgetFor(name);
    final has = limit > 0;
    final ratio = has ? (spent / limit).clamp(0.0, 1.0).toDouble() : 0.0;
    final over = has && spent > limit;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _editDialog(context, s, name, limit),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    child: Icon(CategoryIcons.byKey(s.iconKeyFor(name)),
                        size: 18,
                        color: theme.colorScheme.onSecondaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(name,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  if (has)
                    Text(
                      '${Fmt.currency(spent, code: cur)} / ${Fmt.currency(limit, code: cur)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: over ? theme.colorScheme.error : null,
                          fontWeight: FontWeight.w600),
                    )
                  else
                    Text('Set budget',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.primary)),
                ],
              ),
              if (has) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 7,
                    color: over ? theme.colorScheme.error : Colors.teal,
                  ),
                ),
                if (over)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Over by ${Fmt.currency(spent - limit, code: cur)}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.error)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editDialog(
      BuildContext context, AppState s, String name, double current) async {
    final ctrl = TextEditingController(
        text: current > 0 ? current.toStringAsFixed(0) : '');
    final result = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Budget · $name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(
            labelText: 'Monthly limit (${s.currency})',
            hintText: 'e.g. 5000',
          ),
        ),
        actions: [
          if (current > 0)
            TextButton(
                onPressed: () => Navigator.pop(ctx, 0.0),
                child: const Text('Clear')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(ctrl.text.trim()) ?? 0.0),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || !context.mounted) return;
    await s.setBudget(name, result);
  }
}
