import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

/// Holds the user's appearance choices — light/dark/system mode and the colour
/// theme (seed) — and persists them across launches via SharedPreferences.
class ThemeController extends ChangeNotifier {
  static const _kMode = 'theme_mode';
  static const _kSeed = 'theme_seed';

  ThemeMode mode = ThemeMode.system;
  Color seed = AppTheme.seed;

  /// Optional hook, set by the app root, to also persist appearance changes to
  /// the signed-in user's cloud profile so they follow the user across devices.
  /// Called after the local save; never called by [applyRemote] (which would
  /// echo a just-loaded cloud value straight back up).
  Future<void> Function(ThemeMode mode, Color seed)? cloudPersist;

  ThemeController() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeName = prefs.getString(_kMode);
    if (modeName != null) {
      mode = ThemeMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => ThemeMode.system,
      );
    }
    final seedValue = prefs.getInt(_kSeed);
    if (seedValue != null) seed = Color(seedValue);
    notifyListeners();
  }

  Future<void> setMode(ThemeMode value) async {
    if (mode == value) return;
    mode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMode, value.name);
    await cloudPersist?.call(mode, seed);
  }

  Future<void> setSeed(Color value) async {
    if (seed.value == value.value) return;
    seed = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSeed, value.value);
    await cloudPersist?.call(mode, seed);
  }

  /// Apply appearance values loaded from the cloud profile, without echoing
  /// them back up (so hydration on sign-in doesn't trigger a redundant save).
  /// Ignores empty/zero values, which mean "not set in the cloud".
  Future<void> applyRemote({String? modeName, int? seedValue}) async {
    var changed = false;
    if (modeName != null && modeName.isNotEmpty) {
      final m = ThemeMode.values.firstWhere(
        (x) => x.name == modeName,
        orElse: () => mode,
      );
      if (m != mode) {
        mode = m;
        changed = true;
      }
    }
    if (seedValue != null && seedValue != 0 && seedValue != seed.value) {
      seed = Color(seedValue);
      changed = true;
    }
    if (!changed) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMode, mode.name);
    await prefs.setInt(_kSeed, seed.value);
  }
}
