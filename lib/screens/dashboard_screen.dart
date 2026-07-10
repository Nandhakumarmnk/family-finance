import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/reminder.dart';
import '../state/app_state.dart';
import '../utils/category_icons.dart';
import '../utils/format.dart';
import '../utils/image_data.dart';
import '../widgets/common.dart';
import 'budgets_screen.dart';
import 'reminders_screen.dart';

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
      child: ResponsiveCenter(
        maxWidth: 760,
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
            // Taller cards (was 1.4) so labels like "Family wallet" / "EMI
            // remaining" never clip at the bottom, even at larger font scales.
            childAspectRatio: 1.05,
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
          ..._insights(context, s, y, m, cur),
          if (s.dueReminders.isNotEmpty) ...[
            const SizedBox(height: 8),
            _remindersAlert(context, s, cur),
          ],
          if (s.overBudget.isNotEmpty) ...[
            const SizedBox(height: 8),
            _overBudgetAlert(context, s, cur),
          ],
          const SizedBox(height: 8),
          const SectionHeader('Spending by category'),
          _SpendingByCategory(
            data: breakdown,
            total: expense,
            currency: cur,
            year: y,
            month: m,
          ),
        ],
        ),
      ),
    );
  }

  /// Auto-generated "smart insights" for the selected month — month-over-month
  /// trend, top category, month-end projection and savings rate. Computed purely
  /// from existing data (no new storage). Returns an empty list when there's
  /// nothing meaningful to show yet.
  List<Widget> _insights(
      BuildContext context, AppState s, int y, int m, String cur) {
    final theme = Theme.of(context);
    final expense = s.expenseForMonth(y, m);
    final income = s.incomeForMonth(y, m);
    final prevY = m == 1 ? y - 1 : y;
    final prevM = m == 1 ? 12 : m - 1;
    final prevExpense = s.expenseForMonth(prevY, prevM);
    final breakdown = s.categoryBreakdown(y, m);

    final rows = <Widget>[];

    if (prevExpense > 0) {
      final diff = (expense - prevExpense) / prevExpense;
      final up = diff >= 0;
      rows.add(_insightRow(
        context,
        icon: up ? Icons.trending_up : Icons.trending_down,
        color: up ? Colors.red.shade600 : Colors.green.shade600,
        text:
            'Spending ${up ? 'up' : 'down'} ${(diff.abs() * 100).toStringAsFixed(0)}% vs ${Fmt.monthShort(prevM)}',
      ));
    }

    if (breakdown.isNotEmpty && expense > 0) {
      final top =
          breakdown.entries.reduce((a, b) => a.value >= b.value ? a : b);
      rows.add(_insightRow(
        context,
        icon: CategoryIcons.byKey(s.iconKeyFor(top.key)),
        color: theme.colorScheme.primary,
        text:
            'Top category: ${top.key} — ${Fmt.currency(top.value, code: cur)} (${(top.value / expense * 100).toStringAsFixed(0)}%)',
      ));
    }

    final now = DateTime.now();
    if (y == now.year && m == now.month && expense > 0 && now.day > 1) {
      final daysInMonth = DateUtils.getDaysInMonth(y, m);
      final projected = expense / now.day * daysInMonth;
      rows.add(_insightRow(
        context,
        icon: Icons.timeline,
        color: Colors.deepPurple,
        text:
            'On pace for ~${Fmt.compact(projected, code: cur)} by month end',
      ));
    }

    if (income > 0) {
      final rate = (income - expense) / income * 100;
      rows.add(_insightRow(
        context,
        icon: Icons.savings_outlined,
        color: rate >= 0 ? Colors.teal : Colors.orange,
        text: 'Savings rate ${rate.toStringAsFixed(0)}% this month',
      ));
    }

    if (rows.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.auto_awesome,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Insights',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 6),
              ...rows,
            ],
          ),
        ),
      ),
    ];
  }

  Widget _insightRow(BuildContext context,
      {required IconData icon, required Color color, required String text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
              child:
                  Text(text, style: Theme.of(context).textTheme.bodyMedium)),
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
            backgroundImage: imageProviderFor(s.profile?.avatarUrl),
            child: (s.profile?.avatarUrl?.isNotEmpty ?? false)
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

  /// A dashboard alert listing payments that are overdue or due soon. Tapping
  /// it (or "View all") opens the full reminders screen.
  Widget _remindersAlert(BuildContext context, AppState s, String cur) {
    final theme = Theme.of(context);
    final due = s.dueReminders;
    final shown = due.take(3).toList();
    final overdueCount =
        due.where((r) => r.status == ReminderStatus.overdue).length;
    final accent = overdueCount > 0 ? Colors.red : Colors.amber.shade800;

    void open() => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const RemindersScreen()));

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.notifications_active, color: accent, size: 20),
                  const SizedBox(width: 8),
                  Text('Payments due',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${due.length}',
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: accent, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              ...shown.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(CategoryIcons.byKey(r.iconKey),
                            size: 16, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(r.title,
                                overflow: TextOverflow.ellipsis)),
                        Text(
                          r.status == ReminderStatus.overdue
                              ? 'Overdue'
                              : r.status == ReminderStatus.dueToday
                                  ? 'Today'
                                  : 'In ${r.daysUntilDue}d',
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: r.status == ReminderStatus.overdue
                                  ? Colors.red
                                  : theme.colorScheme.outline,
                              fontWeight: FontWeight.w600),
                        ),
                        if (r.amount > 0) ...[
                          const SizedBox(width: 10),
                          Text(Fmt.currency(r.amount, code: cur),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  )),
              if (due.length > shown.length) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: open,
                    child: Text('View all ${due.length}'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Alert listing categories that have gone over their monthly budget.
  /// Tapping opens the Budgets screen.
  Widget _overBudgetAlert(BuildContext context, AppState s, String cur) {
    final theme = Theme.of(context);
    final over = s.overBudget;
    void open() => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const BudgetsScreen()));

    return Card(
      color: theme.colorScheme.errorContainer.withOpacity(0.4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: theme.colorScheme.error, size: 20),
                  const SizedBox(width: 8),
                  Text('Over budget',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${over.length}',
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              ...over.take(3).map((b) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(CategoryIcons.byKey(s.iconKeyFor(b.category)),
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(b.category,
                                overflow: TextOverflow.ellipsis)),
                        Text(
                          '${Fmt.currency(b.spent, code: cur)} / ${Fmt.currency(b.limit, code: cur)}',
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )),
              if (over.length > 3) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      onPressed: open,
                      child: Text('View all ${over.length}')),
                ),
              ],
            ],
          ),
        ),
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

}

