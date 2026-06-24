import 'package:local_auth/local_auth.dart';

/// Thin wrapper over `local_auth` for fingerprint / face unlock. Every call is
/// defensive: any platform exception (no hardware, not enrolled, web, plugin
/// missing) is treated as "not available / not authenticated" so the app can
/// always fall back to the PIN.
class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// True only when the device has biometric hardware AND the user has at
  /// least one fingerprint / face enrolled.
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Shows the OS biometric prompt. Returns true only on a successful scan.
  Future<bool> authenticate({
    String reason = 'Unlock Family Finance',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
