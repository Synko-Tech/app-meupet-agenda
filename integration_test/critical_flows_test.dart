import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meupet_agenda_app/app/app.dart';
import 'package:meupet_agenda_app/app/firebase_emulators.dart';
import 'package:meupet_agenda_app/firebase_options.dart';

/// Fluxo critico E2E contra a suíte de emuladores Firebase (Auth, Firestore,
/// Storage, Functions). Requer dados semeados pelo `functions/seed-emulator.js`
/// e um dispositivo/emulador Android conectado:
///
///   firebase emulators:exec --project meupet-agenda-app \
///     --only auth,firestore,storage,functions \
///     "node functions/seed-emulator.js && \
///      flutter test integration_test/critical_flows_test.dart \
///        -d emulator-5554 \
///        --dart-define=USE_FIREBASE_EMULATORS=true \
///        --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2"
///
/// O projeto dos emuladores/seed DEVE ser o mesmo do app (meupet-agenda-app):
/// o namespace do Auth Emulator e por projeto e os usuarios semeados so sao
/// encontrados quando o app e o seed usam o mesmo id.
/// O host padrao (10.0.2.2) e o loopback do emulador Android para a maquina
/// host; use localhost em desktop (configurado via `firebase_emulators.dart`).

/// Project id esperado na inicializacao do app (android/app/google-services.json).
const _flutterProjectId = String.fromEnvironment(
  'FIREBASE_PROJECT_ID',
  defaultValue: 'meupet-agenda-app',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!const bool.fromEnvironment(
      'USE_FIREBASE_EMULATORS',
      defaultValue: false,
    )) {
      throw StateError(
        'O teste E2E exige --dart-define=USE_FIREBASE_EMULATORS=true',
      );
    }

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (Firebase.app().options.projectId != _flutterProjectId) {
      throw StateError(
        'Projeto inesperado: ${Firebase.app().options.projectId} '
        '(esperado $_flutterProjectId). O E2E so roda contra emuladores.',
      );
    }

    // Mesma configuracao do app real (main.dart): garante que o E2E testa
    // exatamente o que o usuario roda, nunca um caminho separado.
    configureFirebaseEmulators();
    // Sessao limpa: garante que o gate abra no login.
    await FirebaseAuth.instance.signOut();
  });

  Future<void> submitLogin(
    WidgetTester tester,
    String email,
    String password,
  ) async {
    await tester.enterText(find.byKey(const Key('login_email_field')), email);
    await tester.enterText(
      find.byKey(const Key('login_password_field')),
      password,
    );
    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pumpAndSettle();
  }

  Future<void> selectFirstAvailableSlot(WidgetTester tester) async {
    // Percorre os 5 chips de dia e escolhe o primeiro dia com horario
    // habilitado (evita dia fechado/horas passadas).
    for (var day = 0; day < 5; day++) {
      await tester.tap(find.byKey(ValueKey('appointment_day_chip_$day')));
      await tester.pumpAndSettle();

      final enabledSlot = find.byWidgetPredicate(
        (widget) => widget is OutlinedButton && widget.onPressed != null,
      );
      if (enabledSlot.evaluate().isNotEmpty) {
        await tester.ensureVisible(enabledSlot.first);
        await tester.pumpAndSettle();
        await tester.tap(enabledSlot.first);
        await tester.pumpAndSettle();
        return;
      }
    }
    fail('Nenhum horario habilitado nos 5 dias futuros');
  }

  Future<void> continueStep(WidgetTester tester) async {
    final button = find.byKey(const Key('appointment_continue_button'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  testWidgets('fluxo critico: login, agendamento, checkout e logout', (
    tester,
  ) async {
    await tester.pumpWidget(const MeuPetAgendaApp());
    await tester.pumpAndSettle();

    // 1. Inicio deslogado: tela de login.
    expect(find.text('Acessar'), findsOneWidget);

    // 2. Senha incorreta -> mensagem amigavel.
    await submitLogin(tester, 'alice@exemplo.com', 'senha-errada');
    expect(find.text('E-mail ou senha invalidos.'), findsOneWidget);
    // Deixa o snackbar de erro sair da fila antes do proximo login.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 3. Login correto (semeador) -> selecao de loja -> shell do cliente.
    await submitLogin(tester, 'alice@exemplo.com', 'senha-forte-123');
    await tester.pumpAndSettle();
    if (find.text('Crie sua loja').evaluate().isNotEmpty) {
      await tester.enterText(find.byType(TextField).first, 'Pet Shop Teste');
      await tester.pumpAndSettle();
      final createButton = find.widgetWithText(FilledButton, 'Criar loja');
      await tester.ensureVisible(createButton);
      await tester.pumpAndSettle();
      await tester.tap(createButton);
      await tester.pumpAndSettle();
    } else if (find.text('Suas lojas').evaluate().isNotEmpty) {
      await tester.tap(find.text('Pet Shop Teste'));
      await tester.pumpAndSettle();
    }
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Inicio'), findsWidgets);
    expect(find.text('Sair'), findsNothing);

    // 4. Agendar (wizard de 4 etapas): servico, profissional, data e horario.
    await tester.tap(find.text('Agendar'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('appointment_service_card_svc60')),
    );
    await tester.pumpAndSettle();
    await continueStep(tester);

    await tester.tap(
      find.byKey(const ValueKey('appointment_professional_card_prof1')),
    );
    await tester.pumpAndSettle();
    await continueStep(tester);

    await selectFirstAvailableSlot(tester);
    await continueStep(tester);

    await tester.ensureVisible(
      find.byKey(const Key('appointment_confirm_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appointment_confirm_button')));
    await tester.pumpAndSettle();
    expect(find.text('Agendamento confirmado.'), findsOneWidget);

    // 5. Compra de pacote: a loja do seed nao tem conexao Mercado Pago, o
    // checkout falha com mensagem amigavel (nunca fica preso em PENDENTE).
    await tester.tap(find.text('Pacotes'));
    await tester.pumpAndSettle();
    // Deixa o snackbar do agendamento sair da fila antes do proximo.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('packages_buy_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('packages_buy_button')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Esta loja ainda nao conectou a conta Mercado Pago para receber vendas.',
      ),
      findsOneWidget,
    );

    // 6. Logout pela aba Conta -> volta ao login.
    await tester.tap(find.text('Conta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account_logout_button')));
    await tester.pumpAndSettle();
    expect(find.text('Acessar'), findsOneWidget);
  });
}
