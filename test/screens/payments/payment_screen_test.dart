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
import 'package:meupet_agenda_app/screens/payments/payment_screen.dart';
import 'package:meupet_agenda_app/services/notification_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockUserRepository extends Mock implements UserRepository {}

class MockNotificationService extends Mock implements NotificationService {}

class MockPaymentRepository extends Mock implements PaymentRepository {}

class MockBusinessRepository extends Mock implements BusinessRepository {}

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
    createdAt: DateTime(2026, 8, 1),
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

  Future<void> pumpPayments(
    WidgetTester tester, {
    UserRole role = UserRole.admin,
  }) async {
    final auth = AuthController(
      authRepository: authRepository,
      userRepository: userRepository,
      notificationService: notificationService,
    );
    addTearDown(auth.dispose);
    auth.profile = AppUser(
      id: 'u1',
      name: 'Atendente',
      email: 'atendente@exemplo.com',
      role: role,
    );
    auth.isLoading = false;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PaymentRepository>(create: (_) => payments),
          ChangeNotifierProvider(
            create: (_) {
              final repo = MockBusinessRepository();
              when(() => repo.myMembershipsStream(any())).thenAnswer(
                (_) => Stream.value(const [
                  BusinessMembership(
                    userId: 'u1',
                    businessId: 'b1',
                    businessName: 'Loja Teste',
                    role: BusinessRole.owner,
                  ),
                ]),
              );
              final ctx = BusinessContextController(
                repository: repo,
                authController: auth,
              );
              ctx.selectBusiness('b1');
              return ctx;
            },
          ),
          ChangeNotifierProvider.value(value: auth),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: PaymentScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('PaymentScreen', () {
    testWidgets('staff see the month period filter with Alterar/Limpar', (
      tester,
    ) async {
      await pumpPayments(tester);

      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final last = DateTime(
        now.year,
        now.month + 1,
        1,
      ).subtract(const Duration(days: 1));

      expect(
        find.text('${formatDateForTest(start)} - ${formatDateForTest(last)}'),
        findsOneWidget,
      );
      expect(find.text('Alterar'), findsOneWidget);
      expect(find.text('Limpar'), findsOneWidget);
    });

    testWidgets('passes the current month window to the repository', (
      tester,
    ) async {
      await pumpPayments(tester);

      final now = DateTime.now();
      verify(
        () => payments.allPaymentsStream(
          'b1',
          start: DateTime(now.year, now.month, 1),
          endExclusive: DateTime(now.year, now.month + 1, 1),
        ),
      ).called(1);
    });

    testWidgets('clients do not see the period filter control', (tester) async {
      when(
        () => payments.customerPaymentsStream(
          'b1',
          any(),
          start: any(named: 'start'),
          endExclusive: any(named: 'endExclusive'),
        ),
      ).thenAnswer((_) => Stream.value(const []));

      await pumpPayments(tester, role: UserRole.client);

      expect(find.text('Alterar'), findsNothing);
      expect(find.text('Limpar'), findsNothing);
    });

    testWidgets('clearing the filter queries without the window', (
      tester,
    ) async {
      await pumpPayments(tester);

      await tester.tap(find.byKey(const Key('payment_period_clear_button')));
      await tester.pumpAndSettle();

      final starts = verify(
        () => payments.allPaymentsStream(
          'b1',
          start: captureAny(named: 'start'),
          endExclusive: any(named: 'endExclusive'),
        ),
      ).captured;
      expect(starts, isNotEmpty);
      expect(starts.last, isNull);
    });

    testWidgets('shows an oriented empty state for the period', (tester) async {
      await pumpPayments(tester);

      expect(find.text('Nenhum pagamento neste periodo'), findsOneWidget);
    });

    testWidgets('shows pending payments as awaiting payment', (tester) async {
      when(
        () => payments.allPaymentsStream(
          'b1',
          start: any(named: 'start'),
          endExclusive: any(named: 'endExclusive'),
        ),
      ).thenAnswer(
        (_) => Stream.value([
          payment(PaymentStatus.paid, paidAt: DateTime(2026, 7, 20)),
          payment(PaymentStatus.pending),
        ]),
      );

      await pumpPayments(tester);

      expect(find.textContaining('Alice Silva'), findsNWidgets(2));
      expect(find.textContaining('Aguardando pagamento'), findsOneWidget);
      expect(find.textContaining('20/07/2026'), findsOneWidget);
    });

    testWidgets('renders all five status badges without a dropdown', (
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
          payment(PaymentStatus.paid, paidAt: DateTime(2026, 7, 1)),
          payment(PaymentStatus.pending),
          payment(PaymentStatus.canceled, paidAt: DateTime(2026, 7, 2)),
          payment(PaymentStatus.refunded, paidAt: DateTime(2026, 7, 3)),
          payment(PaymentStatus.underReview),
        ]),
      );

      await pumpPayments(tester);

      expect(find.text('Pago'), findsOneWidget);
      expect(find.text('Pendente'), findsOneWidget);
      expect(find.text('Cancelado'), findsOneWidget);
      expect(find.text('Reembolsado'), findsOneWidget);
      expect(find.text('Em analise'), findsOneWidget);
      expect(find.byType(DropdownButton<PaymentStatus>), findsNothing);
    });

    testWidgets('shows an error state instead of an empty state', (
      tester,
    ) async {
      when(
        () => payments.allPaymentsStream(
          'b1',
          start: any(named: 'start'),
          endExclusive: any(named: 'endExclusive'),
        ),
      ).thenAnswer((_) => Stream<List<PaymentModel>>.error(StateError('boom')));

      await pumpPayments(tester);

      expect(find.text('Nenhum pagamento neste periodo'), findsNothing);
      expect(find.text('Nao foi possivel carregar'), findsOneWidget);
    });
  });
}

String formatDateForTest(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year}';
}
