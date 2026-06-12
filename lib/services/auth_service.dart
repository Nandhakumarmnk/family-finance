import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

/// Handles Google Sign-In and produces an authenticated HTTP client that the
/// Drive service uses. We request the `drive.file` scope which grants access
/// only to files this app creates — the least-privilege option for Drive.
class AuthService {
  /// OAuth *Web* client ID, injected at build time via
  /// `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`. Required on Android so the
  /// sign-in can mint tokens for the requested Drive scope. Empty in local
  /// dev builds (sign-in then falls back to the platform default config).
  static const String _serverClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static const List<String> _scopes = <String>[
    'email',
    drive.DriveApi.driveFileScope,
  ];

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: _scopes,
    serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
  );

  GoogleSignInAccount? _account;
  GoogleSignInAccount? get account => _account;

  /// Try to restore a previous session silently (no UI).
  Future<GoogleSignInAccount?> trySilentSignIn() async {
    _account = await _googleSignIn.signInSilently();
    // On the web, restoring identity does NOT restore access to the Drive
    // scope (authorization is a separate, interactive step). If we can't reach
    // the scope silently, report "signed out" so the user can grant it via the
    // sign-in button rather than failing with a "no authenticated client" error.
    if (kIsWeb && _account != null) {
      final canAccess = await _googleSignIn.canAccessScopes(_scopes);
      if (!canAccess) _account = null;
    }
    return _account;
  }

  /// Interactive sign-in triggered from the login button.
  Future<GoogleSignInAccount?> signIn() async {
    _account = await _googleSignIn.signIn();
    // On the web, signing in only authenticates the user. Obtaining an access
    // token for the Drive scope requires an explicit scope request — without it
    // `authenticatedClient()` returns null. (No-op on mobile, where the scopes
    // are granted as part of sign-in.)
    if (kIsWeb && _account != null) {
      final granted = await _googleSignIn.requestScopes(_scopes);
      if (!granted) _account = null;
    }
    return _account;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _account = null;
  }

  /// An authenticated client suitable for the googleapis Drive client.
  /// Returns null if not signed in.
  Future<http.Client?> authenticatedClient() async {
    return _googleSignIn.authenticatedClient();
  }
}
