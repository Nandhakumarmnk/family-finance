import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Per-member spending analytics for the family: who spent what this month,
/// plus family income and total spend. Reads the shared family ledger.
class MemberAnalyticsScreen extends StatelessWidget {
  const MemberAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);
    final cur = s.currency;
    final y = s.selectedYear;
    final m = s.selectedMonth;

    if (!s.inFamily) {
      return Scaffold(
        appBar: AppBar(title: const Text('Family analytics')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Set up a family to see who spends what across the household.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final byMember = s.familySpendByMember(y, m);
    final entries = byMember.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (a, e) => a + e.value);

    return Scaffold(
      appBar: AppBar(title: const Text('Family analytics')),
      body: ResponsiveCenter(
        maxWidth: 640,
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
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: StatCard(
                  label: 'Family spend (${Fmt.monthShort(m)})',
                  value: Fmt.currency(total, code: cur),
                  icon: Icons.groups,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Family income',
                  value: Fmt.currency(s.familyIncomeForMonth(y, m), code: cur),
                  icon: Icons.south_west,
                  color: Colors.green,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            const SectionHeader('Spending by member'),
            if (entries.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: EmptyState(
                    icon: Icons.groups_outlined,
                    message: 'No family spending recorded this month.',
                  ),
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: entries.map((e) {
                      final pct = total == 0 ? 0.0 : e.value / total;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Text(e.key,
                                      overflow: TextOverflow.ellipsis)),
                              Text(Fmt.currency(e.value, code: cur),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              Text('${(pct * 100).toStringAsFixed(0)}%',
                                  style: TextStyle(
                                      color: theme.colorScheme.outline)),
                            ]),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                  value: pct, minHeight: 6),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
