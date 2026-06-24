import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A local app-lock PIN so the user can re-enter the app quickly without going
/// through Google sign-in each time. This is a convenience lock, not strong
/// security — the PIN is stored only as a lightweight non-reversible hash on
/// the device.
///
/// Wrong entries are rate-limited: after [maxAttempts] consecutive wrong PINs
/// the pad locks for a cooldown that grows with each lock-out, so the PIN can't
/// be guessed by hammering. A user who forgets the PIN can always reset and
/// start fresh (see [clearAll]).
class PinController extends ChangeNotifier {
  static const _kHash = 'pin_hash';
  static const _kFails = 'pin_fails';
  static const _kLockUntil = 'pin_lock_until';
  static const _kLockouts = 'pin_lockouts';
  static const _kBiometric = 'pin_biometric';

  /// Wrong attempts allowed before the pad locks for a cooldown.
  static const int maxAttempts = 5;

  String? _hash;
  bool _loaded = false;
  bool _locked = true;

  int _failed = 0; // consecutive wrong attempts in the current round
  int _lockouts = 0; // how many times we've locked out (escalates cooldown)
  DateTime? _lockedUntil;
  bool _biometric = false;

  bool get loaded => _loaded;
  bool get isSet => _hash != null;

  /// Whether the user opted into fingerprint / face unlock (only meaningful
  /// when a PIN is also set, since the PIN is the fallback).
  bool get biometricEnabled => isSet && _biometric;

  /// True when a PIN is set and the app is currently locked.
  bool get isLocked => isSet && _locked;

  /// Wrong attempts remaining before the next cooldown lock-out.
  int get attemptsLeft => (maxAttempts - _failed).clamp(0, maxAttempts);
  int get failedAttempts => _failed;

  /// True while the pad is in a cooldown after too many wrong attempts.
  bool get isLockedOut =>
      _lockedUntil != null && _lockedUntil!.isAfter(DateTime.now());

  /// Time left in the current cooldown (zero when not locked out).
  Duration get lockRemaining {
    final until = _lockedUntil;
    if (until == null) return Duration.zero;
    final d = until.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  PinController() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _hash = prefs.getString(_kHash);
    _biometric = prefs.getBool(_kBiometric) ?? false;
    _failed = prefs.getInt(_kFails) ?? 0;
    _lockouts = prefs.getInt(_kLockouts) ?? 0;
    final until = prefs.getInt(_kLockUntil);
    _lockedUntil =
        until == null ? null : DateTime.fromMillisecondsSinceEpoch(until);
    _locked = _hash != null; // start locked if a PIN exists
    _loaded = true;
    notifyListeners();
  }

  Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    _hash = _hashPin(pin);
    await prefs.setString(_kHash, _hash!);
    _locked = false;
    await _resetAttempts(prefs);
    notifyListeners();
  }

  /// Opt in/out of fingerprint / face unlock.
  Future<void> setBiometric(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    _biometric = on;
    await prefs.setBool(_kBiometric, on);
    notifyListeners();
  }

  /// Unlock after a successful OS biometric scan (verified by the caller via
  /// [BiometricService]). Only meaningful when a PIN is set.
  void unlockViaBiometric() {
    if (!isSet) return;
    _locked = false;
    _unlockedReset();
    notifyListeners();
  }

  /// Turn the PIN lock off (from settings).
  Future<void> removePin() => clearAll();

  /// Wipe the PIN and all attempt/lock-out state — used by "reset & start
  /// fresh" when a user forgets their PIN. The caller typically signs out
  /// afterwards so the app returns to the login screen.
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHash);
    await prefs.remove(_kFails);
    await prefs.remove(_kLockUntil);
    await prefs.remove(_kLockouts);
    await prefs.remove(_kBiometric);
    _hash = null;
    _failed = 0;
    _lockouts = 0;
    _lockedUntil = null;
    _biometric = false;
    _locked = false;
    notifyListeners();
  }

  /// Returns true and unlocks if [pin] matches. Wrong entries are counted and,
  /// past [maxAttempts], trigger an escalating cooldown. Entries are ignored
  /// (return false) while a cooldown is active.
  bool unlock(String pin) {
    if (isLockedOut) return false;

    if (_hash != null && _hashPin(pin) == _hash) {
      _locked = false;
      _unlockedReset();
      notifyListeners();
      return true;
    }

    _failed += 1;
    if (_failed >= maxAttempts) {
      _lockouts += 1;
      // 30s, 60s, 90s … capped at 10 minutes.
      final seconds = (30 * _lockouts).clamp(30, 600);
      _lockedUntil = DateTime.now().add(Duration(seconds: seconds));
      _failed = 0; // fresh attempts once the cooldown ends
    }
    _persistAttempts();
    notifyListeners();
    return false;
  }

  /// Re-lock (e.g. on sign-out).
  void lock() {
    if (isSet) {
      _locked = true;
      notifyListeners();
    }
  }

  void _unlockedReset() {
    _failed = 0;
    _lockouts = 0;
    _lockedUntil = null;
    _persistAttempts();
  }

  Future<void> _resetAttempts(SharedPreferences prefs) async {
    _failed = 0;
    _lockouts = 0;
    _lockedUntil = null;
    await prefs.remove(_kFails);
    await prefs.remove(_kLockUntil);
    await prefs.remove(_kLockouts);
  }

  Future<void> _persistAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kFails, _failed);
    await prefs.setInt(_kLockouts, _lockouts);
    final until = _lockedUntil;
    if (until == null) {
      await prefs.remove(_kLockUntil);
    } else {
      await prefs.setInt(_kLockUntil, until.millisecondsSinceEpoch);
    }
  }

  // FNV-1a style hash — enough to avoid storing the PIN in clear text. Not a
  // substitute for real cryptography, which a local 4-digit PIN can't provide.
  String _hashPin(String pin) {
    var h = 0x811c9dc5;
    for (final c in '$pin::family-finance'.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return h.toRadixString(16);
  }
}
