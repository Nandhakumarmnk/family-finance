import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A local app-lock PIN so the user can re-enter the app quickly without going
/// through Google sign-in each time. This is a convenience lock, not strong
/// security — the PIN is stored only as a lightweight non-reversible hash on
/// the device.
class PinController extends ChangeNotifier {
  static const _kHash = 'pin_hash';

  String? _hash;
  bool _loaded = false;
  bool _locked = true;

  bool get loaded => _loaded;
  bool get isSet => _hash != null;

  /// True when a PIN is set and the app is currently locked.
  bool get isLocked => isSet && _locked;

  PinController() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _hash = prefs.getString(_kHash);
    _locked = _hash != null; // start locked if a PIN exists
    _loaded = true;
    notifyListeners();
  }

  Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    _hash = _hashPin(pin);
    await prefs.setString(_kHash, _hash!);
    _locked = false;
    notifyListeners();
  }

  Future<void> removePin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHash);
    _hash = null;
    _locked = false;
    notifyListeners();
  }

  /// Returns true and unlocks if [pin] matches.
  bool unlock(String pin) {
    if (_hash != null && _hashPin(pin) == _hash) {
      _locked = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Re-lock (e.g. on sign-out).
  void lock() {
    if (isSet) {
      _locked = true;
      notifyListeners();
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
