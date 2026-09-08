import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meupet_agenda_app/app/app.dart';
import 'package:meupet_agenda_app/app/firebase_emulators.dart';
import 'package:meupet_agenda_app/firebase_options.dart';

/// Onboarding E2E: cadastro de cliente (CPF + endereco) cai direto no shell
/// (cliente nao e forcado a criar loja) e o cadastro de conta empresa cria a
/// loja via callable `registerBusiness`, validando o membership `owner` e os
/// dados cadastrais no Firestore. Exige a suite de emuladores Firebase
/// rodando:
///
///   firebase emulators:exec --project meupet-agenda-app \
///     --only auth,firestore,storage,functions \
///     "node functions/seed-emulator.js && \
///      flutter test integration_test/onboarding_flow_test.dart \
///        -d emulator-5554 \
///        --dart-define=USE_FIREBASE_EMULATORS=true \
///        --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2"
///
/// Deterministico: usa um e-mail unico por execucao, sem depender de dados
/// semeados alem do namespace do Auth Emulator.
///
/// ViaCEP e uma chamada de rede real a partir do emulador Android: o autofill
/// e best-effort. Os campos de endereco sao preenchidos manualmente de
/// qualquer forma, entao o teste passa com ou sem resposta do ViaCEP. As
/// esperas usam `pump` com polling (nunca `pumpAndSettle` enquanto o spinner
/// de CEP/loading pode estar animando).

const _flutterProjectId = String.fromEnvironment(
  'FIREBASE_PROJECT_ID',
  defaultValue: 'meupet-agenda-app',
);

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsWidgets);
}

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

    configureFirebaseEmulators();
    await FirebaseAuth.instance.signOut();
  });

  testWidgets('onboarding: cadastro, cria loja e vira owner', (tester) async {
    final email = 'onboard${DateTime.now().millisecondsSinceEpoch}@exemplo.com';
    const password = 'senha-forte-123';

    await tester.pumpWidget(const MeuPetAgendaApp());
    await tester.pumpAndSettle();

    // 1. Inicio deslogado: tela de login.
    expect(find.text('Acessar'), findsOneWidget);

    // 2. Vai para o cadastro e cria uma conta nova.
    await tester.tap(find.text('Criar conta cliente'));
    await tester.pumpAndSettle();
    expect(find.text('Cadastrar'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('register_name_field')),
      'Onboard User',
    );
    await tester.enterText(
      find.byKey(const Key('register_email_field')),
      email,
    );
    await tester.enterText(
      find.byKey(const Key('register_phone_field')),
      '11988887777',
    );
    await tester.enterText(
      find.byKey(const Key('register_cpf_field')),
      '52998224725',
    );
    await tester.enterText(
      find.byKey(const Key('register_cep_field')),
      '01310100',
    );
    await tester.enterText(
      find.byKey(const Key('register_street_field')),
      'Avenida Paulista',
    );
    await tester.enterText(
      find.byKey(const Key('register_number_field')),
      '1000',
    );
    await tester.enterText(
      find.byKey(const Key('register_complement_field')),
      'Sala 2',
    );
    await tester.enterText(
      find.byKey(const Key('register_neighborhood_field')),
      'Bela Vista',
    );
    await tester.enterText(
      find.byKey(const Key('register_city_field')),
      'Sao Paulo',
    );
    await tester.enterText(find.byKey(const Key('register_uf_field')), 'SP');
    await tester.enterText(
      find.byKey(const Key('register_password_field')),
      password,
    );
    await tester.enterText(
      find.byKey(const Key('register_confirm_field')),
      password,
    );

    // Deixa o ViaCEP (best-effort) terminar antes de submeter: campos de
    // endereco ja estao preenchidos manualmente, o autofill so pode
    // sobrescreve-los com valores identicos (01310100 => Avenida Paulista,
    // Bela Vista, Sao Paulo, SP).
    await tester.pump(const Duration(seconds: 2));

    await tester.ensureVisible(find.byKey(const Key('register_submit_button')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('register_submit_button')));
    await _pumpUntilFound(tester, find.text('Encontrar pet shop'));

    // 3. Cliente sem membership vai direto ao shell (nao e forcado a criar
    //    loja) e a home oferece a descoberta de pet shops.
    expect(find.text('Encontrar pet shop'), findsOneWidget);
    expect(find.text('Crie sua loja'), findsNothing);

    // 4. O cliente nao tem nenhuma loja associada.
    final clientUid = FirebaseAuth.instance.currentUser!.uid;
    final clientMemberships = await FirebaseFirestore.instance
        .collection('users')
        .doc(clientUid)
        .collection('businessMemberships')
        .get();
    expect(clientMemberships.docs, hasLength(0));

    // 5. Sai da conta do cliente para testar o cadastro de empresa.
    await tester.tap(find.text('Conta'));
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('account_logout_button')),
    );
    await tester.tap(find.byKey(const Key('account_logout_button')));
    await _pumpUntilFound(tester, find.text('Acessar'));

    // 6. Cadastro de conta empresa: dados do responsavel + da loja.
    final businessEmail =
        'loja${DateTime.now().millisecondsSinceEpoch}@exemplo.com';
    await tester.tap(find.text('Criar conta empresa'));
    await tester.pumpAndSettle();
    expect(find.text('Cadastrar empresa'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('register_business_name_field')),
      'Dona Loja',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_email_field')),
      businessEmail,
    );
    await tester.enterText(
      find.byKey(const Key('register_business_phone_field')),
      '11988887777',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_cpf_field')),
      '52998224725',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_password_field')),
      password,
    );
    await tester.enterText(
      find.byKey(const Key('register_business_confirm_field')),
      password,
    );
    await tester.enterText(
      find.byKey(const Key('register_business_cnpj_field')),
      '11222333000181',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_business_name_field')),
      'Loja Empresa E2E',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_business_phone_field')),
      '1140028922',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_cep_field')),
      '01310100',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_street_field')),
      'Avenida Paulista',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_number_field')),
      '1000',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_neighborhood_field')),
      'Bela Vista',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_city_field')),
      'Sao Paulo',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_uf_field')),
      'SP',
    );

    await tester.pump(const Duration(seconds: 2));
    await tester.ensureVisible(
      find.byKey(const Key('register_business_submit_button')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('register_business_submit_button')));
    await _pumpUntilFound(tester, find.text('Inicio'));

    // 7. O membership `owner` existe na projecao do dono.
    final ownerUid = FirebaseAuth.instance.currentUser!.uid;
    final memberships = await FirebaseFirestore.instance
        .collection('users')
        .doc(ownerUid)
        .collection('businessMemberships')
        .get();
    expect(memberships.docs, hasLength(1));
    expect(memberships.docs.single.data()['role'], 'owner');
    expect(
      memberships.docs.single.data()['businessName'],
      'Loja Empresa E2E',
    );

    // 8. A loja esta cadastrada no Firestore com os dados da empresa.
    final businessId = memberships.docs.single.data()['businessId'];
    final business = await FirebaseFirestore.instance
        .collection('businesses')
        .doc(businessId)
        .get();
    expect(business.data()?['cnpj'], '11222333000181');
    expect(business.data()?['status'], 'ATIVO');
    expect(business.data()?['endereco']['city'], 'Sao Paulo');
  });
}
