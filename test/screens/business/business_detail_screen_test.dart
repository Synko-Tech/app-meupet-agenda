import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
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
import 'package:meupet_agenda_app/widgets/app_button.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockBusinessRepository extends Mock implements BusinessRepository {}

class MockAuthController extends Mock implements AuthController {}

class MockFirebaseUser extends Mock implements User {}

void main() {
  late MockBusinessRepository repository;
  late MockAuthController authController;
  late BusinessContextController businessContext;
  late MockFirebaseUser firebaseUser;
  late StreamController<List<BusinessMembership>> membershipsController;

  final business = BusinessModel(
    id: 'b1',
    name: 'Pet Shop Central',
    description: 'Banho e tosa',
    cnpj: '11222333000181',
    phone: '1140028922',
    address: PostalAddress(
      postalCode: '01310100',
      street: 'Avenida Paulista',
      number: '1000',
      complement: 'Loja 5',
      neighborhood: 'Bela Vista',
      city: 'Sao Paulo',
      state: 'SP',
    ),
  );

  setUp(() {
    repository = MockBusinessRepository();
    authController = MockAuthController();
    firebaseUser = MockFirebaseUser();
    membershipsController = StreamController<List<BusinessMembership>>.broadcast();
    when(() => firebaseUser.uid).thenReturn('u1');
    when(() => authController.firebaseUser).thenReturn(firebaseUser);
    when(() => authController.addListener(any())).thenReturn(null);
    when(() => authController.removeListener(any())).thenReturn(null);
    when(() => repository.myMembershipsStream('u1')).thenAnswer(
      (_) => membershipsController.stream,
    );
    businessContext = BusinessContextController(
      repository: repository,
      authController: authController,
    );
  });

  tearDown(() {
    businessContext.dispose();
    membershipsController.close();
  });

  Future<void> pumpDetail(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BusinessContextController>.value(
            value: businessContext,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: BusinessDetailScreen(business: business),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('BusinessDetailScreen', () {
    testWidgets('shows the public business details', (tester) async {
      await pumpDetail(tester);

      expect(find.text('Pet Shop Central'), findsOneWidget);
      expect(find.text('Banho e tosa'), findsOneWidget);
      expect(find.textContaining('Avenida Paulista'), findsOneWidget);
      expect(find.textContaining('Sao Paulo'), findsOneWidget);
      expect(find.text('1140028922'), findsOneWidget);
      expect(find.text('**.***.***/****-81'), findsOneWidget);
      expect(
        find.byKey(const Key('business_detail_join_button')),
        findsOneWidget,
      );
    });

    testWidgets('join button calls joinBusiness and pops to the shell', (
      tester,
    ) async {
      when(
        () => repository.joinBusiness(businessId: 'b1'),
      ).thenAnswer((_) async {});

      await pumpDetail(tester);

      await tester.tap(find.byKey(const Key('business_detail_join_button')));
      await tester.pump();
      await tester.pump();

      verify(() => repository.joinBusiness(businessId: 'b1')).called(1);
      expect(businessContext.activeBusinessId, 'b1');
    });

    testWidgets('shows a friendly message when join fails', (tester) async {
      when(
        () => repository.joinBusiness(businessId: 'b1'),
      ).thenThrow(Exception('join falhou'));

      await pumpDetail(tester);

      await tester.tap(find.byKey(const Key('business_detail_join_button')));
      await tester.pump();
      await tester.pump();

      expect(find.text('join falhou'), findsOneWidget);
    });

    testWidgets('disables the join button when already a member', (
      tester,
    ) async {
      membershipsController.add(const [
        BusinessMembership(
          userId: 'u1',
          businessId: 'b1',
          role: BusinessRole.client,
          businessName: 'Pet Shop Central',
        ),
      ]);
      await tester.pump();

      await pumpDetail(tester);

      final button = tester.widget<AppButton>(
        find.byKey(const Key('business_detail_join_button')),
      );
      expect(button.onPressed, isNull);
      expect(find.text('Voce ja faz parte deste pet shop'), findsOneWidget);
    });
  });
}
