import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/screens/auth/login_screen.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockAuthController extends Mock implements AuthController {}

void main() {
  late MockAuthController auth;

  setUp(() {
    auth = MockAuthController();
    when(() => auth.isBusy).thenReturn(false);
  });

  Future<void> pumpLogin(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthController>.value(
        value: auth,
        child: MaterialApp(theme: AppTheme.light(), home: const LoginScreen()),
      ),
    );
  }

  group('LoginScreen', () {
    testWidgets('does not prefill a demo email', (tester) async {
      await pumpLogin(tester);
      expect(find.text('cliente@email.com'), findsNothing);
    });

    testWidgets('renders the brand and the roles card', (tester) async {
      await pumpLogin(tester);
      expect(find.text('MeuPet Agenda'), findsOneWidget);
      expect(find.text('Perfis'), findsOneWidget);
    });

    testWidgets('offers both client and business registration buttons', (
      tester,
    ) async {
      await pumpLogin(tester);
      expect(find.text('Criar conta cliente'), findsOneWidget);
      expect(find.text('Criar conta empresa'), findsOneWidget);
    });

    testWidgets('rejects an invalid email without calling signIn', (
      tester,
    ) async {
      await pumpLogin(tester);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'email-sem-arroba',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '123456');
      await tester.tap(find.text('Acessar'));
      await tester.pump();

      expect(find.text('Informe um e-mail valido'), findsOneWidget);
      verifyNever(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
    });

    testWidgets('rejects an empty password without calling signIn', (
      tester,
    ) async {
      await pumpLogin(tester);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'cliente@exemplo.com',
      );
      await tester.tap(find.text('Acessar'));
      await tester.pump();

      expect(find.text('Campo obrigatorio'), findsOneWidget);
      verifyNever(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
    });

    testWidgets('submits a valid form to signIn', (tester) async {
      when(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async {});

      await pumpLogin(tester);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'cliente@exemplo.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '123456');
      await tester.tap(find.text('Acessar'));
      await tester.pump();

      verify(
        () => auth.signIn(email: 'cliente@exemplo.com', password: '123456'),
      ).called(1);
    });

    testWidgets('shows the friendly message on invalid-credential', (
      tester,
    ) async {
      when(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(FirebaseAuthException(code: 'invalid-credential'));
      when(() => auth.errorMessage).thenReturn('E-mail ou senha invalidos.');

      await pumpLogin(tester);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'cliente@exemplo.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'senha-errada');
      await tester.tap(find.text('Acessar'));
      await tester.pump();

      expect(find.text('E-mail ou senha invalidos.'), findsOneWidget);
    });

    testWidgets('shows the friendly message on invalid-login-credentials', (
      tester,
    ) async {
      when(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(FirebaseAuthException(code: 'invalid-login-credentials'));
      when(() => auth.errorMessage).thenReturn('E-mail ou senha invalidos.');

      await pumpLogin(tester);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'cliente@exemplo.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'senha-errada');
      await tester.tap(find.text('Acessar'));
      await tester.pump();

      expect(find.text('E-mail ou senha invalidos.'), findsOneWidget);
    });
  });
}
