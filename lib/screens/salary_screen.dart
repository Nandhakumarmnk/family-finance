import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/salary.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Salary / income list with add + delete.
class SalaryScreen extends StatelessWidget {
  const SalaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cur = s.currency;
    final items = [...s.salaries]..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(title: const Text('Salary / Income')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Add income'),
      ),
      body: ResponsiveCenter(
        maxWidth: 720,
        child: items.isEmpty
          ? const EmptyState(
              icon: Icons.payments_outlined,
              message: 'No income recorded yet.\nTap “Add income” to start.')
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final s0 = items[i];
                return Card(
                  child: ListTile(
                    onTap: () => _openForm(context, existing: s0),
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.shade50,
                      child: Icon(Icons.south_west, color: Colors.green.shade700),
                    ),
                    title: Text(s0.source),
                    subtitle: Text(
                        '${Fmt.date(s0.date)}${s0.notes.isNotEmpty ? ' • ${s0.notes}' : ''}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(Fmt.currency(s0.amount, code: cur),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') {
                              _openForm(context, existing: s0);
                            } else if (v == 'delete') {
                              _confirmDelete(context, s0);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      ),
    );
  }

  void _openForm(BuildContext context, {Salary? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SalaryForm(existing: existing),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Salary s0) async {
    final cur = context.read<AppState>().currency;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete income?'),
        content: Text(
            '${s0.source} · ${Fmt.currency(s0.amount, code: cur)} on ${Fmt.date(s0.date)} will be removed.'),
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
      context.read<AppState>().deleteSalary(s0.id);
    }
  }
}

class _SalaryForm extends StatefulWidget {
  final Salary? existing;
  const _SalaryForm({this.existing});

  @override
  State<_SalaryForm> createState() => _SalaryFormState();
}

class _SalaryFormState extends State<_SalaryForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _source;
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  late DateTime _date;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _source = TextEditingController(text: e?.source ?? 'Primary salary');
    _amount = TextEditingController(
        text: e != null ? _trimAmount(e.amount) : '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _date = e?.date ?? DateTime.now();
  }

  static String _trimAmount(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _source.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return; // guard against double/triple taps while saving
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final app = context.read<AppState>();
    final salary = Salary(
      id: widget.existing?.id ?? newId('sal'),
      date: _date,
      source: _source.text.trim(),
      amount: double.parse(_amount.text.trim()),
      notes: _notes.text.trim(),
    );
    if (_isEdit) {
      await app.updateSalary(salary);
    } else {
      await app.addSalary(salary);
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isEdit ? 'Edit income' : 'Add income',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _source,
              decoration: const InputDecoration(labelText: 'Source'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount', prefixIcon: Icon(Icons.currency_rupee)),
              validator: (v) => double.tryParse(v ?? '') == null ? 'Enter a valid number' : null,
            ),
            const SizedBox(height: 12),
            _DatePickerTile(date: _date, onChanged: (d) => setState(() => _date = d)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
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
    );
  }
}

/// Reusable date picker tile used by several forms.
class _DatePickerTile extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  const _DatePickerTile({required this.date, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2015),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Date', prefixIcon: Icon(Icons.event)),
        child: Text(Fmt.date(date)),
      ),
    );
  }
}
