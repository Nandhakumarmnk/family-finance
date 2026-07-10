/// No-op notifier for non-web platforms. On mobile/desktop, OS notifications
/// go through `flutter_local_notifications` (see NotificationService), so this
/// stub simply does nothing and reports permission as already granted.
class WebNotifier {
  static String get permission => 'granted';
  static bool get supported => false;
  static Future<bool> requestPermission() async => true;
  static void show(String title, String body) {}
}
