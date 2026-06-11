import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/expense.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Expenses list filtered to the selected month, with add + delete.
class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cur = s.currency;
    final y = s.selectedYear;
    final m = s.selectedMonth;

    final items = s.expenses
        .where((e) => e.year == y && e.month == m)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final total = items.fold(0.0, (a, e) => a + e.amount);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: PeriodPicker(
              year: y,
              month: m,
              years: s.availableYears,
              onYear: (v) => s.selectPeriod(year: v),
              onMonth: (v) => s.selectPeriod(month: v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text('${Fmt.monthYear(y, m)} total',
                    style: Theme.of(context).textTheme.bodyMedium),
                const Spacer(),
                Text(Fmt.currency(total, code: cur),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    message: 'No expenses for this month.\nTap “Add expense”.')
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _tile(context, items[i], cur),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, Expense e, String cur) {
    return Dismissible(
      key: ValueKey(e.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => context.read<AppState>().deleteExpense(e.id),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            child: Icon(_iconFor(e.category), size: 20),
          ),
          title: Text(e.category),
          subtitle: Text(
            '${Fmt.date(e.date)} • ${e.paymentMode}'
            '${e.fromFamilyWallet ? ' • Family wallet' : ''}'
            '${e.notes.isNotEmpty ? '\n${e.notes}' : ''}',
          ),
          isThreeLine: e.notes.isNotEmpty,
          trailing: Text(Fmt.currency(e.amount, code: cur),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
    );
  }

  IconData _iconFor(String category) {
    switch (category) {
      case 'Food':
        return Icons.restaurant;
      case 'Groceries':
        return Icons.local_grocery_store;
      case 'Rent':
        return Icons.home;
      case 'Utilities':
        return Icons.bolt;
      case 'Travel':
        return Icons.directions_car;
      case 'Health':
        return Icons.local_hospital;
      case 'Education':
        return Icons.school;
      case 'Shopping':
        return Icons.shopping_bag;
      case 'Entertainment':
        return Icons.movie;
      case 'EMI':
        return Icons.account_balance;
      case 'Insurance':
        return Icons.shield;
      default:
        return Icons.category;
    }
  }

  void _addDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ExpenseForm(),
    );
  }
}

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm();

  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  String _category = Expense.categories.first;
  String _mode = 'UPI';
  DateTime _date = DateTime.now();
  bool _fromWallet = false;

  static const _modes = ['UPI', 'Cash', 'Card', 'Bank'];

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    await context.read<AppState>().addExpense(Expense(
          id: newId('exp'),
          date: _date,
          category: _category,
          amount: double.parse(_amount.text.trim()),
          paymentMode: _mode,
          notes: _notes.text.trim(),
          fromFamilyWallet: _fromWallet,
        ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final inFamily = context.read<AppState>().inFamily;
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
              Text('Add expense', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount'),
                validator: (v) =>
                    double.tryParse(v ?? '') == null ? 'Enter a valid number' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: Expense.categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _mode,
                decoration: const InputDecoration(labelText: 'Payment mode'),
                items: _modes
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _mode = v ?? _mode),
              ),
              const SizedBox(height: 12),
              DatePickerField(date: _date, onChanged: (d) => setState(() => _date = d)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
              ),
              if (inFamily)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pay from family wallet'),
                  subtitle: const Text('Deducts from the shared common wallet'),
                  value: _fromWallet,
                  onChanged: (v) => setState(() => _fromWallet = v),
                ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _submit, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
  }
}
