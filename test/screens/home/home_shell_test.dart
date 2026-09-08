import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/controllers/admin_controller.dart';
import 'package:meupet_agenda_app/controllers/appointment_controller.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/controllers/business_context_controller.dart';
import 'package:meupet_agenda_app/controllers/package_controller.dart';
import 'package:meupet_agenda_app/models/app_user.dart';
import 'package:meupet_agenda_app/models/business_membership.dart';
import 'package:meupet_agenda_app/repositories/appointment_repository.dart';
import 'package:meupet_agenda_app/repositories/auth_repository.dart';
import 'package:meupet_agenda_app/repositories/business_repository.dart';
import 'package:meupet_agenda_app/repositories/notification_repository.dart';
import 'package:meupet_agenda_app/repositories/package_repository.dart';
import 'package:meupet_agenda_app/repositories/payment_repository.dart';
import 'package:meupet_agenda_app/repositories/service_repository.dart';
import 'package:meupet_agenda_app/repositories/user_repository.dart';
import 'package:meupet_agenda_app/screens/home/home_shell.dart';
import 'package:meupet_agenda_app/services/notification_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockUserRepository extends Mock implements UserRepository {}

class MockNotificationService extends Mock implements NotificationService {}

class MockAppointmentRepository extends Mock implements AppointmentRepository {}

class MockPackageRepository extends Mock implements PackageRepository {}

class MockPaymentRepository extends Mock implements PaymentRepository {}

class MockServiceRepository extends Mock implements ServiceRepository {}

class MockNotificationRepository extends Mock
    implements NotificationRepository {}

class MockBusinessRepository extends Mock implements BusinessRepository {}

AppUser userWithRole(UserRole role) {
  return AppUser(
    id: 'u-${role.name}',
    name: 'Usuario',
    email: 'usuario@exemplo.com',
    role: role,
  );
}

/// Stubs every stream the shell screens subscribe to, with empty data. With
/// empty catalogs the screens render their empty states, which is enough to
/// exercise navigation.
void stubEmptyStreams(
  MockServiceRepository services,
  MockPackageRepository packages,
  MockAppointmentRepository appointments,
  MockPaymentRepository payments,
  MockUserRepository users,
) {
  when(
    () => services.activeServicesStream('b1'),
  ).thenAnswer((_) => Stream.value(const []));
  when(
    () => services.allServicesStream('b1'),
  ).thenAnswer((_) => Stream.value(const []));
  when(
    () => packages.customerPackagesStream('b1', any()),
  ).thenAnswer((_) => Stream.value(const []));
  when(
    () => packages.activePackagesStream('b1'),
  ).thenAnswer((_) => Stream.value(const []));
  when(
    () => packages.allPackagesStream('b1'),
  ).thenAnswer((_) => Stream.value(const []));
  when(
    () => packages.activeCustomerPackagesForServiceStream(
      businessId: 'b1',
      clientId: any(named: 'clientId'),
      serviceId: any(named: 'serviceId'),
    ),
  ).thenAnswer((_) => Stream.value(const []));
  when(
    () => appointments.todayAppointmentsStream('b1'),
  ).thenAnswer((_) => Stream.value(const []));
  when(
    () => appointments.appointmentsForDayStream('b1', any()),
  ).thenAnswer((_) => Stream.value(const []));
  when(
    () => appointments.allAppointmentsStream('b1'),
  ).thenAnswer((_) => Stream.value(const []));
  when(
    () => appointments.customerAppointmentsStream('b1', any()),
  ).thenAnswer((_) => Stream.value(const []));
  when(
    () => payments.allPaymentsStream('b1'),
  ).thenAnswer((_) => Stream.value(const []));
  when(
    () => payments.customerPaymentsStream('b1', any()),
  ).thenAnswer((_) => Stream.value(const []));
  when(
    () => users.allClientsStream(),
  ).thenAnswer((_) => Stream.value(const []));
  when(() => users.allUsersStream()).thenAnswer((_) => Stream.value(const []));
  when(() => users.staffStream()).thenAnswer((_) => Stream.value(const []));
  when(() => users.profileStream(any())).thenAnswer((_) => Stream.value(null));
}

/// Pumps [HomeShell] with the given repositories and [auth]. Exposed as a
/// helper so tests can control exactly which streams are stubbed.
Future<void> pumpShellWidget(
  WidgetTester tester, {
  required AuthController auth,
  required MockServiceRepository services,
  required MockPackageRepository packages,
  required MockAppointmentRepository appointments,
  required MockPaymentRepository payments,
  required MockUserRepository userRepository,
  double width = 360,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

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
        Provider<ServiceRepository>(create: (_) => services),
        Provider<PackageRepository>(create: (_) => packages),
        Provider<AppointmentRepository>(create: (_) => appointments),
        Provider<PaymentRepository>(create: (_) => payments),
        Provider<UserRepository>(create: (_) => userRepository),
        Provider<NotificationRepository>(
          create: (_) => MockNotificationRepository(),
        ),
        Provider<BusinessRepository>(create: (_) => MockBusinessRepository()),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: businessContext),
        ChangeNotifierProvider(
          create: (_) => AppointmentController(
            repository: appointments,
            businessContext: businessContext,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => PackageController(
            packageRepository: packages,
            businessContext: businessContext,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => AdminController(
            serviceRepository: services,
            packageRepository: packages,
            userRepository: userRepository,
            authController: auth,
            businessContext: businessContext,
          ),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const HomeShell()),
    ),
  );
  await tester.pump();
}

