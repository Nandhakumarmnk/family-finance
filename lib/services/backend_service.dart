import 'dart:convert';

import 'package:http/http.dart' as http;

/// Talks to the optional daily-report backend (see /server). The backend URL
/// is injected at build time via `--dart-define=GOOGLE_BACKEND_URL=...`. When
/// it's not configured, every call is a no-op so the app works standalone.
class BackendService {
  static const String _baseUrl = String.fromEnvironment('GOOGLE_BACKEND_URL');

  static bool get isConfigured => _baseUrl.isNotEmpty;

  /// Hand the backend a one-time offline auth code so it can email a daily
  /// report, along with the household role so a "parent" can receive the
  /// consolidated family report. Fire-and-forget: the daily email is a
  /// background nicety and must never block or fail sign-in.
  static Future<void> linkForDailyReport(
    String? serverAuthCode, {
    String familyId = '',
    String role = 'member',
  }) async {
    if (_baseUrl.isEmpty || serverAuthCode == null || serverAuthCode.isEmpty) {
      return;
    }
    try {
      await http
          .post(
            Uri.parse(_baseUrl),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'serverAuthCode': serverAuthCode,
              'familyId': familyId,
              'role': role,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Intentionally swallowed — never disrupt the sign-in flow.
    }
  }
}