/// Shared category-slice palette so the donut and its legend/rows agree, and so
/// the same colours are used wherever spend is broken down by category.
const List<Color> kCategoryPalette = [
  Color(0xFF1E6F6A), Color(0xFFE07A5F), Color(0xFF3D405B), Color(0xFFF2CC8F),
  Color(0xFF81B29A), Color(0xFF9B5DE5), Color(0xFFF15BB5), Color(0xFF00BBF9),
  Color(0xFF8AC926), Color(0xFFFF924C), Color(0xFF6A4C93), Color(0xFF9E9E9E),
];

/// "Spending by category" card: an interactive donut over a tappable list.
/// Tapping a slice **or** a row drills into that category's transactions for
/// the selected month.
class _SpendingByCategory extends StatefulWidget {
  final Map<String, double> data;
  final double total;
  final String currency;
  final int year;
  final int month;

  const _SpendingByCategory({
    required this.data,
    required this.total,
    required this.currency,
    required this.year,
    required this.month,
  });

  @override
  State<_SpendingByCategory> createState() => _SpendingByCategoryState();
}

class _SpendingByCategoryState extends State<_SpendingByCategory> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.data.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: EmptyState(
            icon: Icons.pie_chart_outline,
            message: 'No expenses recorded for this month yet.',
          ),
        ),
      );
    }

    final entries = widget.data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = widget.total == 0
        ? entries.fold(0.0, (a, e) => a + e.value)
        : widget.total;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
        child: Column(
          children: [
            SizedBox(
              height: 196,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 58,
                      startDegreeOffset: -90,
                      pieTouchData: PieTouchData(
                        touchCallback: (event, resp) {
                          final idx =
                              resp?.touchedSection?.touchedSectionIndex;
                          if (idx == null || idx < 0) {
                            if (_touched != null) {
                              setState(() => _touched = null);
                            }
                            return;
                          }
                          if (_touched != idx) setState(() => _touched = idx);
                          // Only a real tap (not hover/drag) opens the details.
                          if (event is FlTapUpEvent && idx < entries.length) {
                            _open(entries[idx].key);
                          }
                        },
                      ),
                      sections: [
                        for (int i = 0; i < entries.length; i++)
                          PieChartSectionData(
                            value: entries[i].value,
                            color: kCategoryPalette[i % kCategoryPalette.length],
                            radius: _touched == i ? 30 : 24,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Total',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(
                        Fmt.compact(total, code: widget.currency),
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < entries.length; i++)
              _row(context, i, entries[i], total),
          ],
        ),
      ),
    );
  }

  Widget _row(
      BuildContext context, int i, MapEntry<String, double> e, double total) {
    final theme = Theme.of(context);
    final pct = total == 0 ? 0.0 : e.value / total;
    final color = kCategoryPalette[i % kCategoryPalette.length];
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _open(e.key),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 8),
                Icon(
                  CategoryIcons.byKey(
                      context.read<AppState>().iconKeyFor(e.key)),
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(e.key, overflow: TextOverflow.ellipsis)),
                Text(Fmt.currency(e.value, code: widget.currency),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text('${(pct * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: theme.colorScheme.outline)),
                Icon(Icons.chevron_right,
                    size: 16, color: theme.colorScheme.outline),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: color.withOpacity(0.12),
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(String category) => showCategoryTransactions(
        context,
        category: category,
        year: widget.year,
        month: widget.month,
      );
}

/// Bottom sheet listing every transaction in [category] for the given month —
/// the drill-down opened from the dashboard's spending chart / list.
void showCategoryTransactions(
  BuildContext context, {
  required String category,
  required int year,
  required int month,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CategoryTransactionsSheet(
        category: category, year: year, month: month),
  );
}

class _CategoryTransactionsSheet extends StatelessWidget {
  final String category;
  final int year;
  final int month;

  const _CategoryTransactionsSheet({
    required this.category,
    required this.year,
    required this.month,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cur = s.currency;
    final theme = Theme.of(context);
    final items = s.expenses
        .where((e) =>
            e.year == year && e.month == month && e.category == category)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final total = items.fold(0.0, (a, e) => a + e.amount);

    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Icon(
                    CategoryIcons.byKey(s.iconKeyFor(category)),
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${Fmt.monthYear(year, month)} • ${items.length} '
                        '${items.length == 1 ? 'transaction' : 'transactions'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(Fmt.currency(total, code: cur),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: EmptyState(
                        icon: Icons.receipt_long_outlined,
                        message: 'No transactions in this category.'),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final e = items[i];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            child: Text('${e.date.day}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ),
                          title: Text(Fmt.currency(e.amount, code: cur),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            '${Fmt.date(e.date)} • ${e.paymentMode}'
                            '${e.fromFamilyWallet ? ' • Family wallet' : ''}'
                            '${e.notes.isNotEmpty ? '\n${e.notes}' : ''}',
                          ),
                          isThreeLine: e.notes.isNotEmpty,
                          trailing: e.hasReceipt
                              ? Icon(Icons.receipt_long,
                                  color: theme.colorScheme.primary)
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
