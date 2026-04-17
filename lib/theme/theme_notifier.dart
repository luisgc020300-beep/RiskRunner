// lib/theme/theme_notifier.dart
//
// Gestiona el modo claro/oscuro de toda la app.
// Uso: ThemeNotifier.instance para acceder desde cualquier sitio.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeNotifier extends ChangeNotifier {
  static final ThemeNotifier instance = ThemeNotifier._();
  ThemeNotifier._();

  static const _key = 'app_theme_mode';

  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == 'light') {
      _mode = ThemeMode.light;
    } else {
      _mode = ThemeMode.dark;
    }
    notifyListeners();
  }

  Future<void> setDark()  => _set(ThemeMode.dark);
  Future<void> setLight() => _set(ThemeMode.light);
  Future<void> toggle()   => isDark ? setLight() : setDark();

  Future<void> _set(ThemeMode m) async {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, m == ThemeMode.light ? 'light' : 'dark');
  }
}
