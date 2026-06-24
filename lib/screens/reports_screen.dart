import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/target.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Reports: month-wise and year-wise summaries with charts, plus monthly
/// savings / spending targets and planned-vs-actual comparison.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const Material(
            child: TabBar(
              tabs: [Tab(text: 'Monthly'), Tab(text: 'Yearly')],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [_MonthlyReport(), _YearlyReport()],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyReport extends StatelessWidget {
  const _MonthlyReport();

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

    return ResponsiveCenter(
      maxWidth: 760,
      child: ListView(
      padding: const EdgeInsets.all(16),
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
          Expanded(child: StatCard(label: 'Income', value: Fmt.currency(income, code: cur), icon: Icons.south_west, color: Colors.green)),
          const SizedBox(width: 12),
          Expanded(child: StatCard(label: 'Expense', value: Fmt.currency(expense, code: cur), icon: Icons.north_east, color: Colors.red)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: StatCard(label: 'Net savings', value: Fmt.currency(savings, code: cur), icon: Icons.savings, color: savings >= 0 ? Colors.teal : Colors.orange)),
          const SizedBox(width: 12),
          Expanded(child: StatCard(label: 'Savings rate', value: income > 0 ? '${(savings / income * 100).toStringAsFixed(0)}%' : '—', icon: Icons.percent, color: Colors.indigo)),
        ]),
        const SizedBox(height: 8),
        SectionHeader('Targets — ${Fmt.monthYear(y, m)}', trailing: TextButton.icon(
          onPressed: () => _setTarget(context, s, y, m, target),
          icon: const Icon(Icons.flag, size: 18),
          label: Text(target == null ? 'Set' : 'Edit'),
        )),
        _targetCard(context, target, savings, expense, cur),
        const SizedBox(height: 8),
        const SectionHeader('Category breakdown'),
        if (breakdown.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(24), child: EmptyState(icon: Icons.pie_chart_outline, message: 'No data for this month.')))
        else
          Card(child: Padding(padding: const EdgeInsets.all(16), child: _CategoryPie(data: breakdown, currency: cur))),
      ],
      ),
    );
  }

  Widget _targetCard(BuildContext context, Target? t, double savings, double expense, String cur) {
    if (t == null) {
      return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No target set for this month. Tap “Set” to add a savings goal and spending limit.')));
    }
    Widget bar(String label, double actual, double goal, {required bool lowerIsBetter}) {
      final double ratio = goal == 0 ? 0.0 : (actual / goal).clamp(0.0, 1.0).toDouble();
      final good = lowerIsBetter ? actual <= goal : actual >= goal;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(label),
              const Spacer(),
              Text('${Fmt.currency(actual, code: cur)} / ${Fmt.currency(goal, code: cur)}',
                  style: TextStyle(fontWeight: FontWeight.w600, color: good ? Colors.green.shade700 : Colors.orange.shade800)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: ratio, minHeight: 8, color: good ? Colors.green : Colors.orange)),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          if (t.savingsTarget > 0) bar('Savings goal', savings < 0 ? 0.0 : savings, t.savingsTarget, lowerIsBetter: false),
          if (t.spendingLimit > 0) bar('Spending limit', expense, t.spendingLimit, lowerIsBetter: true),
          if (t.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Align(alignment: Alignment.centerLeft, child: Text(t.notes, style: Theme.of(context).textTheme.bodySmall))),
        ]),
      ),
    );
  }

  void _setTarget(BuildContext context, AppState s, int y, int m, Target? existing) {
    final savings = TextEditingController(text: existing?.savingsTarget.toStringAsFixed(0) ?? '');
    final limit = TextEditingController(text: existing?.spendingLimit.toStringAsFixed(0) ?? '');
    final notes = TextEditingController(text: existing?.notes ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Target — ${Fmt.monthYear(y, m)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: savings, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Savings goal')),
            const SizedBox(height: 8),
            TextField(controller: limit, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Spending limit')),
            const SizedBox(height: 8),
            TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              s.setTarget(Target(
                id: existing?.id ?? newId('tgt'),
                year: y,
                month: m,
                savingsTarget: double.tryParse(savings.text) ?? 0,
                spendingLimit: double.tryParse(limit.text) ?? 0,
                notes: notes.text.trim(),
              ));
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _YearlyReport extends StatelessWidget {
  const _YearlyReport();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cur = s.currency;
    final y = s.selectedYear;
    final exp = s.monthlyExpenseSeries(y);
    final inc = s.monthlyIncomeSeries(y);
    final totalExp = s.expenseForYear(y);
    final totalInc = s.incomeForYear(y);

    return ResponsiveCenter(
      maxWidth: 760,
      child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PeriodPicker(
          year: y,
          month: s.selectedMonth,
          years: s.availableYears,
          showMonth: false,
          onYear: (v) => s.selectPeriod(year: v),
          onMonth: (_) {},
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: StatCard(label: 'Year income', value: Fmt.currency(totalInc, code: cur), icon: Icons.south_west, color: Colors.green)),
          const SizedBox(width: 12),
          Expanded(child: StatCard(label: 'Year expense', value: Fmt.currency(totalExp, code: cur), icon: Icons.north_east, color: Colors.red)),
        ]),
        const SizedBox(height: 12),
        StatCard(label: 'Year savings', value: Fmt.currency(totalInc - totalExp, code: cur), icon: Icons.savings, color: Colors.teal),
        const SizedBox(height: 16),
        const SectionHeader('Income vs Expense by month'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 20, 16, 12),
            child: SizedBox(height: 260, child: _IncomeExpenseChart(income: inc, expense: exp)),
          ),
        ),
        const SizedBox(height: 8),
        _legend(context),
      ],
      ),
    );
  }

  Widget _legend(BuildContext context) {
    Widget dot(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(t),
        ]);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      dot(Colors.green, 'Income'),
      const SizedBox(width: 20),
      dot(Colors.red, 'Expense'),
    ]);
  }
}

