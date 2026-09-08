import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/widgets/confirmation_sheet.dart';

void main() {
  testWidgets('confirm runs onConfirm and pops with true', (tester) async {
    var confirmed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  final result = await showConfirmationSheet(
                    context: context,
                    title: 'Confirmar agendamento',
                    items: const [
                      ConfirmationItem(label: 'Servico', value: 'Banho'),
                      ConfirmationItem(label: 'Horario', value: '09:00'),
                    ],
                    confirmLabel: 'Confirmar',
                    onConfirm: () async => confirmed = true,
                  );
                  // ignore: avoid_print
                  print('sheet result: $result');
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Confirmar agendamento'), findsOneWidget);
    expect(find.text('Banho'), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);

    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('cancel pops with false', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showConfirmationSheet(
                    context: context,
                    title: 'Confirmar',
                    items: const [],
                    confirmLabel: 'Sim',
                    onConfirm: () async {},
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('failure keeps the sheet open with an inline error', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  await showConfirmationSheet(
                    context: context,
                    title: 'Confirmar',
                    items: const [],
                    confirmLabel: 'Sim',
                    onConfirm: () async {
                      attempts++;
                      throw StateError('boom');
                    },
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sim'));
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(find.text('Confirmar'), findsOneWidget);
    expect(
      find.text('Nao foi possivel concluir a operacao. Tente novamente.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Sim'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });
}
