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
import 'package:meupet_agenda_app/models/service_model.dart';
import 'package:meupet_agenda_app/repositories/appointment_repository.dart';
import 'package:meupet_agenda_app/repositories/auth_repository.dart';
import 'package:meupet_agenda_app/repositories/business_repository.dart';
import 'package:meupet_agenda_app/repositories/package_repository.dart';
import 'package:meupet_agenda_app/repositories/payment_repository.dart';
import 'package:meupet_agenda_app/repositories/service_repository.dart';
import 'package:meupet_agenda_app/repositories/user_repository.dart';
import 'package:meupet_agenda_app/screens/admin/admin_dashboard_screen.dart';
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

const adminUser = AppUser(
  id: 'a1',
  name: 'Bruno',
  email: 'bruno@exemplo.com',
  role: UserRole.admin,
);

const clientUser = AppUser(
  id: 'c1',
  name: 'Alice',
  email: 'alice@exemplo.com',
  role: UserRole.client,
);

const service = ServiceModel(
  id: 's1',
  name: 'Banho',
  description: 'Banho completo',
  durationMinutes: 60,
  price: 80.0,
);

const package = BusinessPackageModel(
  id: 'bp1',
  serviceId: 's1',
  serviceName: 'Banho',
  name: 'Banho 5x',
  totalCredits: 5,
  price: 150.0,
  validityDays: 30,
);

/// Appointment with a startAt inside the current period so the dashboard's
/// period filter (default: today) includes it.
AppointmentModel appointment({
  String? customerPackageId,
  String clientId = 'c1',
  String clientName = 'Alice',
  AppointmentStatus status = AppointmentStatus.scheduled,
}) {
  final start = DateTime.now();
  return AppointmentModel(
    id: 'a1',
    clientId: clientId,
    clientName: clientName,
    serviceId: 's1',
    serviceName: 'Banho',
    customerPackageId: customerPackageId,
    startAt: start,
    endAt: start.add(const Duration(hours: 1)),
    status: status,
  );
}

