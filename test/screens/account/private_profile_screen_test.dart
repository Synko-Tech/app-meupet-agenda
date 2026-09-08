import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/models/postal_address.dart';
import 'package:meupet_agenda_app/models/private_profile.dart';
import 'package:meupet_agenda_app/repositories/private_profile_repository.dart';
import 'package:meupet_agenda_app/screens/account/private_profile_screen.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockPrivateProfileRepository extends Mock
    implements PrivateProfileRepository {}

const _profile = PrivateProfile(
  userId: 'u1',
  cpfCanonical: '52998224725',
  cpfLast2: '25',
  address: PostalAddress(
    postalCode: '01310100',
    street: 'Avenida Paulista',
    number: '1578',
    complement: '8 andar',
    neighborhood: 'Bela Vista',
    city: 'Sao Paulo',
    state: 'SP',
  ),
);

void main() {
  late MockPrivateProfileRepository repository;

  setUpAll(() {
    registerFallbackValue(
      const PostalAddress(
        postalCode: '01310100',
        street: 'Avenida Paulista',
        number: '1578',
        neighborhood: 'Bela Vista',
        city: 'Sao Paulo',
        state: 'SP',
      ),
    );
  });

  setUp(() {
    repository = MockPrivateProfileRepository();
    when(
      () => repository.privateProfileStream(any()),
    ).thenAnswer((_) => Stream.value(_profile));
    when(
      () => repository.updateOwnAddress(address: any(named: 'address')),
    ).thenAnswer((_) async {});
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    String userId = 'u1',
    String? ownUid,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PrivateProfileRepository>.value(value: repository),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: PrivateProfileScreen(userId: userId, ownUid: ownUid),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('PrivateProfileScreen', () {
    testWidgets('shows the masked CPF and the full address, with no editable '
        'CPF field', (tester) async {
      await pumpScreen(tester);

      expect(find.text('***.***.***-25'), findsOneWidget);
      expect(find.text('01310100'), findsOneWidget);
      expect(find.text('Avenida Paulista'), findsOneWidget);
      expect(find.text('1578'), findsOneWidget);
      expect(find.text('8 andar'), findsOneWidget);
      expect(find.text('Bela Vista'), findsOneWidget);
      expect(find.text('Sao Paulo'), findsOneWidget);
      expect(find.text('SP'), findsOneWidget);
      // CPF nunca e editavel: nenhum campo de texto na tela, e o CPF
      // completo jamais aparece.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('52998224725'), findsNothing);
    });

    testWidgets('shows an empty state when the private document is missing', (
      tester,
    ) async {
      when(
        () => repository.privateProfileStream(any()),
      ).thenAnswer((_) => Stream.value(null));
      await pumpScreen(tester);

      expect(find.text('Dados privados nao encontrados'), findsOneWidget);
    });

    testWidgets('shows a friendly message when the rules deny the read', (
      tester,
    ) async {
      when(
        () => repository.privateProfileStream(any()),
      ).thenAnswer(
        (_) => Stream.error(
          FirebaseException(
            plugin: 'firestore',
            code: 'permission-denied',
            message:
                'PERMISSION_DENIED: Missing or insufficient permissions.',
          ),
        ),
      );
      await pumpScreen(tester);

      expect(
        find.text('Voce nao tem permissao para esta acao.'),
        findsOneWidget,
      );
    });

    testWidgets('hides the edit button when viewing another user\'s private '
        'profile (super admin lookup)', (tester) async {
      await pumpScreen(tester, userId: 'u2', ownUid: 'u1');

      expect(find.text('***.***.***-25'), findsOneWidget);
      expect(
        find.byKey(const Key('private_profile_edit_address_button')),
        findsNothing,
      );
    });

    testWidgets('shows the edit button for the owner\'s own profile', (
      tester,
    ) async {
      await pumpScreen(tester, userId: 'u1', ownUid: 'u1');

      expect(
        find.byKey(const Key('private_profile_edit_address_button')),
        findsOneWidget,
      );
    });

    testWidgets('edits the address through the bottom sheet and saves', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Editar endereco'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('edit_address_street_field')), findsOneWidget);
      final streetField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('edit_address_street_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(streetField.controller!.text, 'Avenida Paulista');

      await tester.enterText(
        find.byKey(const Key('edit_address_street_field')),
        'Rua Nova',
      );
      await tester.tap(find.text('Salvar endereco'));
      await tester.pumpAndSettle();

      verify(
        () => repository.updateOwnAddress(
          address: any(
            named: 'address',
            that: isA<PostalAddress>()
                .having((address) => address.postalCode, 'postalCode', '01310100')
                .having((address) => address.street, 'street', 'Rua Nova')
                .having((address) => address.number, 'number', '1578')
                .having((address) => address.complement, 'complement', '8 andar')
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
      expect(find.byKey(const Key('edit_address_street_field')), findsNothing);
      expect(find.text('Endereco atualizado.'), findsOneWidget);
    });

    testWidgets('requires the address fields before saving', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Editar endereco'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('edit_address_street_field')),
        '',
      );
      await tester.tap(find.text('Salvar endereco'));
      await tester.pump();

      expect(find.text('Campo obrigatorio'), findsWidgets);
      verifyNever(
        () => repository.updateOwnAddress(address: any(named: 'address')),
      );
    });

    testWidgets('keeps the sheet open and shows a friendly message when '
        'saving fails', (tester) async {
      when(
        () => repository.updateOwnAddress(address: any(named: 'address')),
      ).thenThrow(
        FirebaseFunctionsException(
          code: 'invalid-argument',
          message: 'CEP invalido.',
        ),
      );
      await pumpScreen(tester);

      await tester.tap(find.text('Editar endereco'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar endereco'));
      await tester.pumpAndSettle();

      expect(find.text('CEP invalido.'), findsOneWidget);
      expect(find.byKey(const Key('edit_address_street_field')), findsOneWidget);
    });

    testWidgets('address form does not overflow with the keyboard open at a '
        'small viewport', (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpScreen(tester);
      await tester.tap(find.text('Editar endereco'));
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 400);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsWidgets);

      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
