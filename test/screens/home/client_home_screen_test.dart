import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/app/formatters.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/controllers/business_context_controller.dart';
import 'package:meupet_agenda_app/models/app_user.dart';
import 'package:meupet_agenda_app/models/appointment_model.dart';
import 'package:meupet_agenda_app/models/business_membership.dart';
import 'package:meupet_agenda_app/models/package_model.dart';
import 'package:meupet_agenda_app/models/payment_model.dart';
import 'package:meupet_agenda_app/repositories/appointment_repository.dart';
import 'package:meupet_agenda_app/repositories/auth_repository.dart';
import 'package:meupet_agenda_app/repositories/business_repository.dart';
import 'package:meupet_agenda_app/repositories/package_repository.dart';
import 'package:meupet_agenda_app/repositories/payment_repository.dart';
import 'package:meupet_agenda_app/repositories/user_repository.dart';
import 'package:meupet_agenda_app/screens/home/client_home_screen.dart';
import 'package:meupet_agenda_app/services/notification_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockBusinessRepository extends Mock implements BusinessRepository {}

class MockUserRepository extends Mock implements UserRepository {}

class MockNotificationService extends Mock implements NotificationService {}

class MockAppointmentRepository extends Mock implements AppointmentRepository {}

class MockPackageRepository extends Mock implements PackageRepository {}

class MockPaymentRepository extends Mock implements PaymentRepository {}

AppUser clientUser() {
  return AppUser(
    id: 'c1',
    name: 'Alice Silva',
    email: 'alice@exemplo.com',
    role: UserRole.client,
  );
}

AppointmentModel appointment({
  DateTime? startAt,
  AppointmentStatus status = AppointmentStatus.scheduled,
}) {
  final start = startAt ?? DateTime.now().add(const Duration(days: 2));
  return AppointmentModel(
    id: 'appt-1',
    clientId: 'c1',
    clientName: 'Alice Silva',
    serviceId: 's1',
    serviceName: 'Banho',
    startAt: start,
    endAt: start.add(const Duration(hours: 1)),
    status: status,
  );
}

CustomerPackageModel activePackage() {
  return CustomerPackageModel(
    id: 'cp1',
    clientId: 'c1',
    packageId: 'bp1',
    serviceId: 's1',
    packageName: 'Pacote Banho 5x',
    serviceName: 'Banho',
    totalCredits: 5,
    usedCredits: 1,
    purchaseDate: DateTime(2026, 7, 1),
    validUntil: DateTime.now().add(const Duration(days: 30)),
    status: CustomerPackageStatus.active,
  );
}

PaymentModel pendingPayment() {
  return PaymentModel(
    id: 'pay-1',
    clientId: 'c1',
    clientName: 'Alice Silva',
    type: PaymentType.package,
    amount: 150.0,
    method: PaymentMethod.pix,
    status: PaymentStatus.pending,
    paidAt: null,
    createdAt: DateTime(2026, 8, 1),
  );
}

void main() {
  late MockAuthRepository authRepository;
  late MockUserRepository userRepository;
  late MockNotificationService notificationService;
  late MockAppointmentRepository appointments;
  late MockPackageRepository packages;
  late MockPaymentRepository payments;

  setUp(() {
    authRepository = MockAuthRepository();
    userRepository = MockUserRepository();
    notificationService = MockNotificationService();
    appointments = MockAppointmentRepository();
    packages = MockPackageRepository();
    payments = MockPaymentRepository();
    when(
      () => authRepository.authStateChanges(),
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => appointments.customerAppointmentsStream('b1', any()),
    ).thenAnswer((_) => Stream.value(const []));
    when(
      () => packages.customerPackagesStream('b1', any()),
    ).thenAnswer((_) => Stream.value(const []));
    when(
      () => payments.customerPaymentsStream('b1', any()),
    ).thenAnswer((_) => Stream.value(const []));
  });

  Future<void> pumpHome(WidgetTester tester) async {
    final auth = AuthController(
      authRepository: authRepository,
      userRepository: userRepository,
      notificationService: notificationService,
    );
    addTearDown(auth.dispose);
    auth.profile = clientUser();
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
          Provider<AppointmentRepository>(create: (_) => appointments),
          Provider<PackageRepository>(create: (_) => packages),
          Provider<PaymentRepository>(create: (_) => payments),
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: businessContext),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: ClientHomeScreen(onOpenAgenda: null, onOpenPackages: null),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ClientHomeScreen', () {
    testWidgets('greets the client by first name', (tester) async {
      await pumpHome(tester);
      expect(find.text('Ola, Alice'), findsOneWidget);
    });

    testWidgets('shows the next appointment as a highlight', (tester) async {
      final next = appointment();
      when(
        () => appointments.customerAppointmentsStream('b1', 'c1'),
      ).thenAnswer((_) => Stream.value([next]));

      await pumpHome(tester);

      expect(find.text('Banho'), findsOneWidget);
      expect(
        find.text(
          '${formatDate(next.startAt)} as ${formatTime(next.startAt)}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows oriented empty states', (tester) async {
      await pumpHome(tester);

      expect(find.text('Nenhum agendamento marcado'), findsOneWidget);
      expect(find.text('Agendar agora'), findsOneWidget);
      expect(find.text('Sem pacotes ativos'), findsOneWidget);
    });

    testWidgets('shows the expiring package balance', (tester) async {
      when(
        () => packages.customerPackagesStream('b1', 'c1'),
      ).thenAnswer((_) => Stream.value([activePackage()]));

      await pumpHome(tester);

      final validText =
          'Valido ate ${formatDate(DateTime.now().add(const Duration(days: 30)))}';
      expect(find.text('Pacote Banho 5x'), findsOneWidget);
      expect(find.text('4 creditos'), findsOneWidget);
      expect(find.text(validText), findsOneWidget);
    });

    testWidgets('shows a pending payment banner', (tester) async {
      when(
        () => payments.customerPaymentsStream('b1', 'c1'),
      ).thenAnswer((_) => Stream.value([pendingPayment()]));

      await pumpHome(tester);

      expect(find.text('Pagamento pendente'), findsOneWidget);
      expect(find.textContaining('R\$ 150,00'), findsOneWidget);
    });

    testWidgets('hides the banner when there are no pending payments', (
      tester,
    ) async {
      final paid = PaymentModel(
        id: 'pay-2',
        clientId: 'c1',
        clientName: 'Alice Silva',
        type: PaymentType.package,
        amount: 150.0,
        method: PaymentMethod.pix,
        status: PaymentStatus.paid,
        paidAt: DateTime(2026, 7, 20),
      );
      when(
        () => payments.customerPaymentsStream('b1', 'c1'),
      ).thenAnswer((_) => Stream.value([paid]));

      await pumpHome(tester);

      expect(find.text('Pagamento pendente'), findsNothing);
    });

    testWidgets(
      'shows an error state instead of pretending the list is empty',
      (tester) async {
        when(() => appointments.customerAppointmentsStream('b1', 'c1')).thenAnswer(
          (_) => Stream<List<AppointmentModel>>.error(StateError('boom')),
        );

        await pumpHome(tester);

        expect(find.text('Nenhum agendamento marcado'), findsNothing);
        expect(
          find.text(
            'Nao foi possivel carregar seus agendamentos. '
            'Verifique sua conexao.',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
