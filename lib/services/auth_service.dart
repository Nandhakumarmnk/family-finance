import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

/// Handles Google Sign-In and produces an authenticated HTTP client that the
/// Drive service uses. We request the `drive.file` scope which grants access
/// only to files this app creates — the least-privilege option for Drive.
class AuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>[
      'email',
      drive.DriveApi.driveFileScope,
    ],
  );

  GoogleSignInAccount? _account;
  GoogleSignInAccount? get account => _account;

  /// Try to restore a previous session silently (no UI).
  Future<GoogleSignInAccount?> trySilentSignIn() async {
    _account = await _googleSignIn.signInSilently();
    return _account;
  }

  /// Interactive sign-in triggered from the login button.
  Future<GoogleSignInAccount?> signIn() async {
    _account = await _googleSignIn.signIn();
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
