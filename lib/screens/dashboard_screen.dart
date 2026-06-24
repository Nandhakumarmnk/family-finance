import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cur = s.currency;
    final y = s.selectedYear;
    final m = s.selectedMonth;

    final income = s.incomeForMonth(y, m);
    final expense = s.expenseForMonth(y, m);
    final savings = income - expense;
    final target = s.targetFor(y, m);
    final breakdown = s.categoryBreakdown(y, m);

    return RefreshIndicator(
      onRefresh: () async => context.read<AppState>().init(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _greeting(context, s),
          const SizedBox(height: 12),
          PeriodPicker(
            year: y,
            month: m,
            years: s.availableYears,
            onYear: (v) => s.selectPeriod(year: v),
            onMonth: (v) => s.selectPeriod(month: v),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              StatCard(
                label: 'Income (${Fmt.monthShort(m)})',
                value: Fmt.currency(income, code: cur),
                icon: Icons.south_west,
                color: Colors.green.shade600,
              ),
              StatCard(
                label: 'Expenses (${Fmt.monthShort(m)})',
                value: Fmt.currency(expense, code: cur),
                icon: Icons.north_east,
                color: Colors.red.shade600,
              ),
              StatCard(
                label: 'Savings',
                value: Fmt.currency(savings, code: cur),
                icon: Icons.savings,
                color: savings >= 0 ? Colors.teal : Colors.orange,
                sub: target != null && target.savingsTarget > 0
                    ? 'Target ${Fmt.compact(target.savingsTarget, code: cur)}'
                    : null,
              ),
              StatCard(
                label: 'Family wallet',
                value: s.inFamily
                    ? Fmt.currency(s.walletBalance, code: cur)
                    : '—',
                icon: Icons.account_balance_wallet,
                color: Colors.indigo,
                sub: s.inFamily ? null : 'Not set up',
              ),
              StatCard(
                label: 'EMI / month',
                value: Fmt.currency(s.totalEmiMonthly, code: cur),
                icon: Icons.event_repeat,
                color: Colors.deepPurple,
                sub: '${s.activeEmiCount} active',
              ),
              StatCard(
                label: 'EMI remaining',
                value: Fmt.currency(s.totalEmiRemaining, code: cur),
                icon: Icons.hourglass_bottom,
                color: Colors.brown,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (target != null && target.spendingLimit > 0)
            _budgetBar(context, expense, target.spendingLimit, cur),
          const SizedBox(height: 8),
          const SectionHeader('Spending by category'),
          if (breakdown.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: EmptyState(
                  icon: Icons.pie_chart_outline,
                  message: 'No expenses recorded for this month yet.',
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: _categoryRows(context, breakdown, expense, cur)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _greeting(BuildContext context, AppState s) {
    final theme = Theme.of(context);
    final name = (s.profile?.displayName ?? '').split(' ').first;
    final initial = (s.profile?.displayName ?? '?').trim();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            Color.lerp(theme.colorScheme.primary, Colors.black, 0.4)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello${name.isEmpty ? '' : ', $name'} 👋',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      s.inFamily ? Icons.family_restroom : Icons.person_outline,
                      size: 14,
                      color: Colors.white.withOpacity(0.8),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        s.inFamily
                            ? (s.family?.familyName ??
                                s.profile?.familyName ??
                                'Family')
                            : 'Personal account',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white.withOpacity(0.85)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white.withOpacity(0.18),
            backgroundImage: (s.profile?.photoUrl?.isNotEmpty ?? false)
                ? NetworkImage(s.profile!.photoUrl!)
                : null,
            child: (s.profile?.photoUrl?.isNotEmpty ?? false)
                ? null
                : Text(
                    initial.isEmpty ? '?' : initial[0].toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _budgetBar(BuildContext context, double spent, double limit, String cur) {
    final double ratio = (spent / limit).clamp(0.0, 1.0).toDouble();
    final over = spent > limit;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Monthly budget'),
                const Spacer(),
                Text('${Fmt.currency(spent, code: cur)} / ${Fmt.currency(limit, code: cur)}',
                    style: TextStyle(
                        color: over ? Colors.red : null,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 10,
                color: over ? Colors.red : Colors.teal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _categoryRows(
      BuildContext context, Map<String, double> data, double total, String cur) {
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) {
      final pct = total == 0 ? 0.0 : e.value / total;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text(e.key)),
                Text(Fmt.currency(e.value, code: cur),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text('${(pct * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: pct, minHeight: 6),
            ),
          ],
        ),
      );
    }).toList();
  }
}
