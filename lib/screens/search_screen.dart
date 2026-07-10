import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/category_icons.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Advanced search across **every** transaction (all months), with filters for
/// text, category, payment mode, amount range and date range. Read-only — it's
/// a lens over the data; editing still happens on the Expenses screen.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  final _min = TextEditingController();
  final _max = TextEditingController();
  String _q = '';
  String? _category; // null == all
  String _mode = 'All';
  DateTime? _from;
  DateTime? _to;
  bool _showFilters = true;

  static const _modes = ['All', 'UPI', 'Cash', 'Card', 'Bank'];

  @override
  void dispose() {
    _query.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  bool get _anyFilter =>
      _q.trim().isNotEmpty ||
      _category != null ||
      _mode != 'All' ||
      _min.text.trim().isNotEmpty ||
      _max.text.trim().isNotEmpty ||
      _from != null ||
      _to != null;

  void _reset() {
    setState(() {
      _query.clear();
      _min.clear();
      _max.clear();
      _q = '';
      _category = null;
      _mode = 'All';
      _from = null;
      _to = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cur = s.currency;
    final minV = double.tryParse(_min.text.trim());
    final maxV = double.tryParse(_max.text.trim());
    final q = _q.trim().toLowerCase();

    final results = s.expenses.where((e) {
      if (_category != null && e.category != _category) return false;
      if (_mode != 'All' && e.paymentMode != _mode) return false;
      if (minV != null && e.amount < minV) return false;
      if (maxV != null && e.amount > maxV) return false;
      if (_from != null &&
          e.date.isBefore(DateTime(_from!.year, _from!.month, _from!.day))) {
        return false;
      }
      if (_to != null &&
          e.date
              .isAfter(DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59))) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay =
            '${e.category} ${e.notes} ${e.paymentMode} ${e.amount}'
                .toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final total = results.fold(0.0, (a, e) => a + e.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search transactions'),
        actions: [
          IconButton(
            tooltip: _showFilters ? 'Hide filters' : 'Show filters',
            icon: Icon(_showFilters ? Icons.filter_list_off : Icons.filter_list),
            onPressed: () => setState(() => _showFilters = !_showFilters),
          ),
          if (_anyFilter)
            TextButton(onPressed: _reset, child: const Text('Reset')),
        ],
      ),
      body: ResponsiveCenter(
        maxWidth: 720,
        child: Column(
          children: [
            if (_showFilters) _filters(context, s),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Text('${results.length} result${results.length == 1 ? '' : 's'}',
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
            const Divider(height: 1),
            Expanded(
              child: results.isEmpty
                  ? EmptyState(
                      icon: Icons.search_off,
                      message: _anyFilter
                          ? 'No transactions match these filters.'
                          : 'Search across every month.\nSet a filter to begin.')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final e = results[i];
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                              child: Icon(
                                CategoryIcons.byKey(s.iconKeyFor(e.category)),
                                size: 20,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer,
                              ),
                            ),
                            title: Text(e.category),
                            subtitle: Text(
                              '${Fmt.date(e.date)} • ${e.paymentMode}'
                              '${e.fromFamilyWallet ? ' • Family wallet' : ''}'
                              '${e.notes.isNotEmpty ? '\n${e.notes}' : ''}',
                            ),
                            isThreeLine: e.notes.isNotEmpty,
                            trailing: Text(
                              Fmt.currency(e.amount, code: cur),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters(BuildContext context, AppState s) {
    final categories = s.categoryNames;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          TextField(
            controller: _query,
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: 'Search category, notes or amount',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _query.clear();
                        setState(() => _q = '');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('All categories')),
                    for (final c in categories)
                      DropdownMenuItem<String?>(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setState(() => _category = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _mode,
                  decoration: const InputDecoration(labelText: 'Mode'),
                  items: _modes
                      .map((m) =>
                          DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => setState(() => _mode = v ?? 'All'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _min,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Min amount'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _max,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Max amount'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _dateChip(context, isFrom: true)),
              const SizedBox(width: 12),
              Expanded(child: _dateChip(context, isFrom: false)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateChip(BuildContext context, {required bool isFrom}) {
    final value = isFrom ? _from : _to;
    return OutlinedButton.icon(
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2015),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          setState(() => isFrom ? _from = picked : _to = picked);
        }
      },
      icon: const Icon(Icons.event, size: 18),
      label: Text(
        value == null
            ? (isFrom ? 'From date' : 'To date')
            : Fmt.date(value),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
