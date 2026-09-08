import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/widgets/app_button.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required AppButton button}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: Center(child: button)),
      ),
    );
  }

  group('AppButton', () {
    testWidgets('renders label and triggers onPressed', (tester) async {
      var tapped = false;
      await pump(
        tester,
        button: AppButton(
          label: 'Acessar',
          icon: Icons.login,
          onPressed: () => tapped = true,
        ),
      );
      expect(find.text('Acessar'), findsOneWidget);
      await tester.tap(find.text('Acessar'));
      expect(tapped, isTrue);
    });

    testWidgets('disabled when onPressed is null', (tester) async {
      await pump(tester, button: AppButton(label: 'Salvar', onPressed: null));
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('loading disables tap and shows a spinner', (tester) async {
      var tapped = false;
      await pump(
        tester,
        button: AppButton(
          label: 'Enviar',
          isLoading: true,
          onPressed: () => tapped = true,
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Enviar'), findsOneWidget);
      await tester.tap(find.text('Enviar'));
      expect(tapped, isFalse);
    });

    testWidgets('isSecondary legacy flag maps to secondary variant', (
      tester,
    ) async {
      await pump(
        tester,
        button: AppButton(label: 'Voltar', isSecondary: true, onPressed: () {}),
      );
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.style?.backgroundColor, isNotNull);
    });

    testWidgets('destructive variant uses error color', (tester) async {
      await pump(
        tester,
        button: AppButton(
          label: 'Excluir',
          variant: AppButtonVariant.destructive,
          onPressed: () {},
        ),
      );
      final scheme = Theme.of(
        tester.element(find.byType(AppButton)),
      ).colorScheme;
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.style?.backgroundColor?.resolve({}), scheme.error);
    });

    testWidgets('meets Android tap target guideline (48x48)', (tester) async {
      await pump(
        tester,
        button: AppButton(label: 'Acao', onPressed: () {}),
      );
      final handle = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  });
}
