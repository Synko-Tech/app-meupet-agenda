import 'package:flutter/material.dart';

class ThemeController extends ChangeNotifier {
  ThemeController({ThemeMode initial = ThemeMode.light})
      : _mode = initial;

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  void toggle() {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  void setMode(ThemeMode mode) {
    if (_mode != mode) {
      _mode = mode;
      notifyListeners();
    }
  }
}
