import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'common_expenses_screen.dart';
import 'family_wallet_screen.dart';

/// The "Family" tab: a shared common wallet plus a read-only view of every
/// member's common expenses. Both are backed by the one shared family workbook,
/// so what each member adds is visible to the whole household.
class FamilyScreen extends StatelessWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final inFamily = context.select<AppState, bool>((s) => s.inFamily);
    // Not set up yet → the wallet screen already shows a friendly "set a
    // Family ID" prompt, so reuse it without the tab chrome.
    if (!inFamily) return const FamilyWalletScreen();

    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: theme.scaffoldBackgroundColor,
            child: TabBar(
              dividerColor: theme.dividerTheme.color,
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
              tabs: const [
                Tab(
                  height: 48,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.account_balance_wallet_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Common wallet'),
                    ],
                  ),
                ),
                Tab(
                  height: 48,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Common expenses'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                FamilyWalletScreen(),
                CommonExpensesScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
