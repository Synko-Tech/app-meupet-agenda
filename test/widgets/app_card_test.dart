import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/widgets/app_card.dart';

void main() {
  Future<void> pump(WidgetTester tester, AppCard card) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: Center(child: card)),
      ),
    );
  }

  group('AppCard', () {
    testWidgets('renders child', (tester) async {
      await pump(tester, const AppCard(child: Text('conteudo')));
      expect(find.text('conteudo'), findsOneWidget);
    });

    testWidgets('interactive variant fires onTap', (tester) async {
      var tapped = false;
      await pump(
        tester,
        AppCard(child: const Text('tocar'), onTap: () => tapped = true),
      );
      await tester.tap(find.text('tocar'));
      expect(tapped, isTrue);
    });

    testWidgets('trailing is rendered on the right', (tester) async {
      await pump(
        tester,
        const AppCard(
          trailing: Icon(Icons.chevron_right),
          child: Text('principal'),
        ),
      );
      expect(find.text('principal'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('highlighted variant uses tinted background', (tester) async {
      await pump(
        tester,
        const AppCard(
          variant: AppCardVariant.highlighted,
          child: Text('destaque'),
        ),
      );
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, isNot(Colors.white));
    });
  });
}
