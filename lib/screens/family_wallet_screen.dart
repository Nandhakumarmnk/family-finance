import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/wallet_entry.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Shared family "common wallet": every member can top-up or spend, and the
/// balance + history is stored in the shared family workbook on Drive.
class FamilyWalletScreen extends StatelessWidget {
  const FamilyWalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (!s.inFamily) return const _NoFamily();

    final cur = s.currency;
    final entries = [...s.wallet]..sort((a, b) => b.date.compareTo(a.date));
    final balance = s.walletBalance;
    final totalIn = s.wallet.where((e) => e.direction == WalletDirection.topUp).fold(0.0, (a, e) => a + e.amount);
    final totalOut = s.wallet.where((e) => e.direction == WalletDirection.spend).fold(0.0, (a, e) => a + e.amount);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _entryDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Wallet entry'),
      ),
      body: ResponsiveCenter(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          children: [
          _balanceCard(context, s, balance, cur),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: StatCard(label: 'Total added', value: Fmt.currency(totalIn, code: cur), icon: Icons.add_circle, color: Colors.green)),
            const SizedBox(width: 12),
            Expanded(child: StatCard(label: 'Total spent', value: Fmt.currency(totalOut, code: cur), icon: Icons.remove_circle, color: Colors.red)),
          ]),
          const SizedBox(height: 8),
          SectionHeader('History', trailing: TextButton.icon(
            onPressed: () => _invite(context),
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('Invite'),
          )),
          if (entries.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(24), child: EmptyState(icon: Icons.account_balance_wallet_outlined, message: 'No wallet activity yet.')))
          else
            ...entries.map((e) => _entryTile(context, e, cur)),
        ],
        ),
      ),
    );
  }

  Widget _balanceCard(BuildContext context, AppState s, double balance, String cur) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, Color.lerp(primary, Colors.black, 0.4)!],
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.family_restroom, size: 18, color: Colors.white.withOpacity(0.9)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(s.family?.familyName ?? 'Family wallet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${s.members.length} member${s.members.length == 1 ? '' : 's'}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 18),
          Text('Common wallet balance',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white.withOpacity(0.85))),
          const SizedBox(height: 2),
          Text(Fmt.currency(balance, code: cur),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  Widget _entryTile(BuildContext context, WalletEntry e, String cur) {
    final isIn = e.direction == WalletDirection.topUp;
    return Dismissible(
      key: ValueKey(e.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => context.read<AppState>().deleteWalletEntry(e.id),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: (isIn ? Colors.green : Colors.red).withOpacity(0.12),
            child: Icon(isIn ? Icons.add : Icons.remove, color: isIn ? Colors.green.shade700 : Colors.red.shade700),
          ),
          title: Text(e.purpose.isEmpty ? (isIn ? 'Top-up' : 'Spend') : e.purpose),
          subtitle: Text('${e.memberName} • ${Fmt.date(e.date)}'),
          trailing: Text('${isIn ? '+' : '-'}${Fmt.currency(e.amount, code: cur)}',
              style: TextStyle(fontWeight: FontWeight.bold, color: isIn ? Colors.green.shade700 : Colors.red.shade700)),
        ),
      ),
    );
  }

  void _entryDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _WalletForm(),
    );
  }

  Future<void> _invite(BuildContext context) async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite family member'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Their Google email'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Invite')),
        ],
      ),
    );
    if (email == null || email.isEmpty || !context.mounted) return;
    final link = await context.read<AppState>().inviteMember(email);
    if (!context.mounted) return;
    if (link != null) {
      await Clipboard.setData(ClipboardData(text: link));
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(link != null ? 'Invited $email — share link copied' : 'Invited $email'),
    ));
  }
}

class _WalletForm extends StatefulWidget {
  const _WalletForm();

  @override
  State<_WalletForm> createState() => _WalletFormState();
}

class _WalletFormState extends State<_WalletForm> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _purpose = TextEditingController();
  WalletDirection _dir = WalletDirection.topUp;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _purpose.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return; // guard against double/triple taps while saving
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final p = context.read<AppState>().profile!;
    await context.read<AppState>().addWalletEntry(WalletEntry(
          id: newId('wal'),
          date: _date,
          memberEmail: p.email,
          memberName: p.displayName,
          direction: _dir,
          amount: double.parse(_amount.text.trim()),
          purpose: _purpose.text.trim(),
        ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Wallet entry', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            SegmentedButton<WalletDirection>(
              segments: const [
                ButtonSegment(value: WalletDirection.topUp, label: Text('Add money'), icon: Icon(Icons.add)),
                ButtonSegment(value: WalletDirection.spend, label: Text('Spend'), icon: Icon(Icons.remove)),
              ],
              selected: {_dir},
              onSelectionChanged: (v) => setState(() => _dir = v.first),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount'),
              validator: (v) => double.tryParse(v ?? '') == null ? 'Enter a number' : null,
            ),
            const SizedBox(height: 12),
            DatePickerField(date: _date, onChanged: (d) => setState(() => _date = d)),
            const SizedBox(height: 12),
            TextFormField(controller: _purpose, decoration: const InputDecoration(labelText: 'Purpose (optional)')),
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
    );
  }
}

class _NoFamily extends StatelessWidget {
  const _NoFamily();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.family_restroom, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('No family set up yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Open “My Details” from the top-right menu and set a Family ID '
              'to create a shared common wallet for your family.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
