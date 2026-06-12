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
      body: items.isEmpty
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
                    if (v == 'del') context.read<AppState>().deleteEmi(e.id);
                  },
                  itemBuilder: (_) => [
                    if (!e.isClosed)
                      const PopupMenuItem(value: 'pay', child: Text('Record payment')),
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

  void _addDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _EmiForm(),
    );
  }
}

class _EmiForm extends StatefulWidget {
  const _EmiForm();

  @override
  State<_EmiForm> createState() => _EmiFormState();
}

class _EmiFormState extends State<_EmiForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _monthly = TextEditingController();
  final _total = TextEditingController();
  final _paid = TextEditingController(text: '0');
  final _rate = TextEditingController(text: '0');
  DateTime _start = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _monthly.dispose();
    _total.dispose();
    _paid.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return; // guard against double/triple taps while saving
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    await context.read<AppState>().addEmi(Emi(
          id: newId('emi'),
          name: _name.text.trim(),
          monthlyAmount: double.parse(_monthly.text.trim()),
          totalMonths: int.parse(_total.text.trim()),
          paidMonths: int.tryParse(_paid.text.trim()) ?? 0,
          annualInterestRate: double.tryParse(_rate.text.trim()) ?? 0,
          startDate: _start,
        ));
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
              Text('Add EMI / loan', style: Theme.of(context).textTheme.titleLarge),
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _rate,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Interest % (optional)'),
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
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
