import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/controllers/appointment_controller.dart';
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
import 'package:meupet_agenda_app/repositories/service_repository.dart';
import 'package:meupet_agenda_app/repositories/user_repository.dart';
import 'package:meupet_agenda_app/screens/appointments/appointment_screen.dart';
import 'package:meupet_agenda_app/services/notification_service.dart';
import 'package:meupet_agenda_app/widgets/app_button.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockUserRepository extends Mock implements UserRepository {}

class MockNotificationService extends Mock implements NotificationService {}

class MockServiceRepository extends Mock implements ServiceRepository {}

class MockAppointmentRepository extends Mock implements AppointmentRepository {}

class MockPackageRepository extends Mock implements PackageRepository {}

class MockBusinessRepository extends Mock implements BusinessRepository {}

class MockBusinessContextController extends Mock
    implements BusinessContextController {}

class _FakeCustomerPackage extends Fake implements CustomerPackageModel {}

const clientUser = AppUser(
  id: 'c1',
  name: 'Alice',
  email: 'alice@exemplo.com',
  role: UserRole.client,
);

const adminUser = AppUser(
  id: 'a1',
  name: 'Admin',
  email: 'admin@exemplo.com',
  role: UserRole.admin,
);

const collaboratorUser = AppUser(
  id: 'cl1',
  name: 'Carlos',
  email: 'carlos@exemplo.com',
  role: UserRole.collaborator,
);

const service = ServiceModel(
  id: 's1',
  name: 'Banho',
  description: 'Banho completo',
  durationMinutes: 60,
  price: 80.0,
);

const otherService = ServiceModel(
  id: 's2',
  name: 'Consulta',
  description: 'Consulta veterinaria',
  durationMinutes: 30,
  price: 100.0,
);

