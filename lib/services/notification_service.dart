import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';
import '../utils/format.dart';

/// Schedules **device** notifications for upcoming payment reminders. They show
/// up in the phone's notification tray (like WhatsApp or email) and fire even
/// when the app is closed. Purely on-device (no server, no cloud messaging),
/// so it stays free and private. No-op on web (browsers can't schedule these).
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const String _channelId = 'payment_reminders';
  static const String _channelName = 'Payment reminders';

  /// One-time setup: init the plugin, the timezone DB, and request permission.
  static Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      tzdata.initializeTimeZones();
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      _ready = true;
    } catch (_) {
      _ready = false; // notifications are best-effort; never block the app
    }
  }

  /// Cancel everything and (re)schedule a tray notification for each active
  /// reminder, at 9am on its due date. Call whenever reminders change.
  static Future<void> sync(List<Reminder> reminders, {String currency = 'INR'}) async {
    if (kIsWeb) return;
    if (!_ready) await init();
    if (!_ready) return;
    try {
      await _plugin.cancelAll();

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Reminders for bills, EMIs and other payments',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

      final now = DateTime.now();
      for (final r in reminders) {
        if (!r.active) continue;
        // Fire at 9am on the due date; skip ones already in the past.
        final at = DateTime(r.dueDate.year, r.dueDate.month, r.dueDate.day, 9);
        if (!at.isAfter(now)) continue;
        final body = r.amount > 0
            ? '${Fmt.currency(r.amount, code: currency)} due today'
            : 'Payment due today';
        await _plugin.zonedSchedule(
          r.id.hashCode & 0x7fffffff, // stable, non-negative notification id
          'Payment due: ${r.title}',
          body,
          tz.TZDateTime.from(at, tz.local),
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (_) {
      // Best-effort — a scheduling failure must never disrupt the app.
    }
  }

  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
