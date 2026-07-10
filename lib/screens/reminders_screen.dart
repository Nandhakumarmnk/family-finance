import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/reminder.dart';
import '../state/app_state.dart';
import '../utils/category_icons.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Payment reminders — EMIs, repayments, groceries, bills, recharges and other
/// mandatory needs. Shows what's overdue / due soon / upcoming, lets the user
/// mark a payment done (optionally booking the expense) and rolls recurring
/// reminders forward to their next due date.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();

  static void openForm(BuildContext context,
      {Reminder? existing, ReminderKind? kind}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReminderForm(existing: existing, initialKind: kind),
    );
  }
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cur = s.currency;
    final hasAny = s.reminders.isNotEmpty;

    final q = _query.trim().toLowerCase();
    final all = s.remindersSorted.where((r) {
      if (q.isEmpty) return true;
      return r.title.toLowerCase().contains(q) ||
          r.notes.toLowerCase().contains(q) ||
          r.label.toLowerCase().contains(q) ||
          r.amount.toStringAsFixed(2).contains(q);
    }).toList();

    final overdue =
        all.where((r) => r.status == ReminderStatus.overdue).toList();
    final today =
        all.where((r) => r.status == ReminderStatus.dueToday).toList();
    final soon = all.where((r) => r.status == ReminderStatus.dueSoon).toList();
    final upcoming =
        all.where((r) => r.status == ReminderStatus.upcoming).toList();
    final paused = all.where((r) => r.status == ReminderStatus.paused).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Payment reminders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => RemindersScreen.openForm(context),
        icon: const Icon(Icons.add_alert_outlined),
        label: const Text('Add reminder'),
      ),
      body: ResponsiveCenter(
        maxWidth: 720,
        child: !hasAny
            ? _EmptyReminders(
                onPick: (k) => RemindersScreen.openForm(context, kind: k))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Search reminders',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                              ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: all.isEmpty
                        ? const EmptyState(
                            icon: Icons.search_off,
                            message: 'No reminders match your search.')
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                            children: [
                              _summary(context, s, cur),
                              _group(context, 'Overdue', overdue, cur,
                                  Colors.red),
                              _group(context, 'Due today', today, cur,
                                  Colors.deepOrange),
                              _group(context, 'Due soon', soon, cur,
                                  Colors.amber.shade800),
                              _group(context, 'Upcoming', upcoming, cur,
                                  Colors.teal),
                              _group(context, 'Paused', paused, cur,
                                  Colors.grey),
                            ],
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _summary(BuildContext context, AppState s, String cur) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: StatCard(
              label: 'Needs attention',
              value: '${s.dueReminderCount}',
              icon: Icons.notifications_active_outlined,
              color: s.dueReminderCount > 0 ? Colors.red : Colors.teal,
              sub: s.dueReminderCount > 0 ? 'Due or overdue' : 'All clear',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StatCard(
              label: 'Monthly reminders',
              value: Fmt.currency(s.reminderMonthlyOutgo, code: cur),
              icon: Icons.event_repeat,
              color: Colors.deepPurple,
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(BuildContext context, String title, List<Reminder> items,
      String cur, Color accent) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Row(
            children: [
              Container(width: 10, height: 10,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('${items.length}',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            ],
          ),
        ),
        ...items.map((r) => _ReminderCard(reminder: r, currency: cur)),
      ],
    );
  }

}

class _EmptyReminders extends StatelessWidget {
  final ValueChanged<ReminderKind> onPick;
  const _EmptyReminders({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        const EmptyState(
          icon: Icons.notifications_none,
          message:
              'No payment reminders yet.\nAdd one for an EMI, repayment, bill,\n'
              'recharge, groceries or any mandatory need.',
        ),
        const SizedBox(height: 8),
        Text('Quick add',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in ReminderKind.values)
              ActionChip(
                avatar: Icon(CategoryIcons.byKey(kindMeta[k]!.iconKey), size: 18),
                label: Text(kindMeta[k]!.label),
                onPressed: () => onPick(k),
              ),
          ],
        ),
      ],
    );
  }
}

class _ReminderCard extends StatelessWidget {
  final Reminder reminder;
  final String currency;
  const _ReminderCard({required this.reminder, required this.currency});

  Color _statusColor(BuildContext context) {
    switch (reminder.status) {
      case ReminderStatus.overdue:
        return Colors.red;
      case ReminderStatus.dueToday:
        return Colors.deepOrange;
      case ReminderStatus.dueSoon:
        return Colors.amber.shade800;
      case ReminderStatus.upcoming:
        return Colors.teal;
      case ReminderStatus.paused:
        return Theme.of(context).colorScheme.outline;
    }
  }