/// A weekday (Mon-Fri) strictly in the future, regardless of the run day.
DateTime futureWeekday() {
  final today = DateTime.now();
  final start = DateTime(
    today.year,
    today.month,
    today.day,
  ).add(const Duration(days: 1));
  for (var i = 0; i < 7; i++) {
    final candidate = start.add(Duration(days: i));
    if (candidate.weekday >= DateTime.monday &&
        candidate.weekday <= DateTime.friday) {
      return candidate;
    }
  }
  return start;
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

CustomerPackageModel expiredActivePackage() {
  return CustomerPackageModel(
    id: 'cp-expired',
    clientId: 'c1',
    packageId: 'bp1',
    serviceId: 's1',
    packageName: 'Pacote Banho 5x',
    serviceName: 'Banho',
    totalCredits: 5,
    usedCredits: 1,
    purchaseDate: DateTime(2026, 7, 1),
    // Ainda marcado ATIVO, mas vencido: nunca pode ser usado.
    validUntil: DateTime.now().subtract(const Duration(days: 1)),
    status: CustomerPackageStatus.active,
  );
}

void main() {
  late MockAuthRepository authRepository;
  late MockUserRepository userRepository;
  late MockNotificationService notificationService;
  late MockServiceRepository serviceRepository;
  late MockAppointmentRepository appointmentRepository;
  late MockPackageRepository packageRepository;
  late MockBusinessContextController businessContext;
  late AuthController authController;
  late AppointmentController appointmentController;

  setUpAll(() {
    registerFallbackValue(service);
    registerFallbackValue(DateTime(2026));
    registerFallbackValue(_FakeCustomerPackage());
  });

  setUp(() {
    authRepository = MockAuthRepository();
    userRepository = MockUserRepository();
    notificationService = MockNotificationService();
    serviceRepository = MockServiceRepository();
    appointmentRepository = MockAppointmentRepository();
    packageRepository = MockPackageRepository();
    businessContext = MockBusinessContextController();
    when(() => businessContext.activeBusinessId).thenReturn('b1');

    when(
      () => authRepository.authStateChanges(),
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => serviceRepository.activeServicesStream('b1'),
    ).thenAnswer((_) => Stream.value(const [service]));
    when(
      () => appointmentRepository.appointmentsForDayStream('b1', any()),
    ).thenAnswer((_) => Stream.value(const []));
    when(
      () => packageRepository.activeCustomerPackagesForServiceStream(businessId: 'b1',
        clientId: any(named: 'clientId'),
        serviceId: any(named: 'serviceId'),
      ),
    ).thenAnswer((_) => Stream.value(const []));

    authController = AuthController(
      authRepository: authRepository,
      userRepository: userRepository,
      notificationService: notificationService,
    );
    authController.profile = clientUser;
    authController.isLoading = false;

    appointmentController = AppointmentController(
      repository: appointmentRepository,
      businessContext: businessContext,
    );
    appointmentController.selectDate(futureWeekday());
  });

  Future<void> pumpScreen(WidgetTester tester, {bool settle = true}) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ServiceRepository>(create: (_) => serviceRepository),
          Provider<AppointmentRepository>(create: (_) => appointmentRepository),
          Provider<PackageRepository>(create: (_) => packageRepository),
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
                authController: authController,
              );
              ctx.selectBusiness('b1');
              return ctx;
            },
          ),
          ChangeNotifierProvider<AuthController>.value(value: authController),
          ChangeNotifierProvider<AppointmentController>.value(
            value: appointmentController,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AppointmentScreen()),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
  }

  Future<void> goNext(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('appointment_continue_button')));
    await tester.pumpAndSettle();
  }

  Future<void> goBack(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('appointment_back_button')));
    await tester.pumpAndSettle();
  }

  Future<void> goToSchedule(WidgetTester tester) async {
    await goNext(tester); // servico -> data e horario
  }

  Future<void> goToReview(WidgetTester tester) async {
    await goToSchedule(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '09:00'));
    await tester.pump();
    await goNext(tester); // data e horario -> revisao
  }

  group('AppointmentScreen', () {
    testWidgets('shows a loading spinner while services load', (tester) async {
      final servicesController = StreamController<List<ServiceModel>>();
      addTearDown(servicesController.close);
      when(
        () => serviceRepository.activeServicesStream('b1'),
      ).thenAnswer((_) => servicesController.stream);

      await pumpScreen(tester, settle: false);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('shows an error state when services fail to load', (
      tester,
    ) async {
      when(
        () => serviceRepository.activeServicesStream('b1'),
      ).thenAnswer((_) => Stream.error(Exception('falha')));

      await pumpScreen(tester);

      expect(
        find.text('Nao foi possivel carregar os servicos'),
        findsOneWidget,
      );
    });

    testWidgets('shows an empty state when no services are registered', (
      tester,
    ) async {
      when(
        () => serviceRepository.activeServicesStream('b1'),
      ).thenAnswer((_) => Stream.value(const []));

      await pumpScreen(tester);

      expect(find.text('Nenhum servico cadastrado'), findsOneWidget);
    });

    testWidgets('renders header, step indicator and service cards', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Agendar atendimento'), findsOneWidget);
      expect(
        find.text('Escolha servico, data e horario'),
        findsOneWidget,
      );
      expect(find.text('Servico'), findsWidgets);
      expect(find.text('Data e horario'), findsWidgets);
      expect(find.text('Revisao'), findsWidgets);
      expect(find.text('Banho'), findsOneWidget);
      expect(find.text('60 min'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('appointment_service_card_s1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('appointment_continue_button')),
        findsOneWidget,
      );
    });

    testWidgets('tapping a service card selects it and advances', (
      tester,
    ) async {
      when(
        () => serviceRepository.activeServicesStream('b1'),
      ).thenAnswer((_) => Stream.value(const [service, otherService]));

      await pumpScreen(tester);
      await tester.tap(
        find.byKey(const ValueKey('appointment_service_card_s2')),
      );
      await tester.pumpAndSettle();
      await goNext(tester);

      expect(find.text('Data'), findsWidgets);
    });

    testWidgets('admin does not see the business hours reminder card', (
      tester,
    ) async {
      authController.profile = adminUser;

      await pumpScreen(tester);
      await goToSchedule(tester);

      expect(find.text('Horario de funcionamento'), findsNothing);
    });

    testWidgets('collaborator sees the business hours reminder card', (
      tester,
    ) async {
      authController.profile = collaboratorUser;

      await pumpScreen(tester);
      await goToSchedule(tester);

      expect(find.text('Horario de funcionamento'), findsOneWidget);
    });

    testWidgets('client sees the business hours reminder card', (tester) async {
      await pumpScreen(tester);
      await goToSchedule(tester);

      expect(find.text('Horario de funcionamento'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(5));
    });

    testWidgets('shows the active package card when one matches the service', (
      tester,
    ) async {
      when(
        () => packageRepository.activeCustomerPackagesForServiceStream(businessId: 'b1',
          clientId: any(named: 'clientId'),
          serviceId: any(named: 'serviceId'),
        ),
      ).thenAnswer((_) => Stream.value([activePackage()]));

      await pumpScreen(tester);
      await goToReview(tester);

      expect(find.text('Pacote ativo encontrado'), findsOneWidget);
      expect(find.text('4 creditos disponiveis'), findsOneWidget);
      expect(find.text('Sem pacote ativo para este servico'), findsNothing);
    });

    testWidgets('shows the no-package empty state in the review step', (
      tester,
    ) async {
      await pumpScreen(tester);
      await goToReview(tester);

      expect(find.text('Sem pacote ativo para este servico'), findsOneWidget);
    });

    testWidgets('never offers an expired package even when still ATIVO', (
      tester,
    ) async {
      when(
        () => packageRepository.activeCustomerPackagesForServiceStream(businessId: 'b1',
          clientId: any(named: 'clientId'),
          serviceId: any(named: 'serviceId'),
        ),
      ).thenAnswer((_) => Stream.value([expiredActivePackage()]));

      await pumpScreen(tester);
      await goToReview(tester);

      expect(find.text('Sem pacote ativo para este servico'), findsOneWidget);
      expect(find.text('Pacote ativo encontrado'), findsNothing);
    });

    testWidgets('disables slots outside business hours', (tester) async {
      await pumpScreen(tester);
      await goToSchedule(tester);

      final afternoonButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '15:00'),
      );
      final eveningButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '16:30'),
      );
      expect(afternoonButton.onPressed, isNotNull);
      expect(eveningButton.onPressed, isNull);
    });

    testWidgets('marks slots as disabled when they are already occupied', (
      tester,
    ) async {
      final date = futureWeekday();
      final occupied = AppointmentModel(
        id: 'a1',
        clientId: 'c1',
        clientName: 'Outro',
        serviceId: 's1',
        serviceName: 'Banho',
        startAt: DateTime(date.year, date.month, date.day, 9, 0),
        endAt: DateTime(date.year, date.month, date.day, 10, 0),
        status: AppointmentStatus.scheduled,
      );
      when(
        () => appointmentRepository.appointmentsForDayStream('b1', any()),
      ).thenAnswer((_) => Stream.value([occupied]));

      await pumpScreen(tester);
      await goToSchedule(tester);

      final nineButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '09:00'),
      );
      final twoButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '14:00'),
      );
      expect(nineButton.onPressed, isNull);
      expect(twoButton.onPressed, isNotNull);
    });

    testWidgets('selecting a time stores it in the controller', (tester) async {
      await pumpScreen(tester);
      await goToSchedule(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, '14:00'));
      await tester.pump();

      expect(appointmentController.selectedTime, '14:00');
    });

    testWidgets('continue is disabled until a time is picked', (tester) async {
      await pumpScreen(tester);
      await goToSchedule(tester);

      var button = tester.widget<AppButton>(
        find.byKey(const Key('appointment_continue_button')),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.widgetWithText(OutlinedButton, '14:00'));
      await tester.pump();

      button = tester.widget<AppButton>(
        find.byKey(const Key('appointment_continue_button')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('clears the picked time when going back and changing the '
        'service', (tester) async {
      when(
        () => serviceRepository.activeServicesStream('b1'),
      ).thenAnswer((_) => Stream.value(const [service, otherService]));

      await pumpScreen(tester);
      await goToSchedule(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, '14:00'));
      await tester.pump();

      await goBack(tester); // volta para servicos
      await tester.tap(
        find.byKey(const ValueKey('appointment_service_card_s2')),
      );
      await tester.pumpAndSettle();
      await goNext(tester); // para data e horario

      var button = tester.widget<AppButton>(
        find.byKey(const Key('appointment_continue_button')),
      );
      expect(
        button.onPressed,
        isNull,
        reason: 'novo servico deve limpar o horario escolhido',
      );
    });

    testWidgets('shows the review summary before confirming', (tester) async {
      await pumpScreen(tester);
      await goToReview(tester);

      expect(find.text('Revisao'), findsWidgets);
      expect(find.textContaining('Banho'), findsWidgets);
      expect(find.text('Horario'), findsWidgets);
      expect(
        find.byKey(const Key('appointment_confirm_button')),
        findsOneWidget,
      );
    });

    testWidgets('confirms an appointment and shows a success snackbar', (
      tester,
    ) async {
      when(
        () => appointmentRepository.createAppointment(
          businessId: 'b1',
          service: any(named: 'service'),
          startAt: any(named: 'startAt'),
          customerPackage: any(named: 'customerPackage'),
        ),
      ).thenAnswer((_) async => 'appt-1');

      await pumpScreen(tester);
      await goToReview(tester);
      await tester.tap(find.byKey(const Key('appointment_confirm_button')));
      await tester.pumpAndSettle();

      verify(
        () => appointmentRepository.createAppointment(
          businessId: 'b1',
          service: service,
          startAt: any(named: 'startAt'),
          customerPackage: null,
        ),
      ).called(1);
      expect(find.text('Agendamento confirmado.'), findsOneWidget);
    });

    testWidgets('shows an inline error in the review step when confirmation '
        'fails', (tester) async {
      when(
        () => appointmentRepository.createAppointment(
          businessId: 'b1',
          service: any(named: 'service'),
          startAt: any(named: 'startAt'),
          customerPackage: any(named: 'customerPackage'),
        ),
      ).thenThrow(StateError('Horario ja reservado.'));

      await pumpScreen(tester);
      await goToReview(tester);
      await tester.tap(find.byKey(const Key('appointment_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.text('Horario ja reservado.'), findsOneWidget);
    });
  });
}
