import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/emi.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// EMI / loan tracker. Shows each loan's progress, remaining EMIs and amount,
/// next due date, and lets the user record a paid instalment.
class EmiScreen extends StatelessWidget {
  const EmiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cur = s.currency;
    final items = [...s.emis]
      ..sort((a, b) {
        if (a.isClosed != b.isClosed) return a.isClosed ? 1 : -1;
        return a.nextDueDate.compareTo(b.nextDueDate);
      });

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add EMI'),
      ),
      body: ResponsiveCenter(
        maxWidth: 720,
        child: items.isEmpty
          ? const EmptyState(
              icon: Icons.account_balance_outlined,
              message: 'No loans/EMIs tracked yet.\nTap “Add EMI”.')
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              children: [
                _summary(context, s, cur),
                const SizedBox(height: 8),
                ...items.map((e) => _emiCard(context, e, cur)),
              ],
            ),
      ),
    );
  }

  Widget _summary(BuildContext context, AppState s, String cur) {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Monthly outgo',
            value: Fmt.currency(s.totalEmiMonthly, code: cur),
            icon: Icons.event_repeat,
            color: Colors.deepPurple,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            label: 'Total remaining',
            value: Fmt.currency(s.totalEmiRemaining, code: cur),
            icon: Icons.hourglass_bottom,
            color: Colors.brown,
          ),
        ),
      ],
    );
  }

  Widget _emiCard(BuildContext context, Emi e, String cur) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(e.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                if (e.isClosed)
                  const Chip(
                    label: Text('Closed'),
                    visualDensity: VisualDensity.compact,
                  )
                else
                  Text(Fmt.currency(e.monthlyAmount, code: cur),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'pay') context.read<AppState>().recordEmiPayment(e.id);
                    if (v == 'edit') _openForm(context, existing: e);
                    if (v == 'del') _confirmDelete(context, e);
                  },
                  itemBuilder: (_) => [
                    if (!e.isClosed)
                      const PopupMenuItem(value: 'pay', child: Text('Record payment')),
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'del', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: e.progress, minHeight: 8),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _kv('Paid', '${e.paidMonths}/${e.totalMonths}'),
                _kv('Remaining EMIs', '${e.remainingMonths}'),
                _kv('Remaining amt', Fmt.currency(e.amountRemaining, code: cur)),
                if (!e.isClosed) _kv('Next due', Fmt.date(e.nextDueDate)),
                _kv('Ends', Fmt.date(e.payoffDate)),
                if (e.annualInterestRate > 0)
                  _kv('Interest', '${e.annualInterestRate}%'),
              ],
            ),
            if (!e.isClosed) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.read<AppState>().recordEmiPayment(e.id),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Record this month’s payment'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Builder(builder: (context) {
      final theme = Theme.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(k, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
          Text(v, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      );
    });
  }

  void _addDialog(BuildContext context) => _openForm(context);

  void _openForm(BuildContext context, {Emi? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EmiForm(existing: existing),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Emi e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete EMI?'),
        content: Text('“${e.name}” will be removed from your loans.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      context.read<AppState>().deleteEmi(e.id);
    }
  }
}

/// How the user wants to capture the loan's cost: by an interest rate, or by
/// entering the remaining/outstanding balance directly.
enum _EmiExtra { interest, remaining }

class _EmiForm extends StatefulWidget {
  final Emi? existing;
  const _EmiForm({this.existing});

  @override
  State<_EmiForm> createState() => _EmiFormState();
}

class _EmiFormState extends State<_EmiForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _monthly;
  late final TextEditingController _total;
  late final TextEditingController _paid;
  late final TextEditingController _rate;
  late final TextEditingController _outstanding;
  late _EmiExtra _extra;
  late DateTime _start;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _monthly =
        TextEditingController(text: e != null ? _num(e.monthlyAmount) : '');
    _total = TextEditingController(text: e != null ? '${e.totalMonths}' : '');
    _paid = TextEditingController(text: e != null ? '${e.paidMonths}' : '0');
    _rate = TextEditingController(
        text: e != null ? _num(e.annualInterestRate) : '0');
    _outstanding = TextEditingController(
        text: (e != null && e.outstandingAmount > 0)
            ? _num(e.outstandingAmount)
            : '');
    _extra = (e != null && e.outstandingAmount > 0)
        ? _EmiExtra.remaining
        : _EmiExtra.interest;
    _start = e?.startDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _name.dispose();
    _monthly.dispose();
    _total.dispose();
    _paid.dispose();
    _rate.dispose();
    _outstanding.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return; // guard against double/triple taps while saving
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final byInterest = _extra == _EmiExtra.interest;
    final app = context.read<AppState>();
    final emi = Emi(
      id: widget.existing?.id ?? newId('emi'),
      name: _name.text.trim(),
      monthlyAmount: double.parse(_monthly.text.trim()),
      totalMonths: int.parse(_total.text.trim()),
      paidMonths: int.tryParse(_paid.text.trim()) ?? 0,
      annualInterestRate:
          byInterest ? (double.tryParse(_rate.text.trim()) ?? 0) : 0,
      outstandingAmount:
          byInterest ? 0 : (double.tryParse(_outstanding.text.trim()) ?? 0),
      startDate: _start,
    );
    if (_isEdit) {
      await app.updateEmi(emi);
    } else {
      await app.addEmi(emi);
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
              Text(_isEdit ? 'Edit EMI / loan' : 'Add EMI / loan',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Loan name', hintText: 'Home loan'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _monthly,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monthly EMI amount'),
                validator: (v) => double.tryParse(v ?? '') == null ? 'Enter a number' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _total,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Total months'),
                      validator: (v) => int.tryParse(v ?? '') == null ? 'Number' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _paid,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Paid so far'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Add either',
                    style: Theme.of(context).textTheme.labelLarge),
              ),
              const SizedBox(height: 8),
              SegmentedButton<_EmiExtra>(
                segments: const [
                  ButtonSegment(
                      value: _EmiExtra.interest, label: Text('Interest %')),
                  ButtonSegment(
                      value: _EmiExtra.remaining, label: Text('Remaining amt')),
                ],
                selected: {_extra},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _extra = v.first),
              ),
              const SizedBox(height: 12),
              if (_extra == _EmiExtra.interest)
                TextFormField(
                  controller: _rate,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Interest % per year'),
                )
              else
                TextFormField(
                  controller: _outstanding,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Total remaining / pending amount',
                    helperText: 'Overrides the monthly × remaining estimate',
                  ),
                ),
              const SizedBox(height: 12),
              DatePickerField(
                date: _start,
                label: 'Start date',
                onChanged: (d) => setState(() => _start = d),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEdit ? 'Save changes' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