  String _dueText() {
    final d = reminder.daysUntilDue;
    switch (reminder.status) {
      case ReminderStatus.overdue:
        final n = -d;
        return 'Overdue by $n day${n == 1 ? '' : 's'} · ${Fmt.date(reminder.dueDate)}';
      case ReminderStatus.dueToday:
        return 'Due today · ${Fmt.date(reminder.dueDate)}';
      case ReminderStatus.paused:
        return 'Paused · was due ${Fmt.date(reminder.dueDate)}';
      default:
        return 'Due in $d day${d == 1 ? '' : 's'} · ${Fmt.date(reminder.dueDate)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _statusColor(context);
    final r = reminder;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Icon(CategoryIcons.byKey(r.iconKey),
                      size: 20, color: theme.colorScheme.onSecondaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('${r.label} · ${r.recurrenceLabel}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                ),
                if (r.amount > 0)
                  Text(Fmt.currency(r.amount, code: currency),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                PopupMenuButton<String>(
                  onSelected: (v) => _onMenu(context, v),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    if (r.active)
                      const PopupMenuItem(
                          value: 'paidonly', child: Text('Mark paid (no expense)')),
                    PopupMenuItem(
                        value: 'toggle',
                        child: Text(r.active ? 'Pause' : 'Resume')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.schedule, size: 14, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_dueText(),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: color, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (r.active) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: () => _markPaid(context),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Mark paid'),
                ),
              ),
            ],
          ],
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
      case 'paidonly':
        s.markReminderPaid(reminder.id, addExpense: false);
        break;
      case 'toggle':
        s.setReminderActive(reminder.id, !reminder.active);
        break;
      case 'delete':
        _confirmDelete(context);
        break;
    }
  }

  Future<void> _markPaid(BuildContext context) async {
    final s = context.read<AppState>();
    final r = reminder;
    // No amount → nothing to book, just mark paid.
    if (r.amount <= 0) {
      await s.markReminderPaid(r.id, addExpense: false);
      return;
    }
    bool addExpense = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Mark as paid'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('“${r.title}” for ${Fmt.currency(r.amount, code: s.currency)}.'),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: addExpense,
                onChanged: (v) => setS(() => addExpense = v ?? true),
                title: const Text('Also record an expense'),
                subtitle: Text('In “${r.expenseCategory}”'),
              ),
              if (r.recurrence != Recurrence.none)
                Text('Next due: ${Fmt.date(r.nextOccurrenceAfter(DateTime.now()))}',
                    style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await s.markReminderPaid(r.id, addExpense: addExpense);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final s = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: Text('“${reminder.title}” will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await s.deleteReminder(reminder.id);
  }
}

class _ReminderForm extends StatefulWidget {
  final Reminder? existing;
  final ReminderKind? initialKind;
  const _ReminderForm({this.existing, this.initialKind});

  @override
  State<_ReminderForm> createState() => _ReminderFormState();
}

class _ReminderFormState extends State<_ReminderForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  late ReminderKind _kind;
  late Recurrence _recurrence;
  late DateTime _due;
  late bool _active;
  late bool _autoPost;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _amount = TextEditingController(
        text: (e != null && e.amount > 0) ? _trimAmount(e.amount) : '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _kind = e?.kind ?? widget.initialKind ?? ReminderKind.emi;
    _recurrence = e?.recurrence ?? Recurrence.monthly;
    _due = e?.dueDate ?? DateTime.now().add(const Duration(days: 1));
    _active = e?.active ?? true;
    _autoPost = e?.autoPost ?? false;
  }

  static String _trimAmount(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final s = context.read<AppState>();
    final r = Reminder(
      id: widget.existing?.id ?? newId('rem'),
      title: _title.text.trim(),
      kind: _kind,
      amount: double.tryParse(_amount.text.trim()) ?? 0,
      dueDate: _due,
      recurrence: _recurrence,
      notes: _notes.text.trim(),
      active: _active,
      // Auto-post only makes sense for repeating reminders.
      autoPost: _recurrence != Recurrence.none && _autoPost,
      lastPaidDate: widget.existing?.lastPaidDate,
    );
    if (_isEdit) {
      await s.updateReminder(r);
    } else {
      await s.addReminder(r);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_isEdit ? 'Edit reminder' : 'Add reminder',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(
                    labelText: 'Title', hintText: 'e.g. Home loan EMI'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ReminderKind>(
                value: _kind,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final k in ReminderKind.values)
                    DropdownMenuItem(
                      value: k,
                      child: Row(children: [
                        Icon(CategoryIcons.byKey(kindMeta[k]!.iconKey), size: 18),
                        const SizedBox(width: 10),
                        Text(kindMeta[k]!.label),
                      ]),
                    ),
                ],
                onChanged: (v) => setState(() => _kind = v ?? _kind),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (optional)',
                  helperText: 'Used to auto-record an expense when you mark it paid',
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null;
                  return double.tryParse(t) == null ? 'Enter a number' : null;
                },
              ),
              const SizedBox(height: 12),
              DatePickerField(
                date: _due,
                label: 'Next due date',
                onChanged: (d) => setState(() => _due = d),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Recurrence>(
                value: _recurrence,
                decoration: const InputDecoration(labelText: 'Repeats'),
                items: [
                  for (final rc in Recurrence.values)
                    DropdownMenuItem(
                      value: rc,
                      child: Text(_recurrenceLabel(rc)),
                    ),
                ],
                onChanged: (v) => setState(() => _recurrence = v ?? _recurrence),
              ),
              if (_recurrence != Recurrence.none) ...[
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-record on due date'),
                  subtitle: const Text(
                      'Books the expense automatically when it falls due — '
                      'no need to mark it paid'),
                  value: _autoPost,
                  onChanged: (v) => setState(() => _autoPost = v),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
                maxLines: 2,
              ),
              if (_isEdit) ...[
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text('Paused reminders stop raising alerts'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _recurrenceLabel(Recurrence r) => switch (r) {
        Recurrence.none => 'One-time (no repeat)',
        Recurrence.weekly => 'Weekly',
        Recurrence.monthly => 'Monthly',
        Recurrence.quarterly => 'Every 3 months',
        Recurrence.yearly => 'Yearly',
      };
}
