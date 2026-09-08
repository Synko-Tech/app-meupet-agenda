import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/controllers/admin_controller.dart';
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
import 'package:meupet_agenda_app/repositories/service_repository.dart';
import 'package:meupet_agenda_app/repositories/user_repository.dart';
import 'package:meupet_agenda_app/screens/customers/customer_details_screen.dart';
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

class MockServiceRepository extends Mock implements ServiceRepository {}

const client = AppUser(
  id: 'c1',
  name: 'Alice',
  email: 'alice@exemplo.com',
  phone: '11999990001',
  role: UserRole.client,
  isActive: true,
  createdAt: null,
  updatedAt: null,
);

AppointmentModel appointment() {
  return AppointmentModel(
    id: 'a1',
    clientId: 'c1',
    clientName: 'Alice',
    serviceId: 's1',
    serviceName: 'Banho',
    startAt: DateTime(2026, 8, 1, 10, 0),
    endAt: DateTime(2026, 8, 1, 11, 0),
    status: AppointmentStatus.scheduled,
  );
}

CustomerPackageModel customerPackage() {
  return CustomerPackageModel(
    id: 'cp1',
    clientId: 'c1',
    packageId: 'bp1',
    serviceId: 's1',
    packageName: 'Banho 5x',
    serviceName: 'Banho',
    totalCredits: 5,
    usedCredits: 2,
    purchaseDate: DateTime(2026, 7, 1),
    validUntil: DateTime(2026, 10, 1),
    status: CustomerPackageStatus.active,
  );
}

PaymentModel payment() {
  return PaymentModel(
    id: 'pay1',
    clientId: 'c1',
    clientName: 'Alice',
    type: PaymentType.package,
    amount: 150.0,
    method: PaymentMethod.pix,
    status: PaymentStatus.paid,
    paidAt: DateTime(2026, 7, 1),
  );
}

