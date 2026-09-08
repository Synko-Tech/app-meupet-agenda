import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/controllers/business_context_controller.dart';
import 'package:meupet_agenda_app/models/business_membership.dart';
import 'package:meupet_agenda_app/repositories/business_repository.dart';
import 'package:meupet_agenda_app/screens/business/business_selector_screen.dart';
import 'package:meupet_agenda_app/screens/business/create_business_screen.dart';
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
  });

  tearDown(() {
    businessContext.dispose();
  });

  Future<void> pumpSelector(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BusinessContextController>.value(
            value: businessContext,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const BusinessSelectorScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('BusinessSelectorScreen', () {
    testWidgets('shows the empty state and create CTA when there are no '
        'businesses', (tester) async {
      await pumpSelector(tester);

      expect(find.text('Suas lojas'), findsOneWidget);
      expect(find.text('Nenhuma loja'), findsOneWidget);
      expect(find.text('Criar loja'), findsOneWidget);
    });

    testWidgets('lists businesses the user belongs to with their roles', (
      tester,
    ) async {
      businessContext.memberships = [
        BusinessMembership(
          userId: 'u1',
          businessId: 'b1',
          businessName: 'Pet Shop Central',
          role: BusinessRole.owner,
        ),
        BusinessMembership(
          userId: 'u1',
          businessId: 'b2',
          businessName: 'Banho & Tosa',
          role: BusinessRole.admin,
        ),
      ];
      businessContext.isLoading = false;

      await pumpSelector(tester);

      expect(find.text('Pet Shop Central'), findsOneWidget);
      expect(find.text('Banho & Tosa'), findsOneWidget);
      expect(find.text('Dono'), findsOneWidget);
      expect(find.text('Administrador'), findsOneWidget);
      expect(find.text('Nenhuma loja'), findsNothing);
    });

    testWidgets('marks the active business with an Ativa badge', (
      tester,
    ) async {
      businessContext.memberships = [
        BusinessMembership(
          userId: 'u1',
          businessId: 'b1',
          businessName: 'Pet Shop Central',
          role: BusinessRole.owner,
        ),
      ];
      businessContext.activeBusinessId = 'b1';
      businessContext.isLoading = false;

      await pumpSelector(tester);

      expect(find.text('Ativa'), findsOneWidget);
    });

    testWidgets('navigates to create business screen from the empty state', (
      tester,
    ) async {
      await pumpSelector(tester);

      await tester.tap(find.text('Criar loja'));
      await tester.pumpAndSettle();

      expect(find.byType(CreateBusinessScreen), findsOneWidget);
    });

    testWidgets('selecting a business sets it as active and pops the route', (
      tester,
    ) async {
      businessContext.memberships = [
        BusinessMembership(
          userId: 'u1',
          businessId: 'b1',
          businessName: 'Pet Shop Central',
          role: BusinessRole.owner,
        ),
      ];
      businessContext.isLoading = false;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BusinessContextController>.value(
              value: businessContext,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BusinessSelectorScreen(),
                      ),
                    ),
                    child: const Text('abrir'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pet Shop Central'));
      await tester.pumpAndSettle();

      expect(businessContext.activeBusinessId, 'b1');
      expect(find.text('abrir'), findsOneWidget);
    });
  });
}
