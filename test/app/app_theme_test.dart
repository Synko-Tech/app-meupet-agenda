import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_breakpoints.dart';
import 'package:meupet_agenda_app/app/app_brand_colors.dart';
import 'package:meupet_agenda_app/app/app_semantic_colors.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/app/app_typography.dart';

double _luminance(Color color) {
  double channel(double v) {
    return v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final l1 = _luminance(a);
  final l2 = _luminance(b);
  final hi = math.max(l1, l2);
  final lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('AppTheme', () {
    test('light() and dark() build with Material 3 and brand extension', () {
      final light = AppTheme.light();
      final dark = AppTheme.dark();

      expect(light.useMaterial3, isTrue);
      expect(dark.useMaterial3, isTrue);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.extension<AppBrandColors>(), isNotNull);
      expect(dark.extension<AppBrandColors>(), isNotNull);
    });

    test('titles use the display font, body uses the body font', () {
      final theme = AppTheme.light();
      expect(
        theme.textTheme.headlineMedium?.fontFamily,
        AppTypography.displayFont,
      );
      expect(theme.textTheme.titleMedium?.fontFamily, AppTypography.bodyFont);
      expect(theme.textTheme.bodyMedium?.fontFamily, AppTypography.bodyFont);
    });

    test('light theme: key text pairs meet WCAG AA (4.5:1)', () {
      final brand = AppBrandColors.light;
      expect(
        _contrast(AppSemanticColors.onPrimary, AppSemanticColors.primary),
        greaterThanOrEqualTo(4.5),
        reason: 'onPrimary on primary',
      );
      expect(
        _contrast(AppSemanticColors.text, AppSemanticColors.background),
        greaterThanOrEqualTo(4.5),
        reason: 'text on background',
      );
      expect(
        _contrast(brand.muted, AppSemanticColors.background),
        greaterThanOrEqualTo(4.5),
        reason: 'muted on background',
      );
      expect(
        _contrast(brand.muted, AppSemanticColors.surface),
        greaterThanOrEqualTo(4.5),
        reason: 'muted on surface',
      );
    });

    test('dark theme: key text pairs meet WCAG AA (4.5:1)', () {
      final brand = AppBrandColors.dark;
      expect(
        _contrast(
          AppSemanticColors.darkOnPrimary,
          AppSemanticColors.darkPrimary,
        ),
        greaterThanOrEqualTo(4.5),
        reason: 'dark onPrimary on primary',
      );
      expect(
        _contrast(AppSemanticColors.darkText, AppSemanticColors.darkSurface),
        greaterThanOrEqualTo(4.5),
        reason: 'dark text on surface',
      );
      expect(
        _contrast(brand.muted, AppSemanticColors.darkSurface),
        greaterThanOrEqualTo(4.5),
        reason: 'dark muted on surface',
      );
    });

    test('semantic palette feeds the generated light scheme', () {
      final scheme = AppTheme.light().colorScheme;
      expect(scheme.primary, AppSemanticColors.primary);
      expect(scheme.primaryContainer, AppSemanticColors.primaryContainer);
    });
  });

  group('AppBreakpoints', () {
    testWidgets('isTablet reflects width threshold', (tester) async {
      Future<void> expectLabel(double width, String expected) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) =>
                  Text(AppBreakpoints.isTablet(context) ? 'tablet' : 'phone'),
            ),
          ),
        );
        expect(find.text(expected), findsOneWidget);
      }

      await expectLabel(360, 'phone');
      await expectLabel(600, 'tablet');
      await expectLabel(840, 'tablet');
    });
  });
}
