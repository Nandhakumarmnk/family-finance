import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/backend_service.dart';
import '../state/app_state.dart';
import '../utils/image_data.dart';
import '../widgets/common.dart';
import '../widgets/feedback.dart';
import 'activity_screen.dart';
import 'add_details_screen.dart';
import 'appearance_screen.dart';
import 'budgets_screen.dart';
import 'master_screen.dart';
import 'member_analytics_screen.dart';
import 'notification_settings_screen.dart';
import 'reminders_screen.dart';
import 'reports_export_screen.dart';
import 'salary_screen.dart';

/// One tidy home for everything configurable — profile, money tools, insights
/// and preferences — instead of a long pop-up menu. This is the app's
/// "Settings" hub.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ResponsiveCenter(
        maxWidth: 640,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ProfileHeader(),
            if (s.refreshing) ...[
              const SizedBox(height: 12),
              const _SyncingBanner(),
            ],
            const SizedBox(height: 8),

            const SectionHeader('Account'),
            _Group(children: [
              _NavTile(
                icon: Icons.person_outline,
                title: 'My details',
                subtitle: 'Name, photo, phone, currency & family',
                onTap: () => _push(context, const AddDetailsScreen()),
              ),
              _NavTile(
                icon: Icons.payments_outlined,
                title: 'Salary / income',
                subtitle: 'Record and edit your income',
                onTap: () => _push(context, const SalaryScreen()),
              ),
            ]),
            const SizedBox(height: 8),

            const SectionHeader('Money'),
            _Group(children: [
              _NavTile(
                icon: Icons.notifications_active_outlined,
                title: 'Payment reminders',
                subtitle: s.dueReminderCount > 0
                    ? '${s.dueReminderCount} need attention'
                    : 'EMIs, bills, recharges & needs',
                badge: s.dueReminderCount,
                onTap: () => _push(context, const RemindersScreen()),
              ),
              _NavTile(
                icon: Icons.savings_outlined,
                title: 'Budgets',
                subtitle: 'Per-category monthly limits',
                onTap: () => _push(context, const BudgetsScreen()),
              ),
              _NavTile(
                icon: Icons.groups_outlined,
                title: 'Users & categories',
                subtitle: 'Family members, roles & expense categories',
                badge: s.pendingRequestCount,
                onTap: () => _push(context, const MasterScreen()),
              ),
            ]),
            const SizedBox(height: 8),

            const SectionHeader('Insights & data'),
            _Group(children: [
              _NavTile(
                icon: Icons.ios_share_outlined,
                title: 'Reports & export',
                subtitle: 'PDF statement, CSV of all your data',
                onTap: () => _push(context, const ReportsExportScreen()),
              ),
              if (s.inFamily)
                _NavTile(
                  icon: Icons.insights_outlined,
                  title: 'Family analytics',
                  subtitle: 'Per-member spending insights',
                  onTap: () => _push(context, const MemberAnalyticsScreen()),
                ),
              _NavTile(
                icon: Icons.history,
                title: 'Activity & changes',
                subtitle: 'A log of what changed and when',
                onTap: () => _push(context, const ActivityScreen()),
              ),
              if (BackendService.isConfigured)
                _NavTile(
                  icon: Icons.mark_email_read_outlined,
                  title: 'Email me a report',
                  subtitle: 'Send the latest report to your inbox',
                  onTap: () => _emailReport(context),
                ),
            ]),
            const SizedBox(height: 8),

            const SectionHeader('Preferences'),
            _Group(children: [
              _NavTile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: s.notificationsEnabled
                    ? 'On · daily at ${_fmtHour(s.reminderHour)}'
                    : 'Off',
                onTap: () =>
                    _push(context, const NotificationSettingsScreen()),
              ),
              _NavTile(
                icon: Icons.palette_outlined,
                title: 'Appearance & security',
                subtitle: 'Theme, colour, PIN & biometric lock',
                onTap: () => _push(context, const AppearanceScreen()),
              ),
            ]),
            const SizedBox(height: 16),

            _Group(children: [
              _NavTile(
                icon: Icons.logout,
                title: 'Sign out',
                subtitle: 'Your data stays safely in the cloud',
                iconColor: Theme.of(context).colorScheme.error,
                onTap: () => _confirmSignOut(context),
              ),
            ]),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  static String _fmtHour(int h) {
    final period = h < 12 ? 'AM' : 'PM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:00 $period';
  }

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'You can sign back in anytime with the same Google account.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true && context.mounted) context.read<AppState>().signOut();
  }

  Future<void> _emailReport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final state = context.read<AppState>();
    messenger
        .showSnackBar(const SnackBar(content: Text('Sending your report…')));
    final ok = await state.sendReportEmailNow();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Report emailed — check your inbox ✓'
          : 'Could not send the report (is the backend set up?)'),
    ));
  }
}

class _ProfileHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);
    final url = s.profile?.avatarUrl;
    final name = s.profile?.displayName ?? 'Signed in';
    final initial = name.trim();

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 26,
          backgroundImage: imageProviderFor(url),
          child: (url == null || url.isEmpty)
              ? Text(initial.isEmpty ? '?' : initial[0].toUpperCase(),
                  style: const TextStyle(fontSize: 20))
              : null,
        ),
        title: Text(name,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        subtitle: Text(
          [
            s.profile?.email ?? '',
            if (s.roleLabel.isNotEmpty) s.roleLabel,
          ].where((e) => e.isNotEmpty).join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const AddDetailsScreen())),
      ),
    );
  }
}

class _SyncingBanner extends StatelessWidget {
  const _SyncingBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text('Syncing your latest data…',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// A rounded card wrapping a list of tiles with dividers between them.
class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(height: 1, indent: 56));
      rows.add(children[i]);
    }
    return Card(child: Column(children: rows));
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int badge;
  final Color? iconColor;

  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = 0,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title,
          style: theme.textTheme.bodyLarge
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge > 0)
            Badge(label: Text('$badge'), backgroundColor: theme.colorScheme.error),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }
}