void main() {
  late MockAuthRepository authRepository;
  late MockUserRepository userRepository;
  late MockNotificationService notificationService;
  late MockAppointmentRepository appointmentRepository;
  late MockPackageRepository packageRepository;
  late MockPaymentRepository paymentRepository;
  late MockBusinessRepository businessRepository;
  late AuthController authController;
  late AdminController adminController;
  late BusinessContextController businessContext;

  setUp(() {
    authRepository = MockAuthRepository();
    userRepository = MockUserRepository();
    notificationService = MockNotificationService();
    appointmentRepository = MockAppointmentRepository();
    packageRepository = MockPackageRepository();
    paymentRepository = MockPaymentRepository();
    businessRepository = MockBusinessRepository();

    when(
      () => authRepository.authStateChanges(),
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => userRepository.profileStream('c1'),
    ).thenAnswer((_) => Stream.value(client));
    when(
      () => appointmentRepository.customerAppointmentsStream('b1', 'c1'),
    ).thenAnswer((_) => Stream.value([appointment()]));
    when(
      () => packageRepository.customerPackagesStream('b1', 'c1'),
    ).thenAnswer((_) => Stream.value([customerPackage()]));
    when(
      () => paymentRepository.customerPaymentsStream('b1', 'c1'),
    ).thenAnswer((_) => Stream.value([payment()]));
    when(
      () => userRepository.setUserActive(userId: 'c1', isActive: false),
    ).thenAnswer((_) async {});

    authController = AuthController(
      authRepository: authRepository,
      userRepository: userRepository,
      notificationService: notificationService,
    );
    authController.profile = const AppUser(
      id: 'a1',
      name: 'Admin',
      email: 'admin@exemplo.com',
      role: UserRole.admin,
    );
    authController.isLoading = false;

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
    businessContext = BusinessContextController(
      repository: businessRepository,
      authController: authController,
    );
    businessContext.selectBusiness('b1');
    addTearDown(businessContext.dispose);

    adminController = AdminController(
      serviceRepository: MockServiceRepository(),
      packageRepository: packageRepository,
      userRepository: userRepository,
      authController: authController,
      businessContext: businessContext,
    );
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<UserRepository>(create: (_) => userRepository),
          Provider<AppointmentRepository>(create: (_) => appointmentRepository),
          Provider<PackageRepository>(create: (_) => packageRepository),
          Provider<PaymentRepository>(create: (_) => paymentRepository),
          ChangeNotifierProvider<AuthController>.value(value: authController),
          ChangeNotifierProvider<BusinessContextController>.value(
            value: businessContext,
          ),
          ChangeNotifierProvider<AdminController>.value(value: adminController),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const CustomerDetailsScreen(clientId: 'c1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('CustomerDetailsScreen', () {
    testWidgets('renders profile fields', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Alice'), findsNWidgets(2));
      expect(find.text('alice@exemplo.com'), findsNWidgets(2));
      expect(find.text('11999990001'), findsOneWidget);
      expect(find.text('Ativo'), findsNWidgets(3));
    });

    testWidgets('renders appointment history', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Agendamentos'), findsOneWidget);
      expect(find.text('Banho'), findsWidgets);
      expect(
        find.text('01/08/2026 10:00'),
        findsOneWidget,
      );
      expect(find.text('Agendado'), findsOneWidget);
    });

    testWidgets('renders package history with credits', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Pacotes'), findsOneWidget);
      expect(find.text('Banho 5x'), findsOneWidget);
      expect(find.textContaining('2/5 creditos'), findsOneWidget);
      expect(find.textContaining('Validade'), findsOneWidget);
    });

    testWidgets('renders payment history', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Pagamentos'), findsOneWidget);
      expect(find.text('Pacote de servicos - R\$ 150,00'), findsOneWidget);
      expect(find.text('Pago'), findsOneWidget);
    });

    testWidgets('shows empty states for each history section', (tester) async {
      when(
        () => appointmentRepository.customerAppointmentsStream('b1', 'c1'),
      ).thenAnswer((_) => Stream.value(const []));
      when(
        () => packageRepository.customerPackagesStream('b1', 'c1'),
      ).thenAnswer((_) => Stream.value(const []));
      when(
        () => paymentRepository.customerPaymentsStream('b1', 'c1'),
      ).thenAnswer((_) => Stream.value(const []));

      await pumpScreen(tester);

      expect(find.text('Sem agendamentos'), findsOneWidget);
      expect(find.text('Sem pacotes'), findsOneWidget);
      expect(find.text('Sem pagamentos'), findsOneWidget);
    });

    testWidgets('inactive client shows Inativo badge and Activar action', (
      tester,
    ) async {
      when(() => userRepository.profileStream('c1')).thenAnswer(
        (_) => Stream.value(
          const AppUser(
            id: 'c1',
            name: 'Alice',
            email: 'alice@exemplo.com',
            role: UserRole.client,
            isActive: false,
          ),
        ),
      );

      await pumpScreen(tester);

      expect(find.text('Inativo'), findsNWidgets(2));
      expect(find.text('Ativar cliente'), findsOneWidget);
    });

    testWidgets('deactivating requires confirmation and persists', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.ensureVisible(find.text('Inativar cliente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inativar cliente'));
      await tester.pumpAndSettle();

      expect(find.text('Inativar'), findsWidgets);

      await tester.tap(find.text('Inativar').last);
      await tester.pumpAndSettle();

      verify(
        () => userRepository.setUserActive(userId: 'c1', isActive: false),
      ).called(1);
      expect(find.text('Cliente inativado com sucesso.'), findsOneWidget);
    });

    testWidgets('canceling the confirmation keeps the client untouched', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.ensureVisible(find.text('Inativar cliente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inativar cliente'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(
        () => userRepository.setUserActive(userId: 'c1', isActive: false),
      );
    });

    testWidgets('responsive: no overflow at 320 width', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpScreen(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
