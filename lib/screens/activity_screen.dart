import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/activity.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// A chronological report of every recorded change — payments added, edited,
/// EMI instalments paid, wallet top-ups/spends, etc. Grouped by day, newest
/// first, with a quick filter by type.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String _filter = 'All';

  static const _filters = [
    'All',
    'Income',
    'Expense',
    'EMI',
    'Wallet',
    'Target',
  ];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cur = s.currency;

    // Newest first (already inserted at front, but sort defensively).
    final all = [...s.activities]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final items = _filter == 'All'
        ? all
        : all.where((a) => a.type.startsWith(_filter)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Activity & changes')),
      body: ResponsiveCenter(
        maxWidth: 720,
        child: Column(
          children: [
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final f = _filters[i];
                return ChoiceChip(
                  label: Text(f),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: items.isEmpty
                ? const EmptyState(
                    icon: Icons.history,
                    message: 'No changes recorded yet.\n'
                        'Add a payment, EMI or wallet entry to see it here.',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: _buildGrouped(context, items, cur),
                  ),
          ),
        ],
        ),
      ),
    );
  }

  List<Widget> _buildGrouped(
      BuildContext context, List<Activity> items, String cur) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];
    String? currentDay;

    for (final a in items) {
      final day = Fmt.dayLabel(a.timestamp);
      if (day != currentDay) {
        currentDay = day;
        widgets.add(Padding(
          padding: EdgeInsets.only(top: widgets.isEmpty ? 0 : 18, bottom: 8),
          child: Text(
            day,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ));
      }
      widgets.add(_ActivityTile(activity: a, currency: cur));
      widgets.add(const SizedBox(height: 8));
    }
    return widgets;
  }
}

class _ActivityTile extends StatelessWidget {
  final Activity activity;
  final String currency;
  const _ActivityTile({required this.activity, required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = _visual(theme);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.description.isEmpty
                        ? activity.type
                        : activity.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${activity.action} · ${activity.type} · ${Fmt.time(activity.timestamp)}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (activity.amount > 0) ...[
              const SizedBox(width: 8),
              Text(
                Fmt.currency(activity.amount, code: currency),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  (IconData, Color) _visual(ThemeData theme) {
    switch (activity.type) {
      case 'Income':
        return (Icons.south_west, Colors.green.shade600);
      case 'Expense':
        return (Icons.north_east, Colors.red.shade600);
      case 'EMI':
      case 'EMI payment':
        return (Icons.account_balance, Colors.deepPurple);
      case 'Wallet':
        return (Icons.account_balance_wallet, Colors.indigo);
      case 'Target':
        return (Icons.flag, theme.colorScheme.secondary);
      default:
        return (Icons.history, theme.colorScheme.primary);
    }
  }
}
