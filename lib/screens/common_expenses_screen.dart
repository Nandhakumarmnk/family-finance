import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/family_ledger.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// "Common expenses" — a shared, read-only view of every family member's
/// income and expenses, pulled from the shared family workbook. This is where
/// each member's spending shows up for the whole household (the data each
/// person enters on their own Expenses / Salary screens is mirrored here).
class CommonExpensesScreen extends StatelessWidget {
  const CommonExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cur = s.currency;
    final y = s.selectedYear;
    final m = s.selectedMonth;

    final income = s.familyIncomeForMonth(y, m);
    final expense = s.familyExpenseForMonth(y, m);
    final byMember = s.familySpendByMember(y, m);
    final entries = s.familyEntriesForMonth(y, m);

    return ResponsiveCenter(
      maxWidth: 720,
      child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        PeriodPicker(
          year: y,
          month: m,
          years: s.availableYears,
          onYear: (v) => s.selectPeriod(year: v),
          onMonth: (v) => s.selectPeriod(month: v),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: StatCard(
              label: 'Family income (${Fmt.monthShort(m)})',
              value: Fmt.currency(income, code: cur),
              icon: Icons.south_west,
              color: Colors.green.shade600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StatCard(
              label: 'Family expenses (${Fmt.monthShort(m)})',
              value: Fmt.currency(expense, code: cur),
              icon: Icons.north_east,
              color: Colors.red.shade600,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        const SectionHeader('Spending by member'),
        if (byMember.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: EmptyState(
                icon: Icons.groups_outlined,
                message: 'No family spending recorded this month yet.',
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: _memberRows(context, byMember, expense, cur),
              ),
            ),
          ),
        const SizedBox(height: 8),
        const SectionHeader('All family activity'),
        if (entries.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                message: 'Nothing recorded for this month.\n'
                    'Income and expenses each member adds will appear here.',
              ),
            ),
          )
        else
          ...entries.map((e) => _entryTile(context, e, cur)),
      ],
      ),
    );
  }

  List<Widget> _memberRows(BuildContext context, Map<String, double> data,
      double total, String cur) {
    final scheme = Theme.of(context).colorScheme;
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: scheme.primaryContainer,
                    child: Text(
                      e.key.isEmpty ? '?' : e.key[0].toUpperCase(),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimaryContainer),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(e.key,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text(Fmt.currency(e.value, code: cur),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text('${total == 0 ? 0 : (e.value / total * 100).round()}%',
                      style: TextStyle(color: scheme.outline)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : (e.value / total).clamp(0.0, 1.0),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _entryTile(BuildContext context, FamilyLedgerEntry e, String cur) {
    final isIncome = e.type == 'income';
    final color = isIncome ? Colors.green.shade700 : Colors.red.shade700;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(isIncome ? Icons.south_west : Icons.north_east,
              color: color, size: 20),
        ),
        title: Text(e.category.isEmpty ? (isIncome ? 'Income' : 'Expense') : e.category),
        subtitle: Text(
          '${e.memberName.isEmpty ? e.memberEmail : e.memberName} • ${Fmt.date(e.date)}'
          '${e.notes.isEmpty ? '' : '\n${e.notes}'}',
        ),
        isThreeLine: e.notes.isNotEmpty,
        trailing: Text('${isIncome ? '+' : '-'}${Fmt.currency(e.amount, code: cur)}',
            style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ),
    );
  }
}
