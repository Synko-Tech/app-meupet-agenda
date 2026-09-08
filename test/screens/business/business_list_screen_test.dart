import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/controllers/business_context_controller.dart';
import 'package:meupet_agenda_app/models/business_membership.dart';
import 'package:meupet_agenda_app/models/business_model.dart';
import 'package:meupet_agenda_app/models/postal_address.dart';
import 'package:meupet_agenda_app/repositories/business_repository.dart';
import 'package:meupet_agenda_app/screens/business/business_detail_screen.dart';
import 'package:meupet_agenda_app/screens/business/business_list_screen.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockBusinessRepository extends Mock implements BusinessRepository {}

class MockAuthController extends Mock implements AuthController {}

void main() {
  late MockBusinessRepository repository;
  late MockAuthController authController;
  late BusinessContextController businessContext;

  setUp(() {
    repository = MockBusinessRepository();
    authController = MockAuthController();
    when(() => authController.firebaseUser).thenReturn(null);
    when(() => authController.addListener(any())).thenReturn(null);
    when(() => authController.removeListener(any())).thenReturn(null);
    businessContext = BusinessContextController(
      repository: repository,
      authController: authController,
    );
    when(() => repository.myMembershipsStream(any())).thenAnswer(
      (_) => Stream.value(const <BusinessMembership>[]),
    );
  });

  tearDown(() {
    businessContext.dispose();
  });

  BusinessModel business({
    String id = 'b1',
    String name = 'Pet Shop Central',
    String? city = 'Sao Paulo',
  }) {
    return BusinessModel(
      id: id,
      name: name,
      description: 'Banho e tosa',
      address: city == null
          ? null
          : PostalAddress(
              postalCode: '01310100',
              street: 'Avenida Paulista',
              number: '1000',
              neighborhood: 'Bela Vista',
              city: city,
              state: 'SP',
            ),
    );
  }

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BusinessRepository>.value(value: repository),
          ChangeNotifierProvider<BusinessContextController>.value(
            value: businessContext,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const BusinessListScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('BusinessListScreen', () {
    testWidgets('shows the search field and header', (tester) async {
      when(
        () => repository.publicBusinessesStream(),
      ).thenAnswer((_) => Stream.value(const <BusinessModel>[]));

      await pumpList(tester);

      expect(find.text('Encontre um pet shop'), findsOneWidget);
      expect(
        find.byKey(const Key('business_list_search_field')),
        findsOneWidget,
      );
    });

    testWidgets('shows the empty state when there are no businesses', (
      tester,
    ) async {
      when(
        () => repository.publicBusinessesStream(),
      ).thenAnswer((_) => Stream.value(const <BusinessModel>[]));

      await pumpList(tester);

      expect(find.text('Nenhum pet shop cadastrado'), findsOneWidget);
    });

    testWidgets('lists active businesses with name and city', (tester) async {
      when(() => repository.publicBusinessesStream()).thenAnswer(
        (_) => Stream.value([
          business(id: 'b1', name: 'Pet Shop Central'),
          business(id: 'b2', name: 'Tosa Legal', city: 'Campinas'),
        ]),
      );

      await pumpList(tester);

      expect(find.text('Pet Shop Central'), findsOneWidget);
      expect(find.text('Tosa Legal'), findsOneWidget);
      expect(find.textContaining('Sao Paulo'), findsOneWidget);
      expect(find.textContaining('Campinas'), findsOneWidget);
    });

    testWidgets('filters by name', (tester) async {
      when(() => repository.publicBusinessesStream()).thenAnswer(
        (_) => Stream.value([
          business(id: 'b1', name: 'Pet Shop Central'),
          business(id: 'b2', name: 'Tosa Legal'),
        ]),
      );

      await pumpList(tester);
      await tester.enterText(
        find.byKey(const Key('business_list_search_field')),
        'tosa',
      );
      await tester.pump();

      expect(find.text('Pet Shop Central'), findsNothing);
      expect(find.text('Tosa Legal'), findsOneWidget);
    });

    testWidgets('filters by city', (tester) async {
      when(() => repository.publicBusinessesStream()).thenAnswer(
        (_) => Stream.value([
          business(id: 'b1', name: 'Pet Shop Central', city: 'Sao Paulo'),
          business(id: 'b2', name: 'Tosa Legal', city: 'Campinas'),
        ]),
      );

      await pumpList(tester);
      await tester.enterText(
        find.byKey(const Key('business_list_search_field')),
        'campinas',
      );
      await tester.pump();

      expect(find.text('Pet Shop Central'), findsNothing);
      expect(find.text('Tosa Legal'), findsOneWidget);
    });

    testWidgets('shows a message when no business matches the search', (
      tester,
    ) async {
      when(() => repository.publicBusinessesStream()).thenAnswer(
        (_) => Stream.value([business(id: 'b1', name: 'Pet Shop Central')]),
      );

      await pumpList(tester);
      await tester.enterText(
        find.byKey(const Key('business_list_search_field')),
        'nao existe',
      );
      await tester.pump();

      expect(find.text('Nenhum pet shop encontrado.'), findsOneWidget);
    });

    testWidgets('tapping a business opens its detail screen', (tester) async {
      when(() => repository.publicBusinessesStream()).thenAnswer(
        (_) => Stream.value([business(id: 'b1', name: 'Pet Shop Central')]),
      );

      await pumpList(tester);

      await tester.tap(find.text('Pet Shop Central'));
      await tester.pumpAndSettle();

      expect(find.byType(BusinessDetailScreen), findsOneWidget);
      expect(find.text('Entrar neste pet shop'), findsOneWidget);
    });
  });
}
