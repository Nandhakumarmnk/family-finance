import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/image_data.dart';
import 'add_details_screen.dart';
import 'dashboard_screen.dart';
import 'emi_screen.dart';
import 'expenses_screen.dart';
import 'family_screen.dart';
import 'reminders_screen.dart';
import 'reports_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// Main authenticated shell: bottom navigation between the primary screens,
/// with a compact avatar menu (My details · Settings · Sign out) — everything
/// else now lives in the Settings hub.
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
    FamilyScreen(),
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
          IconButton(
            tooltip: 'Search transactions',
            icon: const Icon(Icons.search),
            onPressed: () => _push(context, const SearchScreen()),
          ),
          _reminderBell(context, state),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _push(context, const SettingsScreen()),
          ),
          PopupMenuButton<String>(
            // Badge the menu when the head has join requests waiting.
            icon: state.pendingRequestCount > 0
                ? Badge.count(
                    count: state.pendingRequestCount, child: _avatar(state))
                : _avatar(state),
            onSelected: (v) => _onMenu(context, v),
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state.profile?.displayName ?? 'Signed in',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (state.roleLabel.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                              state.isFamilyHead
                                  ? Icons.shield_moon_outlined
                                  : Icons.person_outline,
                              size: 14),
                          const SizedBox(width: 4),
                          Text(state.roleLabel,
                              style: const TextStyle(fontSize: 12)),
                        ]),
                      ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: 'details', child: _MenuRow(Icons.person, 'My details')),
              const PopupMenuItem(
                  value: 'settings',
                  child: _MenuRow(Icons.settings, 'Settings')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: 'signout', child: _MenuRow(Icons.logout, 'Sign out')),
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

  /// Bell icon that opens the reminders screen, badged with the number of
  /// reminders that are overdue or due soon.
  Widget _reminderBell(BuildContext context, AppState state) {
    final count = state.dueReminderCount;
    final icon = IconButton(
      tooltip: 'Payment reminders',
      icon: const Icon(Icons.notifications_outlined),
      onPressed: () => _push(context, const RemindersScreen()),
    );
    if (count == 0) return icon;
    return Badge.count(count: count, child: icon);
  }

  Widget _avatar(AppState state) {
    final provider = imageProviderFor(state.profile?.avatarUrl);
    if (provider != null) {
      return CircleAvatar(radius: 14, backgroundImage: provider);
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
      case 'settings':
        _push(context, const SettingsScreen());
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
