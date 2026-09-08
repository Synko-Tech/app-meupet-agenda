import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/controllers/business_context_controller.dart';
import 'package:meupet_agenda_app/repositories/business_repository.dart';
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

  Future<void> pumpCreate(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BusinessContextController>.value(
            value: businessContext,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const CreateBusinessScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('CreateBusinessScreen', () {
    testWidgets('requires a business name', (tester) async {
      await pumpCreate(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Criar loja'));
      await tester.pumpAndSettle();

      expect(find.text('Campo obrigatorio'), findsOneWidget);
      verifyNever(
        () => repository.createBusiness(
          name: any(named: 'name'),
          description: any(named: 'description'),
        ),
      );
    });

    testWidgets('creates the business with the typed name', (tester) async {
      when(
        () => repository.createBusiness(
          name: any(named: 'name'),
          description: any(named: 'description'),
        ),
      ).thenAnswer((_) async => const CreatedBusiness(businessId: 'b1'));

      await pumpCreate(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Pet Shop');
      await tester.tap(find.widgetWithText(FilledButton, 'Criar loja'));
      await tester.pumpAndSettle();

      verify(
        () => repository.createBusiness(
          name: 'Pet Shop',
          description: any(named: 'description', that: isNull),
        ),
      ).called(1);
    });

    testWidgets('shows a snackbar when creation fails', (tester) async {
      when(
        () => repository.createBusiness(
          name: any(named: 'name'),
          description: any(named: 'description'),
        ),
      ).thenThrow(StateError('Resposta invalida do servidor.'));

      await pumpCreate(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Pet Shop');
      await tester.tap(find.widgetWithText(FilledButton, 'Criar loja'));
      await tester.pumpAndSettle();

      expect(find.text('Resposta invalida do servidor.'), findsOneWidget);
    });
  });
}
