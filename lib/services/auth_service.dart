import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

/// A backend-agnostic snapshot of the signed-in identity, so the rest of the
/// app doesn't care whether we authenticated via Firebase or plain Google.
class AppAccount {
  final String email;
  final String displayName;
  final String? photoUrl;
  final String uid;
  final String? serverAuthCode;
  AppAccount({
    required this.email,
    required this.displayName,
    required this.uid,
    this.photoUrl,
    this.serverAuthCode,
  });
}

/// Handles sign-in. Two modes, chosen at startup:
///
/// * **Firebase mode** (when [useFirebase] is true — i.e. a real
///   `firebase_options.dart` is present): signs in with the *basic* Google
///   profile scope only. That scope is non-sensitive, so the app works for
///   **every Google user worldwide with no OAuth verification**. Data lives in
///   Firestore.
/// * **Drive mode** (legacy fallback): requests the full `drive` scope so the
///   shared family workbook can be read across accounts, and exposes an
///   authenticated HTTP client for the Drive API.
class AuthService {
  AuthService({required this.useFirebase});

  final bool useFirebase;

  /// OAuth *Web* client ID, injected via `--dart-define=GOOGLE_SERVER_CLIENT_ID`.
  /// In Firebase mode this is your Firebase project's Web client ID.
  static const String _serverClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  late final List<String> _scopes = useFirebase
      ? const <String>['email']
      : const <String>['email', drive.DriveApi.driveScope];

  // The web plugin mutates the scopes list internally, so every call gets a
  // fresh growable copy.
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: List<String>.of(_scopes),
    serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
  );

  GoogleSignInAccount? _googleAccount;
  AppAccount? _account;
  AppAccount? get account => _account;

  /// Try to restore a previous session silently (no UI).
  Future<AppAccount?> trySilentSignIn() async {
    if (useFirebase) {
      // Firebase persists the session across launches automatically.
      final u = FirebaseAuth.instance.currentUser;
      _account = u == null ? null : _fromFirebase(u);
      return _account;
    }
    _googleAccount = await _googleSignIn.signInSilently();
    if (kIsWeb && _googleAccount != null) {
      final canAccess =
          await _googleSignIn.canAccessScopes(List<String>.of(_scopes));
      if (!canAccess) _googleAccount = null;
    }
    _account = _googleAccount == null ? null : _fromGoogle(_googleAccount!);
    return _account;
  }

  /// Interactive sign-in triggered from the login button.
  Future<AppAccount?> signIn() async {
    if (useFirebase) {
      User? user;
      if (kIsWeb) {
        // Popup flow is the most robust for Firebase web Google sign-in.
        final provider = GoogleAuthProvider();
        final cred = await FirebaseAuth.instance.signInWithPopup(provider);
        user = cred.user;
      } else {
        final g = await _googleSignIn.signIn();
        if (g == null) return null;
        _googleAccount = g;
        final auth = await g.authentication;
        final credential = GoogleAuthProvider.credential(
          idToken: auth.idToken,
          accessToken: auth.accessToken,
        );
        final cred =
            await FirebaseAuth.instance.signInWithCredential(credential);
        user = cred.user;
      }
      _account = user == null ? null : _fromFirebase(user);
      return _account;
    }

    _googleAccount = await _googleSignIn.signIn();
    if (kIsWeb && _googleAccount != null) {
      final granted =
          await _googleSignIn.requestScopes(List<String>.of(_scopes));
      if (!granted) _googleAccount = null;
    }
    _account = _googleAccount == null ? null : _fromGoogle(_googleAccount!);
    return _account;
  }

  Future<void> signOut() async {
    if (useFirebase) {
      await FirebaseAuth.instance.signOut();
    }
    try {
      await _googleSignIn.signOut();
    } catch (_) {/* may be a no-op on web / popup flow */}
    _account = null;
    _googleAccount = null;
  }

  /// The signed-in user's ID token — used to authenticate the optional report
  /// backend. Null if not signed in.
  Future<String?> idToken() async {
    if (useFirebase) {
      return FirebaseAuth.instance.currentUser?.getIdToken();
    }
    final a = _googleAccount;
    if (a == null) return null;
    final auth = await a.authentication;
    return auth.idToken;
  }

  /// An authenticated client for the googleapis Drive client. Only meaningful
  /// in Drive mode; returns null under Firebase mode (Drive isn't used).
  Future<http.Client?> authenticatedClient() async {
    if (useFirebase) return null;
    return _googleSignIn.authenticatedClient();
  }

  AppAccount _fromGoogle(GoogleSignInAccount g) => AppAccount(
        email: g.email,
        displayName: g.displayName ?? g.email,
        photoUrl: g.photoUrl,
        uid: g.id,
        serverAuthCode: g.serverAuthCode,
      );

  AppAccount _fromFirebase(User u) => AppAccount(
        email: u.email ?? '',
        displayName: u.displayName ?? (u.email ?? 'User'),
        photoUrl: u.photoURL,
        uid: u.uid,
      );
}
