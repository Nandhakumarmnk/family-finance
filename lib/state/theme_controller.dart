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
  }

  Future<void> setSeed(Color value) async {
    if (seed.value == value.value) return;
    seed = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSeed, value.value);
  }
}
