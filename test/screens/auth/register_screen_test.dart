import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/models/postal_address.dart';
import 'package:meupet_agenda_app/screens/auth/register_screen.dart';
import 'package:meupet_agenda_app/services/cep_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockAuthController extends Mock implements AuthController {}

class MockCepService extends Mock implements CepService {}

const _allFieldKeys = <String>[
  'register_name_field',
  'register_email_field',
  'register_phone_field',
  'register_cpf_field',
  'register_cep_field',
  'register_street_field',
  'register_number_field',
  'register_complement_field',
  'register_neighborhood_field',
  'register_city_field',
  'register_uf_field',
  'register_password_field',
  'register_confirm_field',
];

void main() {
  late MockAuthController auth;
  late MockCepService cepService;

  setUpAll(() {
    registerFallbackValue(
      const PostalAddress(
        postalCode: '01310100',
        street: 'Avenida Paulista',
        number: '1000',
        neighborhood: 'Bela Vista',
        city: 'Sao Paulo',
        state: 'SP',
      ),
    );
  });

  setUp(() {
    auth = MockAuthController();
    cepService = MockCepService();
    when(() => auth.isBusy).thenReturn(false);
    when(() => cepService.lookup(any())).thenAnswer(
      (_) async => const PostalAddressLookup(
        postalCode: '01310100',
        street: 'Avenida Paulista',
        neighborhood: 'Bela Vista',
        city: 'Sao Paulo',
        state: 'SP',
      ),
    );
  });

  Future<void> pumpRegister(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          Provider<CepService>.value(value: cepService),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const RegisterScreen(),
        ),
      ),
    );
  }

  Future<void> fillValid(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('register_name_field')),
      'Cliente',
    );
    await tester.enterText(
      find.byKey(const Key('register_email_field')),
      'cliente@exemplo.com',
    );
    await tester.enterText(
      find.byKey(const Key('register_phone_field')),
      '11999999999',
    );
    await tester.enterText(
      find.byKey(const Key('register_cpf_field')),
      '529.982.247-25',
    );
    await tester.enterText(
      find.byKey(const Key('register_cep_field')),
      '01310-100',
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
      'Sala 1',
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
      'Senha@123',
    );
    await tester.enterText(
      find.byKey(const Key('register_confirm_field')),
      'Senha@123',
    );
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('register_submit_button')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('register_submit_button')));
    await tester.pump();
  }

  void expectNoRegistration() {
    verifyNever(
      () => auth.registerClient(
        name: any(named: 'name'),
        email: any(named: 'email'),
        password: any(named: 'password'),
        phone: any(named: 'phone'),
        cpf: any(named: 'cpf'),
        address: any(named: 'address'),
      ),
    );
  }

  group('RegisterScreen', () {
    testWidgets('shows all fourteen registration fields', (tester) async {
      await pumpRegister(tester);

      for (final key in _allFieldKeys) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(find.byKey(const Key('register_submit_button')), findsOneWidget);
    });

    testWidgets('rejects an invalid CPF without registering', (tester) async {
      await pumpRegister(tester);
      await fillValid(tester);
      await tester.enterText(
        find.byKey(const Key('register_cpf_field')),
        '123.456.789-00',
      );
      await tapSubmit(tester);

      expect(find.text('CPF invalido'), findsOneWidget);
      expectNoRegistration();
    });

    testWidgets('rejects an invalid CEP without registering', (tester) async {
      await pumpRegister(tester);
      await fillValid(tester);
      await tester.enterText(
        find.byKey(const Key('register_cep_field')),
        '12345',
      );
      await tapSubmit(tester);

      expect(find.text('CEP invalido'), findsOneWidget);
      expectNoRegistration();
    });

    testWidgets('requires the address fields', (tester) async {
      await pumpRegister(tester);
      await fillValid(tester);
      await tester.enterText(
        find.byKey(const Key('register_street_field')),
        '',
      );
      await tapSubmit(tester);

      expect(find.text('Campo obrigatorio'), findsOneWidget);
      expectNoRegistration();
    });

    testWidgets('prefills the address from ViaCEP on eight digits', (
      tester,
    ) async {
      await pumpRegister(tester);

      await tester.enterText(
        find.byKey(const Key('register_cep_field')),
        '01310100',
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Avenida Paulista'), findsOneWidget);
      expect(find.text('Bela Vista'), findsOneWidget);
      expect(find.text('Sao Paulo'), findsOneWidget);
      expect(find.text('SP'), findsOneWidget);
      verify(() => cepService.lookup('01310100')).called(1);
    });

    testWidgets('allows manual correction after the ViaCEP autofill', (
      tester,
    ) async {
      await pumpRegister(tester);

      await tester.enterText(
        find.byKey(const Key('register_cep_field')),
        '01310100',
      );
      await tester.pump();
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('register_street_field')),
        'Rua Corrigida',
      );

      expect(find.text('Rua Corrigida'), findsOneWidget);
    });

    testWidgets('shows a friendly message when the CEP is not found', (
      tester,
    ) async {
      when(
        () => cepService.lookup(any()),
      ).thenThrow(const CepException.notFound());

      await pumpRegister(tester);
      await tester.enterText(
        find.byKey(const Key('register_cep_field')),
        '99999999',
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('CEP nao encontrado.'), findsOneWidget);
    });

    testWidgets('shows a friendly message when the CEP service fails', (
      tester,
    ) async {
      when(
        () => cepService.lookup(any()),
      ).thenThrow(const CepException.unavailable());

      await pumpRegister(tester);
      await tester.enterText(
        find.byKey(const Key('register_cep_field')),
        '01310100',
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Servico de CEP indisponivel. Tente novamente.'),
        findsOneWidget,
      );
    });

    testWidgets('rejects a password shorter than eight characters', (
      tester,
    ) async {
      await pumpRegister(tester);
      await fillValid(tester);
      await tester.enterText(
        find.byKey(const Key('register_password_field')),
        'Ab1!xyz',
      );
      await tester.enterText(
        find.byKey(const Key('register_confirm_field')),
        'Ab1!xyz',
      );
      await tapSubmit(tester);

      expect(
        find.text('A senha deve ter no minimo 8 caracteres'),
        findsOneWidget,
      );
      expectNoRegistration();
    });

    testWidgets('rejects a password without an uppercase letter', (
      tester,
    ) async {
      await pumpRegister(tester);
      await fillValid(tester);
      await tester.enterText(
        find.byKey(const Key('register_password_field')),
        'senha@123',
      );
      await tester.enterText(
        find.byKey(const Key('register_confirm_field')),
        'senha@123',
      );
      await tapSubmit(tester);

      expect(
        find.text('A senha deve conter ao menos uma letra maiuscula'),
        findsOneWidget,
      );
      expectNoRegistration();
    });

    testWidgets('rejects a password without a number', (tester) async {
      await pumpRegister(tester);
      await fillValid(tester);
      await tester.enterText(
        find.byKey(const Key('register_password_field')),
        'Senha@abc',
      );
      await tester.enterText(
        find.byKey(const Key('register_confirm_field')),
        'Senha@abc',
      );
      await tapSubmit(tester);

      expect(
        find.text('A senha deve conter ao menos um numero'),
        findsOneWidget,
      );
      expectNoRegistration();
    });

    testWidgets('rejects a password without a special character', (
      tester,
    ) async {
      await pumpRegister(tester);
      await fillValid(tester);
      await tester.enterText(
        find.byKey(const Key('register_password_field')),
        'Senha123',
      );
      await tester.enterText(
        find.byKey(const Key('register_confirm_field')),
        'Senha123',
      );
      await tapSubmit(tester);

      expect(
        find.text('A senha deve conter ao menos um caractere especial'),
        findsOneWidget,
      );
      expectNoRegistration();
    });

    testWidgets('rejects mismatched passwords without registering', (
      tester,
    ) async {
      await pumpRegister(tester);
      await fillValid(tester);
      await tester.enterText(
        find.byKey(const Key('register_confirm_field')),
        '654321',
      );
      await tapSubmit(tester);

      expect(find.text('As senhas nao conferem'), findsOneWidget);
      expectNoRegistration();
    });

    testWidgets('rejects an invalid email without registering', (tester) async {
      await pumpRegister(tester);
      await fillValid(tester);
      await tester.enterText(
        find.byKey(const Key('register_email_field')),
        'email-invalido',
      );
      await tapSubmit(tester);

      expect(find.text('Informe um e-mail valido'), findsOneWidget);
      expectNoRegistration();
    });

    testWidgets('submits the canonical CPF and a structured address', (
      tester,
    ) async {
      when(
        () => auth.registerClient(
          name: any(named: 'name'),
          email: any(named: 'email'),
          password: any(named: 'password'),
          phone: any(named: 'phone'),
          cpf: any(named: 'cpf'),
          address: any(named: 'address'),
        ),
      ).thenAnswer((_) async {});

      await pumpRegister(tester);
      await fillValid(tester);
      await tapSubmit(tester);

      verify(
        () => auth.registerClient(
          name: 'Cliente',
          email: 'cliente@exemplo.com',
          password: 'Senha@123',
          phone: '11999999999',
          cpf: '52998224725',
          address: any(
            named: 'address',
            that: isA<PostalAddress>()
                .having(
                  (address) => address.postalCode,
                  'postalCode',
                  '01310100',
                )
                .having(
                  (address) => address.street,
                  'street',
                  'Avenida Paulista',
                )
                .having((address) => address.number, 'number', '1000')
                .having((address) => address.complement, 'complement', 'Sala 1')
                .having(
                  (address) => address.neighborhood,
                  'neighborhood',
                  'Bela Vista',
                )
                .having((address) => address.city, 'city', 'Sao Paulo')
                .having((address) => address.state, 'state', 'SP')
                .having((address) => address.country, 'country', 'BR'),
          ),
        ),
      ).called(1);
    });

    testWidgets('shows a friendly message when the CPF is already registered', (
      tester,
    ) async {
      when(
        () => auth.registerClient(
          name: any(named: 'name'),
          email: any(named: 'email'),
          password: any(named: 'password'),
          phone: any(named: 'phone'),
          cpf: any(named: 'cpf'),
          address: any(named: 'address'),
        ),
      ).thenThrow(
        FirebaseFunctionsException(
          code: 'already-exists',
          message: 'CPF ja cadastrado para outro usuario.',
        ),
      );
      when(
        () => auth.errorMessage,
      ).thenReturn('CPF ja cadastrado para outro usuario.');

      await pumpRegister(tester);
      await fillValid(tester);
      await tapSubmit(tester);
      await tester.pump();

      expect(
        find.text('CPF ja cadastrado para outro usuario.'),
        findsOneWidget,
      );
    });

    testWidgets('renders and scrolls without overflow at 360x640', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpRegister(tester);

      expect(tester.takeException(), isNull);

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -800),
      );
      await tester.pump();

      expect(find.byKey(const Key('register_submit_button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