class _IncomeExpenseChart extends StatelessWidget {
  final List<double> income;
  final List<double> expense;
  const _IncomeExpenseChart({required this.income, required this.expense});

  @override
  Widget build(BuildContext context) {
    final maxVal = [
      ...income,
      ...expense,
      1.0,
    ].reduce((a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        maxY: maxVal * 1.2,
        barTouchData: BarTouchData(enabled: true),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i > 11) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(Fmt.monthShort(i + 1).substring(0, 1),
                      style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(12, (i) {
          return BarChartGroupData(x: i, barRods: [
            BarChartRodData(toY: income[i], color: Colors.green, width: 6, borderRadius: BorderRadius.circular(2)),
            BarChartRodData(toY: expense[i], color: Colors.red, width: 6, borderRadius: BorderRadius.circular(2)),
          ]);
        }),
      ),
    );
  }
}

class _CategoryPie extends StatelessWidget {
  final Map<String, double> data;
  final String currency;
  const _CategoryPie({required this.data, required this.currency});

  static const _palette = [
    Color(0xFF1E6F6A), Color(0xFFE07A5F), Color(0xFF3D405B), Color(0xFFF2CC8F),
    Color(0xFF81B29A), Color(0xFF9B5DE5), Color(0xFFF15BB5), Color(0xFF00BBF9),
    Color(0xFF8AC926), Color(0xFFFF924C), Color(0xFF6A4C93), Color(0xFF9E9E9E),
  ];

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold(0.0, (a, e) => a + e.value);

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 44,
              sections: [
                for (int i = 0; i < entries.length; i++)
                  PieChartSectionData(
                    value: entries[i].value,
                    color: _palette[i % _palette.length],
                    title: '${(entries[i].value / total * 100).toStringAsFixed(0)}%',
                    radius: 50,
                    titleStyle: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(entries.length, (i) {
          final e = entries[i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: _palette[i % _palette.length], borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Expanded(child: Text(e.key)),
              Text(Fmt.currency(e.value, code: currency), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          );
        }),
      ],
    );
  }
}
