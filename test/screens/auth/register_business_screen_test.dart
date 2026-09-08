import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/models/postal_address.dart';
import 'package:meupet_agenda_app/screens/auth/register_business_screen.dart';
import 'package:meupet_agenda_app/services/cep_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockAuthController extends Mock implements AuthController {}

class MockCepService extends Mock implements CepService {}

const _allFieldKeys = <String>[
  'register_business_name_field',
  'register_business_email_field',
  'register_business_phone_field',
  'register_business_cpf_field',
  'register_business_password_field',
  'register_business_confirm_field',
  'register_business_cnpj_field',
  'register_business_business_name_field',
  'register_business_legal_name_field',
  'register_business_business_phone_field',
  'register_business_description_field',
  'register_business_cep_field',
  'register_business_street_field',
  'register_business_number_field',
  'register_business_complement_field',
  'register_business_neighborhood_field',
  'register_business_city_field',
  'register_business_uf_field',
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

  Future<void> pumpRegisterBusiness(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          Provider<CepService>.value(value: cepService),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const RegisterBusinessScreen(),
        ),
      ),
    );
  }

  Future<void> fillValid(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('register_business_name_field')),
      'Fulano de Tal',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_email_field')),
      'dono@pet.com',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_phone_field')),
      '11999999999',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_cpf_field')),
      '529.982.247-25',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_password_field')),
      'Senha@123',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_confirm_field')),
      'Senha@123',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_cnpj_field')),
      '11.222.333/0001-81',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_business_name_field')),
      'Pet Shop Central',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_legal_name_field')),
      'Central Pet Comercio LTDA',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_business_phone_field')),
      '1140028922',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_description_field')),
      'Banho e tosa',
    );
    await tester.enterText(
      find.byKey(const Key('register_business_cep_field')),
      '01310-100',
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
      find.byKey(const Key('register_business_complement_field')),
      'Loja 5',
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
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('register_business_submit_button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('register_business_submit_button')));
    await tester.pump();
  }

  void expectNoRegistration() {
    verifyNever(
      () => auth.registerBusiness(
        name: any(named: 'name'),
        email: any(named: 'email'),
        password: any(named: 'password'),
        phone: any(named: 'phone'),
        cpf: any(named: 'cpf'),
        cnpj: any(named: 'cnpj'),
        businessName: any(named: 'businessName'),
        businessLegalName: any(named: 'businessLegalName'),
        businessPhone: any(named: 'businessPhone'),
        businessDescription: any(named: 'businessDescription'),
        address: any(named: 'address'),
      ),
    );
  }

  group('RegisterBusinessScreen', () {
    testWidgets('shows all registration fields', (tester) async {
      await pumpRegisterBusiness(tester);

      for (final key in _allFieldKeys) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(
        find.byKey(const Key('register_business_submit_button')),
        findsOneWidget,
      );
    });

    testWidgets('rejects an invalid CNPJ without registering', (tester) async {
      await pumpRegisterBusiness(tester);
      await fillValid(tester);
      await tester.enterText(
        find.byKey(const Key('register_business_cnpj_field')),
        '11.222.333/0001-82',
      );
      await tapSubmit(tester);

      expect(find.text('CNPJ invalido'), findsOneWidget);
      expectNoRegistration();
    });

    testWidgets('rejects an invalid CPF without registering', (tester) async {
      await pumpRegisterBusiness(tester);
      await fillValid(tester);
      await tester.enterText(
        find.byKey(const Key('register_business_cpf_field')),
        '123.456.789-00',
      );
      await tapSubmit(tester);

      expect(find.text('CPF invalido'), findsOneWidget);
      expectNoRegistration();
    });

    testWidgets('rejects an invalid CEP without registering', (tester) async {
      await pumpRegisterBusiness(tester);
      await fillValid(tester);
      await tester.enterText(
        find.byKey(const Key('register_business_cep_field')),
        '12345',
      );
      await tapSubmit(tester);

      expect(find.text('CEP invalido'), findsOneWidget);
      expectNoRegistration();
    });

    testWidgets('requires the business name', (tester) async {
      await pumpRegisterBusiness(tester);
      await fillValid(tester);
      await tester.enterText(
        find.byKey(const Key('register_business_business_name_field')),
        '',
      );
      await tapSubmit(tester);

      expect(find.text('Campo obrigatorio'), findsOneWidget);
      expectNoRegistration();
    });

    testWidgets('rejects mismatched passwords without registering', (
      tester,
    ) async {
      await pumpRegisterBusiness(tester);
      await fillValid(tester);
      await tester.enterText(
        find.byKey(const Key('register_business_confirm_field')),
        '654321',
      );
      await tapSubmit(tester);

      expect(find.text('As senhas nao conferem'), findsOneWidget);
      expectNoRegistration();
    });

    testWidgets('prefills the address from ViaCEP on eight digits', (
      tester,
    ) async {
      await pumpRegisterBusiness(tester);

      await tester.enterText(
        find.byKey(const Key('register_business_cep_field')),
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

    testWidgets('submits canonical CPF/CNPJ and a structured address', (
      tester,
    ) async {
      when(
        () => auth.registerBusiness(
          name: any(named: 'name'),
          email: any(named: 'email'),
          password: any(named: 'password'),
          phone: any(named: 'phone'),
          cpf: any(named: 'cpf'),
          cnpj: any(named: 'cnpj'),
          businessName: any(named: 'businessName'),
          businessLegalName: any(named: 'businessLegalName'),
          businessPhone: any(named: 'businessPhone'),
          businessDescription: any(named: 'businessDescription'),
          address: any(named: 'address'),
        ),
      ).thenAnswer((_) async {});

      await pumpRegisterBusiness(tester);
      await fillValid(tester);
      await tapSubmit(tester);

      verify(
        () => auth.registerBusiness(
          name: 'Fulano de Tal',
          email: 'dono@pet.com',
          password: 'Senha@123',
          phone: '11999999999',
          cpf: '52998224725',
          cnpj: '11222333000181',
          businessName: 'Pet Shop Central',
          businessLegalName: 'Central Pet Comercio LTDA',
          businessPhone: '1140028922',
          businessDescription: 'Banho e tosa',
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
                .having((address) => address.complement, 'complement', 'Loja 5')
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

    testWidgets(
      'shows a friendly message when the CNPJ is already registered',
      (tester) async {
        when(
          () => auth.registerBusiness(
            name: any(named: 'name'),
            email: any(named: 'email'),
            password: any(named: 'password'),
            phone: any(named: 'phone'),
            cpf: any(named: 'cpf'),
            cnpj: any(named: 'cnpj'),
            businessName: any(named: 'businessName'),
            businessLegalName: any(named: 'businessLegalName'),
            businessPhone: any(named: 'businessPhone'),
            businessDescription: any(named: 'businessDescription'),
            address: any(named: 'address'),
          ),
        ).thenThrow(
          FirebaseFunctionsException(
            code: 'already-exists',
            message: 'CNPJ ja cadastrado para outra loja.',
          ),
        );
        when(
          () => auth.errorMessage,
        ).thenReturn('CNPJ ja cadastrado para outra loja.');

        await pumpRegisterBusiness(tester);
        await fillValid(tester);
        await tapSubmit(tester);
        await tester.pump();

        expect(
          find.text('CNPJ ja cadastrado para outra loja.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('renders and scrolls without overflow at 360x640', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpRegisterBusiness(tester);

      expect(tester.takeException(), isNull);

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1200),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('register_business_submit_button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