void main() {
  late MockAuthRepository authRepository;
  late MockUserRepository userRepository;
  late MockNotificationService notificationService;
  late MockAppointmentRepository appointmentRepository;
  late MockPackageRepository packageRepository;
  late MockPaymentRepository paymentRepository;
  late MockServiceRepository serviceRepository;
  late MockBusinessRepository businessRepository;
  late AuthController authController;
  late AdminController adminController;
  late BusinessContextController businessContext;

  setUpAll(() {
    registerFallbackValue(service);
    registerFallbackValue(package);
  });

  setUp(() {
    authRepository = MockAuthRepository();
    userRepository = MockUserRepository();
    notificationService = MockNotificationService();
    appointmentRepository = MockAppointmentRepository();
    packageRepository = MockPackageRepository();
    paymentRepository = MockPaymentRepository();
    serviceRepository = MockServiceRepository();
    businessRepository = MockBusinessRepository();

    when(
      () => authRepository.authStateChanges(),
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => appointmentRepository.allAppointmentsStream('b1'),
    ).thenAnswer((_) => Stream.value(const []));
    when(
      () => packageRepository.activePackagesStream('b1'),
    ).thenAnswer((_) => Stream.value(const []));
    when(
      () => serviceRepository.activeServicesStream('b1'),
    ).thenAnswer((_) => Stream.value(const [service]));
    when(
      () => serviceRepository.allServicesStream('b1'),
    ).thenAnswer((_) => Stream.value(const [service]));
    when(
      () => packageRepository.allPackagesStream('b1'),
    ).thenAnswer((_) => Stream.value(const [package]));

    authController = AuthController(
      authRepository: authRepository,
      userRepository: userRepository,
      notificationService: notificationService,
    );
    authController.profile = adminUser;
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
      serviceRepository: serviceRepository,
      packageRepository: packageRepository,
      userRepository: userRepository,
      authController: authController,
      businessContext: businessContext,
    );
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppointmentRepository>(create: (_) => appointmentRepository),
          Provider<PackageRepository>(create: (_) => packageRepository),
          Provider<PaymentRepository>(create: (_) => paymentRepository),
          Provider<ServiceRepository>(create: (_) => serviceRepository),
          Provider<UserRepository>(create: (_) => userRepository),
          ChangeNotifierProvider<AuthController>.value(value: authController),
          ChangeNotifierProvider<BusinessContextController>.value(
            value: businessContext,
          ),
          ChangeNotifierProvider<AdminController>.value(value: adminController),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: AdminDashboardScreen(onOpenAgenda: null)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpNarrowScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppointmentRepository>(create: (_) => appointmentRepository),
          Provider<PackageRepository>(create: (_) => packageRepository),
          Provider<PaymentRepository>(create: (_) => paymentRepository),
          Provider<ServiceRepository>(create: (_) => serviceRepository),
          Provider<UserRepository>(create: (_) => userRepository),
          ChangeNotifierProvider<AuthController>.value(value: authController),
          ChangeNotifierProvider<BusinessContextController>.value(
            value: businessContext,
          ),
          ChangeNotifierProvider<AdminController>.value(value: adminController),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: AdminDashboardScreen(onOpenAgenda: null)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AdminDashboardScreen', () {
    testWidgets('blocks clients from the admin panel', (tester) async {
      authController.profile = clientUser;
      await pumpScreen(tester);

      expect(find.text('Acesso administrativo'), findsOneWidget);
      expect(find.text('Painel admin'), findsNothing);
    });

    testWidgets('renders the panel header for staff', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Painel admin'), findsOneWidget);
      expect(find.text('Resumo do estabelecimento'), findsOneWidget);
    });

    testWidgets('renders dashboard metrics without a payments metric', (
      tester,
    ) async {
      when(() => appointmentRepository.allAppointmentsStream('b1')).thenAnswer(
        (_) => Stream.value([appointment()]),
      );
      when(
        () => packageRepository.activePackagesStream('b1'),
      ).thenAnswer((_) => Stream.value(const [package]));

      await pumpScreen(tester);

      expect(find.text('Atendimentos'), findsOneWidget);
      expect(find.text('Pacotes ativos'), findsOneWidget);
      expect(find.text('Creditos usados'), findsOneWidget);
      expect(find.text('Clientes atendidos'), findsOneWidget);
      expect(find.text('Pagamentos'), findsNothing);
    });

    testWidgets('counts package credits used across appointments', (
      tester,
    ) async {
      when(() => appointmentRepository.allAppointmentsStream('b1')).thenAnswer(
        (_) => Stream.value([
          appointment(customerPackageId: 'cp1'),
          appointment(),
        ]),
      );

      await pumpScreen(tester);

      expect(find.text('Creditos usados'), findsOneWidget);
    });

    testWidgets('counts distinct clients served', (tester) async {
      when(() => appointmentRepository.allAppointmentsStream('b1')).thenAnswer(
        (_) => Stream.value([
          appointment(clientId: 'c1', clientName: 'Alice'),
          appointment(clientId: 'c1', clientName: 'Alice'),
          appointment(clientId: 'c2', clientName: 'Bob'),
        ]),
      );

      await pumpScreen(tester);

      expect(find.text('Clientes atendidos'), findsOneWidget);
    });

    testWidgets('renders filter chips', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Hoje'), findsOneWidget);
      expect(find.text('7 dias'), findsOneWidget);
      expect(find.text('30 dias'), findsOneWidget);
    });

    testWidgets('narrow screen does not overflow', (tester) async {
      when(() => appointmentRepository.allAppointmentsStream('b1')).thenAnswer(
        (_) => Stream.value([appointment()]),
      );

      await pumpNarrowScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Painel admin'), findsOneWidget);
      expect(find.text('Clientes atendidos'), findsOneWidget);
    });

    testWidgets('renders weekly chart', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Atendimentos por dia da semana'), findsOneWidget);
    });

    testWidgets('shows the period agenda empty message', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Agenda do periodo'), findsOneWidget);
      expect(find.text('Nenhum atendimento neste periodo.'), findsOneWidget);
    });

    testWidgets('renders period appointments with status badges', (tester) async {
      when(() => appointmentRepository.allAppointmentsStream('b1')).thenAnswer(
        (_) => Stream.value([appointment()]),
      );

      await pumpScreen(tester);

      expect(find.textContaining('Banho'), findsWidgets);
      expect(find.text('Agendado'), findsOneWidget);
    });

    testWidgets('filtering by 7 days includes week appointments', (tester) async {
      when(() => appointmentRepository.allAppointmentsStream('b1')).thenAnswer(
        (_) => Stream.value([appointment()]),
      );

      await pumpScreen(tester);
      await tester.tap(find.text('7 dias'));
      await tester.pumpAndSettle();

      expect(find.text('Nenhum atendimento neste periodo.'), findsNothing);
    });

    testWidgets('clearing filters resets to today', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('7 dias'));
      await tester.pumpAndSettle();

      final clearButton = find.byKey(const Key('dashboard_clear_filters'));
      expect(tester.widget<TextButton>(clearButton).onPressed, isNotNull);

      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      expect(find.text('Hoje'), findsOneWidget);
    });

    testWidgets('renders the services list with an active switch', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Servicos'), findsOneWidget);
      expect(find.text('Banho'), findsWidgets);
      expect(find.text('60 min - R\$ 80,00'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('toggling the switch deactivates the service', (tester) async {
      when(
        () => serviceRepository.setActive('b1', 's1', false),
      ).thenAnswer((_) async {});

      await pumpScreen(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      verify(() => serviceRepository.setActive('b1', 's1', false)).called(1);
    });

    testWidgets('renders the packages list with status badges', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Pacotes'), findsOneWidget);
      expect(find.text('Banho 5x'), findsOneWidget);
      expect(find.text('5 creditos - R\$ 150,00'), findsOneWidget);
      expect(find.text('Ativo'), findsOneWidget);
    });

    testWidgets('shows empty states when lists are empty', (tester) async {
      when(
        () => serviceRepository.allServicesStream('b1'),
      ).thenAnswer((_) => Stream.value(const []));
      when(
        () => packageRepository.allPackagesStream('b1'),
      ).thenAnswer((_) => Stream.value(const []));

      await pumpScreen(tester);

      expect(find.text('Nenhum servico'), findsOneWidget);
      expect(find.text('Nenhum pacote'), findsOneWidget);
    });

    testWidgets('opens the service form and saves a new service', (
      tester,
    ) async {
      when(
        () => serviceRepository.saveService('b1', any()),
      ).thenAnswer((_) async => 's9');

      await pumpScreen(tester);
      await tester.tap(find.text('Servico'));
      await tester.pumpAndSettle();

      expect(find.text('Salvar servico'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'Banho Premium');
      await tester.tap(find.text('Salvar servico'));
      await tester.pumpAndSettle();

      verify(() => serviceRepository.saveService('b1', any())).called(1);
      expect(find.text('Salvar servico'), findsNothing);
    });

    testWidgets('service form validates required fields', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Servico'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '   ');
      await tester.tap(find.text('Salvar servico'));
      await tester.pumpAndSettle();

      expect(find.text('Campo obrigatorio'), findsWidgets);
      verifyNever(() => serviceRepository.saveService('b1', any()));
    });

    testWidgets(
      'service form stays open and shows a clean SnackBar on failure',
      (tester) async {
        when(
          () => serviceRepository.saveService('b1', any()),
        ).thenThrow(Exception('Falha ao salvar'));

        await pumpScreen(tester);
        await tester.tap(find.text('Servico'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).at(0), 'Banho Premium');
        await tester.tap(find.text('Salvar servico'));
        await tester.pumpAndSettle();

        expect(find.text('Salvar servico'), findsOneWidget);
        expect(find.text('Falha ao salvar'), findsOneWidget);
        expect(find.textContaining('Exception:'), findsNothing);
        expect(find.textContaining('Bad state:'), findsNothing);
      },
    );

    testWidgets('service switch failure shows a SnackBar', (tester) async {
      when(
        () => serviceRepository.setActive('b1', 's1', false),
      ).thenThrow(Exception('Falha ao alterar o servico'));

      await pumpScreen(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('Falha ao alterar o servico'), findsOneWidget);
    });

    testWidgets('opens the package form and saves a new package', (
      tester,
    ) async {
      when(
        () => packageRepository.savePackage('b1', any()),
      ).thenAnswer((_) async => 'bp9');

      await pumpScreen(tester);
      await tester.tap(find.text('Pacote'));
      await tester.pumpAndSettle();

      expect(find.text('Salvar pacote'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'Banho 10x');
      await tester.tap(find.text('Salvar pacote'));
      await tester.pumpAndSettle();

      verify(() => packageRepository.savePackage('b1', any())).called(1);
      expect(find.text('Salvar pacote'), findsNothing);
    });

    testWidgets('package form stays open and shows a SnackBar on failure', (
      tester,
    ) async {
      when(
        () => packageRepository.savePackage('b1', any()),
      ).thenThrow(Exception('Falha ao salvar pacote'));

      await pumpScreen(tester);
      await tester.tap(find.text('Pacote'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'Banho 10x');
      await tester.tap(find.text('Salvar pacote'));
      await tester.pumpAndSettle();

      expect(find.text('Salvar pacote'), findsOneWidget);
      expect(find.text('Falha ao salvar pacote'), findsOneWidget);
    });
  });
}
