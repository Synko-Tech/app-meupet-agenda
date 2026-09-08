import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_brand_colors.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/widgets/app_button.dart';
import 'package:meupet_agenda_app/widgets/status_badge.dart';

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
  group('StatusBadge variant contrast', () {
    for (final (mode, brand) in [
      ('light', AppBrandColors.light),
      ('dark', AppBrandColors.dark),
    ]) {
      test('$mode: every variant pairs foreground/background >= 4.5:1', () {
        final pairs = <StatusBadgeVariant, (Color, Color)>{
          StatusBadgeVariant.success: (
            brand.successContainer,
            brand.onSuccessContainer,
          ),
          StatusBadgeVariant.warning: (
            brand.warningContainer,
            brand.onWarningContainer,
          ),
          StatusBadgeVariant.danger: (
            brand.dangerContainer,
            brand.onDangerContainer,
          ),
          StatusBadgeVariant.info: (brand.infoContainer, brand.onInfoContainer),
          StatusBadgeVariant.neutral: (brand.surfaceMuted, brand.muted),
        };

        for (final entry in pairs.entries) {
          expect(
            _contrast(entry.value.$1, entry.value.$2),
            greaterThanOrEqualTo(4.5),
            reason: '$mode ${entry.key} container/onContainer',
          );
        }
      });
    }

    testWidgets('renders a label for every variant', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Wrap(
              children: [
                for (final variant in StatusBadgeVariant.values)
                  StatusBadge(variant: variant, label: variant.name),
              ],
            ),
          ),
        ),
      );

      for (final variant in StatusBadgeVariant.values) {
        expect(find.text(variant.name), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('Touch targets meet the 48x48 guideline', () {
    Future<void> pumpButton(WidgetTester tester, Widget button) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: Center(child: button)),
        ),
      );
    }

    testWidgets('primary AppButton', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpButton(tester, AppButton(label: 'Criar', onPressed: () {}));
      expect(find.byType(FilledButton), findsOneWidget);
      expect(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('secondary AppButton', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpButton(
        tester,
        AppButton(label: 'Editar', isSecondary: true, onPressed: () {}),
      );
      expect(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('text AppButton', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpButton(
        tester,
        AppButton(
          label: 'Alterar',
          variant: AppButtonVariant.text,
          onPressed: () {},
        ),
      );
      expect(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  });
}
