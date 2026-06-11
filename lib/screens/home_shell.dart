import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'add_details_screen.dart';
import 'dashboard_screen.dart';
import 'emi_screen.dart';
import 'expenses_screen.dart';
import 'family_wallet_screen.dart';
import 'master_screen.dart';
import 'reports_screen.dart';
import 'salary_screen.dart';

/// Main authenticated shell: bottom navigation between the primary screens,
/// with secondary screens (Profile/Details, Salary, Master users, Sign out)
/// reachable from the app-bar menu.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['Dashboard', 'Expenses', 'EMIs', 'Reports', 'Family'];

  final _pages = const [
    DashboardScreen(),
    ExpensesScreen(),
    EmiScreen(),
    ReportsScreen(),
    FamilyWalletScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          if (state.busy)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          PopupMenuButton<String>(
            icon: _avatar(state),
            onSelected: (v) => _onMenu(context, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'details', child: _MenuRow(Icons.person, 'My Details')),
              PopupMenuItem(value: 'salary', child: _MenuRow(Icons.payments, 'Salary / Income')),
              PopupMenuItem(value: 'master', child: _MenuRow(Icons.groups, 'Users / Master')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'signout', child: _MenuRow(Icons.logout, 'Sign out')),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Expenses'),
          NavigationDestination(icon: Icon(Icons.account_balance_outlined), selectedIcon: Icon(Icons.account_balance), label: 'EMIs'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Reports'),
          NavigationDestination(icon: Icon(Icons.family_restroom_outlined), selectedIcon: Icon(Icons.family_restroom), label: 'Family'),
        ],
      ),
    );
  }

  Widget _avatar(AppState state) {
    final url = state.profile?.photoUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(radius: 14, backgroundImage: NetworkImage(url));
    }
    final initial = (state.profile?.displayName ?? '?').trim();
    return CircleAvatar(
      radius: 14,
      child: Text(initial.isEmpty ? '?' : initial[0].toUpperCase(),
          style: const TextStyle(fontSize: 14)),
    );
  }

  void _onMenu(BuildContext context, String v) {
    switch (v) {
      case 'details':
        _push(context, const AddDetailsScreen());
        break;
      case 'salary':
        _push(context, const SalaryScreen());
        break;
      case 'master':
        _push(context, const MasterScreen());
        break;
      case 'signout':
        context.read<AppState>().signOut();
        break;
    }
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuRow(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 20),
      const SizedBox(width: 12),
      Text(label),
    ]);
  }
}
