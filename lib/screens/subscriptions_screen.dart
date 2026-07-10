import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/reminder.dart';
import '../state/app_state.dart';
import '../utils/category_icons.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'reminders_screen.dart';

/// Subscriptions & recurring payments — a focused lens over the recurring
/// reminders (Netflix, rent, SIP, EMIs…). Normalises every billing cycle to a
/// monthly-equivalent so it can total your true monthly and annual commitment.
///
/// Reuses the existing recurring-reminder data and its add/edit form, so there
/// is no new storage: a "subscription" is simply a reminder that repeats.
class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  /// Monthly-equivalent cost of one recurrence of [r].
  static double monthlyEquivalent(Reminder r) {
    switch (r.recurrence) {
      case Recurrence.weekly:
        return r.amount * 52 / 12;
      case Recurrence.monthly:
        return r.amount;
      case Recurrence.quarterly:
        return r.amount / 3;
      case Recurrence.yearly:
        return r.amount / 12;
      case Recurrence.none:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cur = s.currency;

    final subs = s.reminders
        .where((r) => r.recurrence != Recurrence.none)
        .toList()
      ..sort((a, b) {
        if (a.active != b.active) return a.active ? -1 : 1;
        return monthlyEquivalent(b).compareTo(monthlyEquivalent(a));
      });
    final active = subs.where((r) => r.active).toList();
    final paused = subs.where((r) => !r.active).toList();
    final monthly =
        active.fold<double>(0, (a, r) => a + monthlyEquivalent(r));

    return Scaffold(
      appBar: AppBar(title: const Text('Subscriptions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            RemindersScreen.openForm(context, kind: ReminderKind.bill),
        icon: const Icon(Icons.add),
        label: const Text('Add subscription'),
      ),
      body: ResponsiveCenter(
        maxWidth: 720,
        child: subs.isEmpty
            ? const _Empty()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  Row(children: [
                    Expanded(
                      child: StatCard(
                        label: 'Monthly',
                        value: Fmt.currency(monthly, code: cur),
                        icon: Icons.event_repeat,
                        color: Colors.deepPurple,
                        sub: '${active.length} active',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        label: 'Yearly',
                        value: Fmt.currency(monthly * 12, code: cur),
                        icon: Icons.calendar_month,
                        color: Colors.indigo,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  const SectionHeader('Active'),
                  if (active.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: EmptyState(
                            icon: Icons.subscriptions_outlined,
                            message: 'No active subscriptions.'),
                      ),
                    )
                  else
                    ...active.map((r) => _SubCard(reminder: r, currency: cur)),
                  if (paused.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const SectionHeader('Paused'),
                    ...paused.map((r) => _SubCard(reminder: r, currency: cur)),
                  ],
                ],
              ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        const EmptyState(
          icon: Icons.subscriptions_outlined,
          message:
              'No subscriptions yet.\nAdd recurring payments like Netflix, rent,\n'
              'SIP or an EMI to see your monthly & yearly total.',
        ),
        const SizedBox(height: 8),
        Center(
          child: FilledButton.icon(
            onPressed: () =>
                RemindersScreen.openForm(context, kind: ReminderKind.bill),
            icon: const Icon(Icons.add),
            label: const Text('Add subscription'),
          ),
        ),
      ],
    );
  }
}

class _SubCard extends StatelessWidget {
  final Reminder reminder;
  final String currency;
  const _SubCard({required this.reminder, required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = reminder;
    final monthly = SubscriptionsScreen.monthlyEquivalent(r);
    final faded = !r.active;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => RemindersScreen.openForm(context, existing: r),
        child: Opacity(
          opacity: faded ? 0.6 : 1,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Icon(CategoryIcons.byKey(r.iconKey),
                      size: 20,
                      color: theme.colorScheme.onSecondaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        '${r.recurrenceLabel}${r.autoPost ? ' · Auto' : ''}'
                        ' · next ${Fmt.date(r.dueDate)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(Fmt.currency(r.amount, code: currency),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (r.recurrence != Recurrence.monthly && r.amount > 0)
                      Text('${Fmt.currency(monthly, code: currency)}/mo',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
                PopupMenuButton<String>(
                  onSelected: (v) => _onMenu(context, v),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(
                        value: 'toggle',
                        child: Text(r.active ? 'Pause' : 'Resume')),
                    const PopupMenuItem(
                        value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onMenu(BuildContext context, String v) {
    final s = context.read<AppState>();
    switch (v) {
      case 'edit':
        RemindersScreen.openForm(context, existing: reminder);
        break;
      case 'toggle':
        s.setReminderActive(reminder.id, !reminder.active);
        break;
      case 'delete':
        s.deleteReminder(reminder.id);
        break;
    }
  }
}
