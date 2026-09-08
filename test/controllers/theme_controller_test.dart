import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/controllers/theme_controller.dart';

void main() {
  group('ThemeController', () {
    test('defaults to light mode', () {
      final controller = ThemeController();
      expect(controller.mode, ThemeMode.light);
      expect(controller.isDark, false);
    });

    test('toggle switches between light and dark', () {
      final controller = ThemeController();
      controller.toggle();
      expect(controller.mode, ThemeMode.dark);
      expect(controller.isDark, true);
      controller.toggle();
      expect(controller.mode, ThemeMode.light);
      expect(controller.isDark, false);
    });

    test('setMode changes the mode', () {
      final controller = ThemeController();
      controller.setMode(ThemeMode.dark);
      expect(controller.mode, ThemeMode.dark);
      controller.setMode(ThemeMode.light);
      expect(controller.mode, ThemeMode.light);
    });

    test('notifies listeners on change', () {
      final controller = ThemeController();
      var notified = false;
      controller.addListener(() => notified = true);
      controller.toggle();
      expect(notified, true);
    });

    test('does not notify when setting same mode', () {
      final controller = ThemeController();
      var notified = false;
      controller.addListener(() => notified = true);
      controller.setMode(ThemeMode.light);
      expect(notified, false);
    });
  });
}
