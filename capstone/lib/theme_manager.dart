import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { light, dark, automatic }

class ThemeManager extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  AppThemeMode _appThemeMode = AppThemeMode.light;
  Timer? _timer;

  ThemeMode get themeMode => _themeMode;
  AppThemeMode get appThemeMode => _appThemeMode;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('themeMode') ?? 'automatic';
    _appThemeMode = AppThemeMode.values.firstWhere(
      (e) => e.name == saved,
      orElse: () => AppThemeMode.automatic,
    );
    _applyTheme();
    _startAutoCheck();
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    _appThemeMode = mode;
    await prefs.setString('themeMode', mode.name);
    _applyTheme();
    notifyListeners();
  }

  void _applyTheme() {
    if (_appThemeMode == AppThemeMode.automatic) {
      _themeMode = _isNightTime() ? ThemeMode.dark : ThemeMode.light;
    } else if (_appThemeMode == AppThemeMode.dark) {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.light;
    }
    notifyListeners();
  }

  bool _isNightTime() {
    final now = DateTime.now();
    return now.hour >= 18 || now.hour < 6;
  }

  void _startAutoCheck() {
    _timer?.cancel();
    if (_appThemeMode == AppThemeMode.automatic) {
      _timer = Timer.periodic(const Duration(minutes: 30), (_) {
        _applyTheme();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
