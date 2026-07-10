import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/notification_service.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Notification preferences: a master on/off switch for reminder alerts and the
/// daily time they fire at. Preferences are stored on the profile, so they sync
/// across the user's devices.
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);
    final enabled = s.notificationsEnabled;
    final hour = s.reminderHour;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ResponsiveCenter(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionHeader('Reminder alerts'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: const Text('Payment reminder notifications'),
                    subtitle: Text(enabled
                        ? 'Get a phone alert on the day each payment is due'
                        : 'Reminder alerts are turned off'),
                    value: enabled,
                    onChanged: (v) => s.setNotificationsEnabled(v),
                  ),
                  if (enabled) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: const Text('Daily alert time'),
                      subtitle: Text('Reminders fire at ${_fmtHour(hour)}'),
                      trailing: FilledButton.tonal(
                        onPressed: () => _pickTime(context, s, hour),
                        child: Text(_fmtHour(hour)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                            kIsWeb
                                ? Icons.desktop_windows_outlined
                                : Icons.phone_android,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                              kIsWeb
                                  ? 'Browser notifications'
                                  : 'Device notifications',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      kIsWeb
                          ? 'Show alerts in your computer’s notification centre '
                              'while the app is open in the browser.'
                          : 'Allow notifications so payment reminders, family '
                              'requests and auto-recorded payments show in your '
                              'phone’s notification tray. Tap below and choose '
                              '“Allow” if Android asks.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _enableAndTest(context),
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text('Enable & send test'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!kIsWeb) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Scheduled reminder alerts appear in your phone’s tray even '
                  'when the app is closed. They’re on-device — no server, no cost.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Ask the OS for notification permission (from this click gesture) and fire
  /// a test notification into the notification tray / centre.
  Future<void> _enableAndTest(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final granted = await NotificationService.requestPermission();
    if (granted) {
      await NotificationService.showNow(
        id: 1,
        title: 'Notifications enabled ✓',
        body: 'Family Finance alerts will now appear here.',
      );
      messenger.showSnackBar(const SnackBar(
          content: Text('Test sent — check your notifications.')));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(kIsWeb
            ? 'Notifications are blocked. Click the lock icon in the address '
                'bar → Site settings → allow Notifications, then try again.'
            : 'Notifications are blocked. Open Android Settings → Apps → '
                'Family Finance → Notifications and turn them on.'),
      ));
    }
  }

  static String _fmtHour(int h) {
    final period = h < 12 ? 'AM' : 'PM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:00 $period';
  }

  Future<void> _pickTime(BuildContext context, AppState s, int hour) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: 0),
      helpText: 'Daily reminder time',
    );
    if (picked != null) {
      await s.setReminderHour(picked.hour);
    }
  }
}
