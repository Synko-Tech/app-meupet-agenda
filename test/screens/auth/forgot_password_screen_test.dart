import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/screens/auth/forgot_password_screen.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockAuthController extends Mock implements AuthController {}

void main() {
  late MockAuthController auth;

  setUp(() {
    auth = MockAuthController();
    when(() => auth.isBusy).thenReturn(false);
  });

  Future<void> pumpForgot(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthController>.value(
        value: auth,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ForgotPasswordScreen(),
        ),
      ),
    );
  }

  group('ForgotPasswordScreen', () {
    testWidgets('rejects an invalid email without sending a reset link', (
      tester,
    ) async {
      await pumpForgot(tester);
      await tester.enterText(find.byType(TextFormField), 'email-sem-arroba');
      await tester.tap(find.text('Enviar link'));
      await tester.pump();

      expect(find.text('Informe um e-mail valido'), findsOneWidget);
      verifyNever(() => auth.sendPasswordReset(any()));
    });

    testWidgets('sends a reset link for a valid email', (tester) async {
      when(() => auth.sendPasswordReset(any())).thenAnswer((_) async {});

      await pumpForgot(tester);
      await tester.enterText(find.byType(TextFormField), 'cliente@exemplo.com');
      await tester.tap(find.text('Enviar link'));
      await tester.pumpAndSettle();

      verify(() => auth.sendPasswordReset('cliente@exemplo.com')).called(1);
    });

    testWidgets('shows the error message when sending fails', (tester) async {
      when(
        () => auth.sendPasswordReset(any()),
      ).thenThrow(StateError('Falha ao enviar e-mail.'));

      await pumpForgot(tester);
      await tester.enterText(find.byType(TextFormField), 'cliente@exemplo.com');
      await tester.tap(find.text('Enviar link'));
      await tester.pumpAndSettle();

      expect(find.text('Nao foi possivel enviar o link.'), findsOneWidget);
    });
  });
}
