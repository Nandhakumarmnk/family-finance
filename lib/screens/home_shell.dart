import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/backend_service.dart';
import '../state/app_state.dart';
import 'activity_screen.dart';
import 'add_details_screen.dart';
import 'appearance_screen.dart';
import 'dashboard_screen.dart';
import 'reports_export_screen.dart';
import 'emi_screen.dart';
import 'expenses_screen.dart';
import 'family_screen.dart';
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
          PopupMenuButton<String>(
            icon: _avatar(state),
            onSelected: (v) => _onMenu(context, v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'details', child: _MenuRow(Icons.person, 'My Details')),
              const PopupMenuItem(value: 'salary', child: _MenuRow(Icons.payments, 'Salary / Income')),
              const PopupMenuItem(value: 'activity', child: _MenuRow(Icons.history, 'Activity & changes')),
              const PopupMenuItem(value: 'export', child: _MenuRow(Icons.picture_as_pdf_outlined, 'Reports & export')),
              const PopupMenuItem(value: 'appearance', child: _MenuRow(Icons.palette_outlined, 'Appearance')),
              if (BackendService.isConfigured)
                const PopupMenuItem(value: 'report', child: _MenuRow(Icons.mark_email_read_outlined, 'Email me a report')),
              const PopupMenuItem(value: 'master', child: _MenuRow(Icons.groups, 'Users / Master')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'signout', child: _MenuRow(Icons.logout, 'Sign out')),
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
      case 'activity':
        _push(context, const ActivityScreen());
        break;
      case 'appearance':
        _push(context, const AppearanceScreen());
        break;
      case 'export':
        _push(context, const ReportsExportScreen());
        break;
      case 'report':
        _emailReport(context);
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

  Future<void> _emailReport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final state = context.read<AppState>();
    messenger.showSnackBar(
      const SnackBar(content: Text('Sending your report…')),
    );
    final ok = await state.sendReportEmailNow();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Report emailed — check your inbox ✓'
            : 'Could not send the report (is the backend set up?)'),
      ),
    );
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
