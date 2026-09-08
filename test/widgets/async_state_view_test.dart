import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/widgets/async_state_view.dart';
import 'package:meupet_agenda_app/widgets/empty_state.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    AsyncSnapshot<List<String>> snapshot, {
    VoidCallback? onRetry,
    Widget Function(BuildContext)? emptyBuilder,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AsyncStateView<List<String>>(
            snapshot: snapshot,
            onRetry: onRetry,
            emptyTitle: 'Vazio',
            emptyMessage: 'Nada ainda.',
            emptyBuilder: emptyBuilder,
            errorTitle: 'Erro',
            errorMessage: 'Falhou.',
            builder: (context, data) =>
                Column(children: [for (final item in data) Text(item)]),
          ),
        ),
      ),
    );
  }

  group('AsyncStateView', () {
    testWidgets('waiting shows skeleton, not content', (tester) async {
      await pump(tester, const AsyncSnapshot<List<String>>.waiting());
      expect(find.byType(EmptyState), findsNothing);
      expect(find.text('dado'), findsNothing);
    });

    testWidgets('error shows message and retry action', (tester) async {
      var retried = false;
      await pump(
        tester,
        AsyncSnapshot<List<String>>.withError(
          ConnectionState.done,
          StateError('boom'),
        ),
        onRetry: () => retried = true,
      );
      expect(find.text('Erro'), findsOneWidget);
      expect(find.text('Falhou.'), findsOneWidget);
      await tester.tap(find.text('Tentar novamente'));
      expect(retried, isTrue);
    });

    testWidgets('empty list shows empty state with CTA', (tester) async {
      await pump(
        tester,
        const AsyncSnapshot<List<String>>.withData(ConnectionState.done, []),
      );
      expect(find.text('Vazio'), findsOneWidget);
      expect(find.text('Nada ainda.'), findsOneWidget);
    });

    testWidgets('emptyBuilder replaces the default empty state', (
      tester,
    ) async {
      await pump(
        tester,
        const AsyncSnapshot<List<String>>.withData(ConnectionState.done, []),
        emptyBuilder: (context) => const SizedBox.shrink(),
      );
      expect(find.byType(EmptyState), findsNothing);
      expect(find.text('Vazio'), findsNothing);
    });

    testWidgets('data renders the builder', (tester) async {
      await pump(
        tester,
        const AsyncSnapshot<List<String>>.withData(ConnectionState.done, [
          'dado 1',
          'dado 2',
        ]),
      );
      expect(find.text('dado 1'), findsOneWidget);
      expect(find.text('dado 2'), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
    });
  });
}
