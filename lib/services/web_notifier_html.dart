import 'dart:html' as html;

/// Web implementation backed by the browser's Notification API. Shows OS-level
/// notifications in the system notification centre (Windows action center,
/// macOS notifications, Android Chrome tray) once the user grants permission.
///
/// These appear even when the browser tab is in the background, but — without a
/// service-worker push backend — not when the browser is fully closed. Good
/// enough for in-session alerts (a new join request, a due payment on open).
class WebNotifier {
  static bool get supported => html.Notification.supported;

  /// 'granted' | 'denied' | 'default' | 'unsupported'.
  static String get permission =>
      supported ? (html.Notification.permission ?? 'default') : 'unsupported';

  /// Ask the browser for permission. Best called from a user gesture (a click);
  /// some browsers ignore it otherwise. Returns true when granted.
  static Future<bool> requestPermission() async {
    if (!supported) return false;
    if (html.Notification.permission == 'granted') return true;
    try {
      final result = await html.Notification.requestPermission();
      return result == 'granted';
    } catch (_) {
      return false;
    }
  }

  static void show(String title, String body) {
    if (!supported || html.Notification.permission != 'granted') return;
    try {
      html.Notification(title, body: body);
    } catch (_) {
      // Best-effort — a notification failure must never disrupt the app.
    }
  }
}
