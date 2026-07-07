import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
            if (kIsWeb)
              Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Note: scheduled device notifications work on the mobile '
                    'app. On the web the reminders list still shows what’s due.',
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Alerts appear in your phone’s notification tray even when '
                  'the app is closed. They’re scheduled on-device — no server, '
                  'no cost.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
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
