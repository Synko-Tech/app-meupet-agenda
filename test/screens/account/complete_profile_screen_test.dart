import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/models/app_user.dart';
import 'package:meupet_agenda_app/models/postal_address.dart';
import 'package:meupet_agenda_app/screens/account/complete_profile_screen.dart';
import 'package:meupet_agenda_app/services/cep_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockAuthController extends Mock implements AuthController {}

class MockCepService extends Mock implements CepService {}

const _incompleteProfile = AppUser(
  id: 'u1',
  name: 'Cliente Antigo',
  email: 'cliente@exemplo.com',
  phone: '11988887777',
  role: UserRole.client,
  isActive: true,
  profileComplete: false,
);

const _allFieldKeys = <String>[
  'complete_profile_name_field',
  'complete_profile_phone_field',
  'complete_profile_cpf_field',
  'complete_profile_cep_field',
  'complete_profile_street_field',
  'complete_profile_number_field',
  'complete_profile_complement_field',
  'complete_profile_neighborhood_field',
  'complete_profile_city_field',
  'complete_profile_uf_field',
];

const _explanation =
    'Antes de comecar, precisamos do seu CPF e endereco para identificar '
    'voce e garantir a seguranca dos agendamentos e pagamentos.';

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
    when(() => auth.profile).thenReturn(_incompleteProfile);
    when(() => auth.errorMessage).thenReturn(null);
    when(() => cepService.lookup(any())).thenAnswer(
      (_) async => const PostalAddressLookup(
        postalCode: '01310100',
        street: 'Avenida Paulista',
        neighborhood: 'Bela Vista',
        city: 'Sao Paulo',
        state: 'SP',
      ),
    );
    when(
      () => auth.completeOwnProfile(
        name: any(named: 'name'),
        phone: any(named: 'phone'),
        cpf: any(named: 'cpf'),
        address: any(named: 'address'),
      ),
    ).thenAnswer((_) async {});
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          Provider<CepService>.value(value: cepService),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const CompleteProfileScreen(),
        ),
      ),
    );
  }

  Future<void> fillValid(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('complete_profile_cpf_field')),
      '529.982.247-25',
    );
    await tester.enterText(
      find.byKey(const Key('complete_profile_cep_field')),
      '01310-100',
    );
    await tester.enterText(
      find.byKey(const Key('complete_profile_street_field')),
      'Avenida Paulista',
    );
    await tester.enterText(
      find.byKey(const Key('complete_profile_number_field')),
      '1000',
    );
    await tester.enterText(
      find.byKey(const Key('complete_profile_complement_field')),
      'Sala 1',
    );
    await tester.enterText(
      find.byKey(const Key('complete_profile_neighborhood_field')),
      'Bela Vista',
    );
    await tester.enterText(
      find.byKey(const Key('complete_profile_city_field')),
      'Sao Paulo',
    );
    await tester.enterText(
      find.byKey(const Key('complete_profile_uf_field')),
      'SP',
    );
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('complete_profile_submit_button')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('complete_profile_submit_button')));
    await tester.pump();
  }

  void expectNoCompletion() {
    verifyNever(
      () => auth.completeOwnProfile(
        name: any(named: 'name'),
        phone: any(named: 'phone'),
        cpf: any(named: 'cpf'),
        address: any(named: 'address'),
      ),
    );
  }

  group('CompleteProfileScreen', () {
    testWidgets('shows the explanation, the logout button and all fields', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text(_explanation), findsOneWidget);
      expect(
        find.byKey(const Key('complete_profile_logout_button')),
        findsOneWidget,
      );
      for (final key in _allFieldKeys) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(
        find.byKey(const Key('complete_profile_submit_button')),
        findsOneWidget,
      );
    });

    testWidgets('prefills name and phone from the incomplete profile', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Cliente Antigo'), findsOneWidget);
      expect(find.text('11988887777'), findsOneWidget);
    });

    testWidgets('logs out', (tester) async {
      when(() => auth.signOut()).thenAnswer((_) async {});

      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('complete_profile_logout_button')));
      await tester.pump();

      verify(() => auth.signOut()).called(1);
    });

    testWidgets('rejects an invalid CPF without submitting', (tester) async {
      await pumpScreen(tester);
      await fillValid(tester);
      await tester.enterText(
        find.byKey(const Key('complete_profile_cpf_field')),
        '123.456.789-00',
      );
      await tapSubmit(tester);

      expect(find.text('CPF invalido'), findsOneWidget);
      expectNoCompletion();
    });

    testWidgets('requires the address fields', (tester) async {
      await pumpScreen(tester);
      await fillValid(tester);
      await tester.enterText(
        find.byKey(const Key('complete_profile_street_field')),
        '',
      );
      await tapSubmit(tester);

      expect(find.text('Campo obrigatorio'), findsOneWidget);
      expectNoCompletion();
    });

    testWidgets('prefills the address from ViaCEP on eight digits', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.byKey(const Key('complete_profile_cep_field')),
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

    testWidgets('shows a friendly message when the CEP is not found', (
      tester,
    ) async {
      when(
        () => cepService.lookup(any()),
      ).thenThrow(const CepException.notFound());

      await pumpScreen(tester);
      await tester.enterText(
        find.byKey(const Key('complete_profile_cep_field')),
        '99999999',
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('CEP nao encontrado.'), findsOneWidget);
    });

    testWidgets('submits the canonical CPF and a structured address', (
      tester,
    ) async {
      await pumpScreen(tester);
      await fillValid(tester);
      await tapSubmit(tester);

      verify(
        () => auth.completeOwnProfile(
          name: 'Cliente Antigo',
          phone: '11988887777',
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

    testWidgets('submits a null phone when the phone field is cleared', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.enterText(
        find.byKey(const Key('complete_profile_phone_field')),
        '',
      );
      await fillValid(tester);
      await tapSubmit(tester);

      verify(
        () => auth.completeOwnProfile(
          name: 'Cliente Antigo',
          phone: null,
          cpf: '52998224725',
          address: any(named: 'address'),
        ),
      ).called(1);
    });

    testWidgets('stays open and shows a friendly message when the CPF is '
        'already registered', (tester) async {
      when(
        () => auth.completeOwnProfile(
          name: any(named: 'name'),
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

      await pumpScreen(tester);
      await fillValid(tester);
      await tapSubmit(tester);
      await tester.pump();

      expect(
        find.text('CPF ja cadastrado para outro usuario.'),
        findsOneWidget,
      );
      expect(find.byType(CompleteProfileScreen), findsOneWidget);
    });

    testWidgets('stays open when the callable fails without a friendly '
        'message', (tester) async {
      when(
        () => auth.completeOwnProfile(
          name: any(named: 'name'),
          phone: any(named: 'phone'),
          cpf: any(named: 'cpf'),
          address: any(named: 'address'),
        ),
      ).thenThrow(Exception('offline'));

      await pumpScreen(tester);
      await fillValid(tester);
      await tapSubmit(tester);
      await tester.pump();

      expect(
        find.text('Nao foi possivel completar o cadastro.'),
        findsOneWidget,
      );
      expect(find.byType(CompleteProfileScreen), findsOneWidget);
    });
  });
}
