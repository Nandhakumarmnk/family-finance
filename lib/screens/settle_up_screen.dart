import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/wallet_entry.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Splitwise-style "who owes whom" for the shared family wallet. Every member
/// tops up the common pot; this compares each member's contribution against an
/// equal share and suggests the fewest transfers that would even things out.
///
/// Derived entirely from existing wallet entries — no new storage. It's a
/// suggestion: it never moves money on its own.
class SettleUpScreen extends StatelessWidget {
  const SettleUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cur = s.currency;
    final theme = Theme.of(context);

    if (!s.inFamily) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settle up')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Set up a family with a shared wallet to split expenses and '
              'settle up between members.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final members = s.members;
    final contrib = <String, double>{};
    double totalIn = 0, totalOut = 0;
    for (final e in s.wallet) {
      if (e.direction == WalletDirection.topUp) {
        contrib[e.memberEmail] = (contrib[e.memberEmail] ?? 0) + e.amount;
        totalIn += e.amount;
      } else {
        totalOut += e.amount;
      }
    }

    final n = members.length;
    final fair = n > 0 ? totalIn / n : 0.0;
    const eps = 0.5; // ignore sub-rupee rounding noise

    String nameOf(m) =>
        m.name.trim().isEmpty ? m.email.split('@').first : m.name.trim();

    // Per-member net vs. an equal contribution (positive == owed money back).
    final rows = [
      for (final m in members)
        _Balance(
          name: nameOf(m),
          contributed: contrib[m.email] ?? 0,
          net: (contrib[m.email] ?? 0) - fair,
        ),
    ]..sort((a, b) => b.net.compareTo(a.net));

    final plan = _settlePlan(rows, eps);

    return Scaffold(
      appBar: AppBar(title: const Text('Settle up')),
      body: ResponsiveCenter(
        maxWidth: 720,
        child: s.wallet.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: EmptyState(
                    icon: Icons.account_balance_wallet_outlined,
                    message:
                        'No shared wallet activity yet.\nAdd top-ups on the '
                        'Family tab to start splitting.',
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  Row(children: [
                    Expanded(
                      child: StatCard(
                        label: 'Pool balance',
                        value: Fmt.currency(s.walletBalance, code: cur),
                        icon: Icons.account_balance_wallet,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        label: 'Contributed',
                        value: Fmt.currency(totalIn, code: cur),
                        icon: Icons.volunteer_activism,
                        color: Colors.teal,
                        sub: 'Spent ${Fmt.compact(totalOut, code: cur)}',
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Assumes the shared wallet is split equally among '
                    '$n member${n == 1 ? '' : 's'} '
                    '(fair share ${Fmt.currency(fair, code: cur)} each). '
                    'A suggestion only — it never moves money.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 8),
                  const SectionHeader('Balances'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      child: Column(
                        children: [
                          for (final b in rows) _balanceRow(context, b, cur),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const SectionHeader('Suggested settle-up'),
                  if (plan.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            const Icon(Icons.celebration_outlined,
                                color: Colors.teal),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text('Everyone is settled up.',
                                  style: theme.textTheme.bodyLarge),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Card(
                      child: Column(
                        children: [
                          for (int i = 0; i < plan.length; i++) ...[
                            if (i > 0) const Divider(height: 1, indent: 16),
                            _planRow(context, plan[i], cur),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _balanceRow(BuildContext context, _Balance b, String cur) {
    final theme = Theme.of(context);
    final settled = b.net.abs() < 0.5;
    final positive = b.net > 0;
    final color = settled
        ? theme.colorScheme.outline
        : positive
            ? Colors.teal.shade700
            : Colors.red.shade600;
    final label = settled
        ? 'Settled'
        : positive
            ? 'Gets back ${Fmt.currency(b.net, code: cur)}'
            : 'Owes ${Fmt.currency(-b.net, code: cur)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.secondaryContainer,
            child: Text(b.name.isEmpty ? '?' : b.name[0].toUpperCase(),
                style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Put in ${Fmt.currency(b.contributed, code: cur)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _planRow(BuildContext context, _Transfer t, String cur) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        child: const Icon(Icons.arrow_forward, size: 18),
      ),
      title: Text.rich(TextSpan(children: [
        TextSpan(
            text: t.from,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const TextSpan(text: '  pays  '),
        TextSpan(
            text: t.to, style: const TextStyle(fontWeight: FontWeight.w700)),
      ])),
      trailing: Text(Fmt.currency(t.amount, code: cur),
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800)),
    );
  }

  /// Greedily match debtors to creditors into the fewest transfers.
  static List<_Transfer> _settlePlan(List<_Balance> rows, double eps) {
    final creditors = rows.where((r) => r.net > eps).toList()
      ..sort((a, b) => b.net.compareTo(a.net));
    final debtors = rows.where((r) => r.net < -eps).toList()
      ..sort((a, b) => a.net.compareTo(b.net)); // most negative first

    final cRem = creditors.map((e) => e.net).toList();
    final dRem = debtors.map((e) => -e.net).toList();
    final plan = <_Transfer>[];
    int ci = 0, di = 0;
    // Guard the loop so rounding can never spin it forever.
    var guard = 0;
    while (ci < creditors.length && di < debtors.length && guard < 1000) {
      guard++;
      final pay = cRem[ci] < dRem[di] ? cRem[ci] : dRem[di];
      if (pay > eps) {
        plan.add(_Transfer(debtors[di].name, creditors[ci].name, pay));
      }
      cRem[ci] -= pay;
      dRem[di] -= pay;
      if (cRem[ci] <= eps) ci++;
      if (dRem[di] <= eps) di++;
    }
    return plan;
  }
}

class _Balance {
  final String name;
  final double contributed;
  final double net;
  _Balance({required this.name, required this.contributed, required this.net});
}

class _Transfer {
  final String from;
  final String to;
  final double amount;
  _Transfer(this.from, this.to, this.amount);
}
