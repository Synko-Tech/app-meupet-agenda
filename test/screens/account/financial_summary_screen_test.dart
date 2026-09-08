import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/controllers/business_context_controller.dart';
import 'package:meupet_agenda_app/models/app_user.dart';
import 'package:meupet_agenda_app/models/business_membership.dart';
import 'package:meupet_agenda_app/models/payment_model.dart';
import 'package:meupet_agenda_app/repositories/auth_repository.dart';
import 'package:meupet_agenda_app/repositories/business_repository.dart';
import 'package:meupet_agenda_app/repositories/payment_repository.dart';
import 'package:meupet_agenda_app/repositories/user_repository.dart';
import 'package:meupet_agenda_app/screens/account/financial_summary_screen.dart';
import 'package:meupet_agenda_app/services/notification_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockBusinessRepository extends Mock implements BusinessRepository {}

class MockUserRepository extends Mock implements UserRepository {}

class MockNotificationService extends Mock implements NotificationService {}

class MockPaymentRepository extends Mock implements PaymentRepository {}

PaymentModel payment(PaymentStatus status, {DateTime? paidAt}) {
  return PaymentModel(
    id: 'pay-${status.name}',
    clientId: 'c1',
    clientName: 'Alice Silva',
    type: PaymentType.package,
    amount: 150.0,
    method: PaymentMethod.pix,
    status: status,
    paidAt: paidAt,
    createdAt: DateTime(2026, 8, 5),
  );
}

void main() {
  late MockAuthRepository authRepository;
  late MockUserRepository userRepository;
  late MockNotificationService notificationService;
  late MockPaymentRepository payments;

  setUp(() {
    authRepository = MockAuthRepository();
    userRepository = MockUserRepository();
    notificationService = MockNotificationService();
    payments = MockPaymentRepository();
    when(
      () => authRepository.authStateChanges(),
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => payments.allPaymentsStream(
        'b1',
        start: any(named: 'start'),
        endExclusive: any(named: 'endExclusive'),
      ),
    ).thenAnswer((_) => Stream.value(const []));
  });

  Future<void> pumpSummary(
    WidgetTester tester, {
    UserRole role = UserRole.admin,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final auth = AuthController(
      authRepository: authRepository,
      userRepository: userRepository,
      notificationService: notificationService,
    );
    addTearDown(auth.dispose);
    auth.profile = AppUser(
      id: 'u1',
      name: 'Bruno',
      email: 'bruno@exemplo.com',
      role: role,
    );
    auth.isLoading = false;

    final businessRepository = MockBusinessRepository();
    when(
      () => businessRepository.myMembershipsStream(any()),
    ).thenAnswer(
      (_) => Stream.value(const [
        BusinessMembership(
          userId: 'u1',
          businessId: 'b1',
          businessName: 'Loja Teste',
          role: BusinessRole.owner,
        ),
      ]),
    );
    final businessContext = BusinessContextController(
      repository: businessRepository,
      authController: auth,
    );
    addTearDown(businessContext.dispose);
    await businessContext.selectBusiness('b1');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PaymentRepository>(create: (_) => payments),
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: businessContext),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: FinancialSummaryScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('FinancialSummaryScreen', () {
    testWidgets('renders header and empty state', (tester) async {
      await pumpSummary(tester);

      expect(find.text('Resumo financeiro'), findsOneWidget);
      expect(find.text('Nenhum pagamento neste mes'), findsOneWidget);
    });

    testWidgets('renders the month selector arrows', (tester) async {
      await pumpSummary(tester);

      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('navigating months re-queries the repository', (tester) async {
      await pumpSummary(tester);

      await tester.tap(find.byKey(const Key('month_previous_button')));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final previousMonth = DateTime(now.year, now.month - 1, 1);
      final start = verify(
        () => payments.allPaymentsStream(
          'b1',
          start: captureAny(named: 'start'),
          endExclusive: any(named: 'endExclusive'),
        ),
      ).captured;
      expect(start.last, previousMonth);
    });

    testWidgets('renders KPIs from paid, pending and canceled payments', (
      tester,
    ) async {
      when(
        () => payments.allPaymentsStream(
          'b1',
          start: any(named: 'start'),
          endExclusive: any(named: 'endExclusive'),
        ),
      ).thenAnswer(
        (_) => Stream.value([
          payment(PaymentStatus.paid, paidAt: DateTime(2026, 8, 1)),
          payment(PaymentStatus.pending),
          payment(PaymentStatus.canceled, paidAt: DateTime(2026, 8, 2)),
        ]),
      );

      await pumpSummary(tester);

      expect(find.text('Recebido'), findsOneWidget);
      expect(find.text('R\$ 150,00'), findsWidgets);
      expect(find.text('Transacoes'), findsOneWidget);
      expect(find.text('Pendente'), findsWidgets);
      expect(find.text('Cancelado'), findsWidgets);
    });

    testWidgets('renders breakdown by payment type', (tester) async {
      when(
        () => payments.allPaymentsStream(
          'b1',
          start: any(named: 'start'),
          endExclusive: any(named: 'endExclusive'),
        ),
      ).thenAnswer(
        (_) => Stream.value([
          payment(PaymentStatus.paid, paidAt: DateTime(2026, 8, 1)),
        ]),
      );

      await pumpSummary(tester);

      expect(find.text('Pacotes'), findsOneWidget);
      expect(find.text('1 · R\$ 150,00'), findsOneWidget);
    });

    testWidgets('clients are blocked from the financial summary', (
      tester,
    ) async {
      await pumpSummary(tester, role: UserRole.client);

      expect(find.text('Acesso restrito'), findsOneWidget);
      expect(find.text('Resumo financeiro'), findsNothing);
    });
  });
}
