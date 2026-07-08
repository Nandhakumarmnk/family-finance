import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/expense.dart';
import '../state/app_state.dart';
import '../utils/category_icons.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Expenses list for the selected month, with search, a category filter, and
/// add / edit / delete (so a wrongly-entered expense can be corrected).
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _categoryFilter; // null == all categories

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cur = s.currency;
    final y = s.selectedYear;
    final m = s.selectedMonth;

    // Month → search text (category / notes / amount) → category filter.
    final q = _query.trim().toLowerCase();
    final items = s.expenses.where((e) {
      if (e.year != y || e.month != m) return false;
      if (_categoryFilter != null && e.category != _categoryFilter) return false;
      if (q.isEmpty) return true;
      return e.category.toLowerCase().contains(q) ||
          e.notes.toLowerCase().contains(q) ||
          e.paymentMode.toLowerCase().contains(q) ||
          e.amount.toStringAsFixed(2).contains(q);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final total = items.fold(0.0, (a, e) => a + e.amount);

    // Categories actually used this month, for the filter dropdown.
    final monthCategories = (s.expenses
            .where((e) => e.year == y && e.month == m)
            .map((e) => e.category)
            .toSet()
            .toList()
          ..sort());

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: ResponsiveCenter(
        maxWidth: 720,
        child: Column(
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search category, notes or amount',
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
            if (monthCategories.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: const Text('All'),
                        selected: _categoryFilter == null,
                        onSelected: (_) =>
                            setState(() => _categoryFilter = null),
                      ),
                    ),
                    for (final c in monthCategories)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(c),
                          selected: _categoryFilter == c,
                          onSelected: (sel) =>
                              setState(() => _categoryFilter = sel ? c : null),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    (q.isEmpty && _categoryFilter == null)
                        ? '${Fmt.monthYear(y, m)} total'
                        : 'Filtered total (${items.length})',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
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
                  ? EmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: (q.isNotEmpty || _categoryFilter != null)
                          ? 'No expenses match your search.'
                          : 'No expenses for this month.\nTap “Add expense”.')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _tile(context, items[i], cur),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, Expense e, String cur) {
    return Dismissible(
      key: ValueKey(e.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context, e),
      onDismissed: (_) => context.read<AppState>().deleteExpense(e.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        child: ListTile(
          onTap: () => _openForm(context, existing: e),
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            child: Icon(
              CategoryIcons.byKey(
                  context.read<AppState>().iconKeyFor(e.category)),
              size: 20,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
          title: Row(
            children: [
              Flexible(child: Text(e.category)),
              if (e.hasReceipt) ...[
                const SizedBox(width: 6),
                Icon(Icons.receipt_long,
                    size: 15, color: Theme.of(context).colorScheme.primary),
              ],
            ],
          ),
          subtitle: Text(
            '${Fmt.date(e.date)} • ${e.paymentMode}'
            '${e.fromFamilyWallet ? ' • Family wallet' : ''}'
            '${e.notes.isNotEmpty ? '\n${e.notes}' : ''}',
          ),
          isThreeLine: e.notes.isNotEmpty,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(Fmt.currency(e.amount, code: cur),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'edit':
                      _openForm(context, existing: e);
                      break;
                    case 'receipt':
                      _viewReceipt(context, e);
                      break;
                    case 'delete':
                      _confirmDelete(context, e).then((ok) {
                        if (ok == true) {
                          context.read<AppState>().deleteExpense(e.id);
                        }
                      });
                      break;
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (e.hasReceipt)
                    const PopupMenuItem(
                        value: 'receipt', child: Text('View bill / receipt')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, Expense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text(
            '${e.category} · ${Fmt.currency(e.amount, code: context.read<AppState>().currency)} on ${Fmt.date(e.date)} will be removed.'),
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
    // When invoked by Dismissible, returning true lets it complete the swipe
    // (the model already deletes on onDismissed below); for the menu path the
    // caller performs the delete.
    return ok ?? false;
  }

  /// Full-screen, pinch-to-zoom view of a bill / receipt. The image is fetched
  /// on demand from Firestore (stored as base64), so it's only pulled when the
  /// user actually opens it. Legacy http URLs, if any, still load directly.
  void _viewReceipt(BuildContext context, Expense e) {
    if (!e.hasReceipt) return;
    final legacyUrl =
        e.receiptUrl.startsWith('http') ? e.receiptUrl : null;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: legacyUrl != null
                    ? Image.network(
                        legacyUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (c, err, s) => const Padding(
                            padding: EdgeInsets.all(40),
                            child: Text('Could not load the receipt.')),
                      )
                    : FutureBuilder<Uint8List?>(
                        future: context.read<AppState>().loadReceipt(e.id),
                        builder: (c, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return const Padding(
                                padding: EdgeInsets.all(40),
                                child: CircularProgressIndicator());
                          }
                          final bytes = snap.data;
                          if (bytes == null) {
                            return const Padding(
                                padding: EdgeInsets.all(40),
                                child: Text('Could not load the receipt.'));
                          }
                          return Image.memory(bytes, fit: BoxFit.contain);
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openForm(BuildContext context, {Expense? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ExpenseForm(existing: existing),
    );
  }
}

class _ExpenseForm extends StatefulWidget {
  final Expense? existing;
  const _ExpenseForm({this.existing});

  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  final _picker = ImagePicker();
  late String _category;
  late String _mode;
  late DateTime _date;
  late bool _fromWallet;
  bool _saving = false;
  Uint8List? _receiptBytes; // newly picked receipt photo, uploaded on save

  bool get _isEdit => widget.existing != null;

  static const _modes = ['UPI', 'Cash', 'Card', 'Bank'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final names = context.read<AppState>().categoryNames;
    _amount = TextEditingController(
        text: e != null ? _trimAmount(e.amount) : '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _category = e?.category ?? (names.isNotEmpty ? names.first : 'Other');
    _mode = e?.paymentMode ?? 'UPI';
    _date = e?.date ?? DateTime.now();
    _fromWallet = e?.fromFamilyWallet ?? false;
  }

  static String _trimAmount(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 70,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (mounted) setState(() => _receiptBytes = bytes);
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final app = context.read<AppState>();
    final id = widget.existing?.id ?? newId('exp');

    // Keep the existing receipt unless the user picked a new one.
    var receiptUrl = widget.existing?.receiptUrl ?? '';
    if (_receiptBytes != null) {
      final url = await app.uploadReceipt(id, _receiptBytes!);
      if (url != null) receiptUrl = url;
    }

    final expense = Expense(
      id: id,
      date: _date,
      category: _category,
      amount: double.parse(_amount.text.trim()),
      paymentMode: _mode,
      notes: _notes.text.trim(),
      fromFamilyWallet: _fromWallet,
      receiptUrl: receiptUrl,
    );
    if (_isEdit) {
      await app.updateExpense(expense);
    } else {
      await app.addExpense(expense);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final inFamily = app.inFamily;
    final cats = app.categories;
    final names = cats.map((c) => c.name).toList();
    final value = names.contains(_category)
        ? _category
        : (names.isNotEmpty ? names.first : null);
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
              Text(_isEdit ? 'Edit expense' : 'Add expense',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount'),
                validator: (v) => double.tryParse(v ?? '') == null
                    ? 'Enter a valid number'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: value,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: cats
                    .map((c) => DropdownMenuItem(
                          value: c.name,
                          child: Row(
                            children: [
                              Icon(CategoryIcons.byKey(c.iconKey), size: 18),
                              const SizedBox(width: 10),
                              Text(c.name),
                            ],
                          ),
                        ))
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
              DatePickerField(
                  date: _date, onChanged: (d) => setState(() => _date = d)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration:
                    const InputDecoration(labelText: 'Notes (optional)'),
              ),
              if (inFamily)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pay from family wallet'),
                  subtitle:
                      const Text('Deducts from the shared common wallet'),
                  value: _fromWallet,
                  onChanged: (v) => setState(() => _fromWallet = v),
                ),
              if (app.canAttachFiles) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Bill / receipt (optional)',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _receiptBytes == null
                      ? OutlinedButton.icon(
                          onPressed: _pickReceipt,
                          icon: const Icon(Icons.attach_file, size: 18),
                          label: Text(
                              (widget.existing?.hasReceipt ?? false)
                                  ? 'Replace bill / receipt'
                                  : 'Attach bill / receipt'),
                        )
                      : Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(_receiptBytes!,
                                  width: 56, height: 56, fit: BoxFit.cover),
                            ),
                            const SizedBox(width: 12),
                            const Text('Bill / receipt attached'),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  setState(() => _receiptBytes = null),
                            ),
                          ],
                        ),
                ),
              ],
              const SizedBox(height: 8),
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