void main() {
  late MockAuthRepository authRepository;
  late MockUserRepository userRepository;
  late MockNotificationService notificationService;

  setUp(() {
    authRepository = MockAuthRepository();
    userRepository = MockUserRepository();
    notificationService = MockNotificationService();
    when(
      () => authRepository.authStateChanges(),
    ).thenAnswer((_) => const Stream.empty());
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    UserRole role = UserRole.client,
    double width = 360,
  }) async {
    final auth = AuthController(
      authRepository: authRepository,
      userRepository: userRepository,
      notificationService: notificationService,
    );
    addTearDown(auth.dispose);
    auth.profile = userWithRole(role);
    auth.isLoading = false;

    final services = MockServiceRepository();
    final packages = MockPackageRepository();
    final appointments = MockAppointmentRepository();
    final payments = MockPaymentRepository();
    stubEmptyStreams(
      services,
      packages,
      appointments,
      payments,
      userRepository,
    );

    await pumpShellWidget(
      tester,
      auth: auth,
      services: services,
      packages: packages,
      appointments: appointments,
      payments: payments,
      userRepository: userRepository,
      width: width,
    );
  }

  List<String> navLabels(WidgetTester tester) {
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    return bar.destinations
        .map((d) => (d as NavigationDestination).label)
        .toList();
  }

  group('HomeShell navigation', () {
    testWidgets('client sees the four focused destinations', (tester) async {
      await pumpShell(tester, role: UserRole.client);
      expect(navLabels(tester), ['Inicio', 'Agendar', 'Pacotes', 'Conta']);
    });

    testWidgets('collaborator keeps payments and panel destinations', (
      tester,
    ) async {
      await pumpShell(tester, role: UserRole.collaborator);
      expect(navLabels(tester), [
        'Inicio',
        'Agendar',
        'Pacotes',
        'Pagamento',
        'Painel',
        'Conta',
      ]);
    });

    testWidgets('admin sees the independent Clientes tab', (tester) async {
      await pumpShell(tester, role: UserRole.admin);
      expect(navLabels(tester), [
        'Inicio',
        'Agendar',
        'Pacotes',
        'Pagamento',
        'Painel',
        'Clientes',
        'Conta',
      ]);
    });

    testWidgets('admin can open the Clientes tab', (tester) async {
      await pumpShell(tester, role: UserRole.admin);

      await tester.tap(find.text('Clientes').last);
      await tester.pump();

      expect(find.text('Clientes'), findsWidgets);
      final title = tester.widget<Text>(
        find.byKey(const ValueKey('home-topbar-title')),
      );
      expect(title.data, 'Clientes');
    });

    testWidgets('admin shell with seven tabs does not overflow at 320 width', (
      tester,
    ) async {
      await pumpShell(tester, role: UserRole.admin, width: 320);

      expect(tester.takeException(), isNull);
      expect(find.text('Clientes'), findsOneWidget);
    });

    testWidgets('super admin renders the admin shell', (tester) async {
      // The legacy dashboard metric grid overflows on narrow widths (fixed in
      // Wave C); test the admin shell at tablet width.
      await pumpShell(tester, role: UserRole.superAdmin, width: 900);
      expect(
        navLabels(tester),
        containsAll([
          'Dashboard',
          'Agenda',
          'Calendario',
          'Pagamento',
          'Clientes',
          'Perfil',
        ]),
      );
      expect(find.byTooltip('Menu administrativo'), findsOneWidget);
    });

    testWidgets('tapping a destination updates selection and top bar title', (
      tester,
    ) async {
      await pumpShell(tester, role: UserRole.client);

      await tester.tap(find.text('Agendar').last);
      await tester.pump();

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 1);

      final title = tester.widget<Text>(
        find.byKey(const ValueKey('home-topbar-title')),
      );
      expect(title.data, 'Agendar');
    });

    testWidgets('client shell has no logout or admin menu in the top bar', (
      tester,
    ) async {
      await pumpShell(tester, role: UserRole.client);
      expect(find.byTooltip('Sair'), findsNothing);
      expect(find.byTooltip('Menu administrativo'), findsNothing);
    });

    testWidgets('destinations are built on demand and subscribe lazily', (
      tester,
    ) async {
      final auth = AuthController(
        authRepository: authRepository,
        userRepository: userRepository,
        notificationService: notificationService,
      );
      addTearDown(auth.dispose);
      auth.profile = userWithRole(UserRole.client);
      auth.isLoading = false;

      final services = MockServiceRepository();
      var servicesListens = 0;
      when(() => services.activeServicesStream('b1')).thenAnswer((_) {
        servicesListens++;
        return Stream.value(const []);
      });
      final packages = MockPackageRepository();
      when(
        () => packages.customerPackagesStream('b1', any()),
      ).thenAnswer((_) => Stream.value(const []));
      final appointments = MockAppointmentRepository();
      when(
        () => appointments.customerAppointmentsStream('b1', any()),
      ).thenAnswer((_) => Stream.value(const []));
      when(
        () => appointments.appointmentsForDayStream('b1', any()),
      ).thenAnswer((_) => Stream.value(const []));
      final payments = MockPaymentRepository();
      when(
        () => payments.customerPaymentsStream('b1', any()),
      ).thenAnswer((_) => Stream.value(const []));

      await pumpShellWidget(
        tester,
        auth: auth,
        services: services,
        packages: packages,
        appointments: appointments,
        payments: payments,
        userRepository: userRepository,
      );

      expect(
        servicesListens,
        0,
        reason: 'Agendar stream must not be subscribed before first visit',
      );

      await tester.tap(find.text('Agendar').last);
      await tester.pump();

      expect(
        servicesListens,
        1,
        reason: 'Agendar stream subscribes only when the tab is visited',
      );
    });
  });
}
