import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/controllers/business_context_controller.dart';
import 'package:meupet_agenda_app/models/app_user.dart';
import 'package:meupet_agenda_app/models/appointment_model.dart';
import 'package:meupet_agenda_app/models/business_membership.dart';
import 'package:meupet_agenda_app/models/service_model.dart';
import 'package:meupet_agenda_app/repositories/appointment_repository.dart';
import 'package:meupet_agenda_app/repositories/auth_repository.dart';
import 'package:meupet_agenda_app/repositories/business_repository.dart';
import 'package:meupet_agenda_app/repositories/service_repository.dart';
import 'package:meupet_agenda_app/repositories/user_repository.dart';
import 'package:meupet_agenda_app/screens/calendar/admin_calendar_screen.dart';
import 'package:meupet_agenda_app/services/notification_service.dart';
import 'package:meupet_agenda_app/widgets/app_skeleton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockBusinessRepository extends Mock implements BusinessRepository {}

class MockUserRepository extends Mock implements UserRepository {}

class MockNotificationService extends Mock implements NotificationService {}

class MockAppointmentRepository extends Mock implements AppointmentRepository {}

class MockServiceRepository extends Mock implements ServiceRepository {}

const superAdmin = AppUser(
  id: 'sa1',
  name: 'Super',
  email: 'super@exemplo.com',
  role: UserRole.superAdmin,
);

const admin = AppUser(
  id: 'a1',
  name: 'Admin',
  email: 'admin@exemplo.com',
  role: UserRole.admin,
);

const service = ServiceModel(
  id: 's1',
  name: 'Banho',
  description: 'Banho completo',
  durationMinutes: 60,
  price: 80.0,
);

AppointmentModel appointment({
  String clientName = 'Alice Silva',
  String serviceId = 's1',
  AppointmentStatus status = AppointmentStatus.scheduled,
}) {
  return AppointmentModel(
    id: 'a1',
    clientId: 'c1',
    clientName: clientName,
    serviceId: serviceId,
    serviceName: 'Banho',
    startAt: DateTime(2026, 8, 1, 10, 0),
    endAt: DateTime(2026, 8, 1, 11, 0),
    status: status,
  );
}

void main() {
  late MockAuthRepository authRepository;
  late MockUserRepository userRepository;
  late MockNotificationService notificationService;
  late MockAppointmentRepository appointmentRepository;
  late MockServiceRepository serviceRepository;
  late AuthController authController;

  setUp(() {
    authRepository = MockAuthRepository();
    userRepository = MockUserRepository();
    notificationService = MockNotificationService();
    appointmentRepository = MockAppointmentRepository();
    serviceRepository = MockServiceRepository();

    when(
      () => authRepository.authStateChanges(),
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => appointmentRepository.appointmentsForDayStream('b1', any()),
    ).thenAnswer((_) => Stream.value(const []));
    when(
      () => serviceRepository.allServicesStream('b1'),
    ).thenAnswer((_) => Stream.value(const [service]));

    authController = AuthController(
      authRepository: authRepository,
      userRepository: userRepository,
      notificationService: notificationService,
    );
    authController.profile = superAdmin;
    authController.isLoading = false;
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(1200, 2400),
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppointmentRepository>(create: (_) => appointmentRepository),
          Provider<ServiceRepository>(create: (_) => serviceRepository),
          ChangeNotifierProvider<AuthController>.value(value: authController),
          ChangeNotifierProvider(
            create: (_) {
              final repository = MockBusinessRepository();
              when(() => repository.myMembershipsStream(any())).thenAnswer(
                (_) => Stream.value(const [
                  BusinessMembership(
                    userId: 'u1',
                    businessId: 'b1',
                    businessName: 'Loja Teste',
                    role: BusinessRole.owner,
                  ),
                ]),
              );
              final context = BusinessContextController(
                repository: repository,
                authController: authController,
              );
              context.selectBusiness('b1');
              return context;
            },
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AdminCalendarScreen()),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
  }

  group('AdminCalendarScreen', () {
    testWidgets('blocks non-super-admin roles', (tester) async {
      authController.profile = admin;
      await pumpScreen(tester);

      expect(find.text('Calendario restrito'), findsOneWidget);
      expect(find.text('Calendario'), findsNothing);
    });

    testWidgets('renders header, date picker, Hoje shortcut and counter', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Calendario'), findsOneWidget);
      expect(
        find.text('Agendamentos por dia e horario'),
        findsOneWidget,
      );
      expect(find.text('Hoje'), findsOneWidget);
      expect(find.text('Alterar'), findsOneWidget);
      expect(find.text('0 atendimentos'), findsOneWidget);
    });

    testWidgets('shows the loading skeleton while appointments load', (
      tester,
    ) async {
      final controller = StreamController<List<AppointmentModel>>();
      addTearDown(controller.close);
      when(
        () => appointmentRepository.appointmentsForDayStream('b1', any()),
      ).thenAnswer((_) => controller.stream);

      await pumpScreen(tester, settle: false);
      await tester.pump();

      expect(find.byType(AppSkeletonList), findsOneWidget);
    });

    testWidgets('shows the error state with retry when loading fails', (
      tester,
    ) async {
      when(
        () => appointmentRepository.appointmentsForDayStream('b1', any()),
      ).thenAnswer((_) => Stream.error(Exception('falha')));

      await pumpScreen(tester);

      expect(
        find.text('Nao foi possivel carregar os agendamentos'),
        findsOneWidget,
      );
      expect(find.text('Tentar novamente'), findsOneWidget);
    });

    testWidgets('shows the empty state when there are no appointments', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Nenhum agendamento neste dia'), findsOneWidget);
    });

    testWidgets('shows a filter-no-results state distinct from empty day', (
      tester,
    ) async {
      when(
        () => appointmentRepository.appointmentsForDayStream('b1', any()),
      ).thenAnswer(
        (_) => Stream.value([
          appointment(clientName: 'Alice Silva'),
          appointment(clientName: 'Bruno Souza'),
        ]),
      );

      await pumpScreen(tester);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();

      expect(
        find.text('Nenhum agendamento encontrado para os filtros'),
        findsOneWidget,
      );
      expect(find.text('Nenhum agendamento neste dia'), findsNothing);
    });

    testWidgets('renders appointments with time, service and client', (
      tester,
    ) async {
      when(
        () => appointmentRepository.appointmentsForDayStream('b1', any()),
      ).thenAnswer((_) => Stream.value([appointment()]));

      await pumpScreen(tester);

      expect(find.text('10:00'), findsOneWidget);
      expect(find.text('Alice Silva'), findsOneWidget);
      expect(find.text('Agendado'), findsOneWidget);
      expect(find.text('1 atendimento'), findsOneWidget);
    });

    testWidgets('renders the status badge for canceled appointments', (
      tester,
    ) async {
      when(
        () => appointmentRepository.appointmentsForDayStream('b1', any()),
      ).thenAnswer(
        (_) => Stream.value([appointment(status: AppointmentStatus.canceled)]),
      );

      await pumpScreen(tester);

      expect(find.text('Cancelado'), findsOneWidget);
    });

    testWidgets('filters appointments by client name', (tester) async {
      when(
        () => appointmentRepository.appointmentsForDayStream('b1', any()),
      ).thenAnswer(
        (_) => Stream.value([
          appointment(clientName: 'Alice Silva'),
          appointment(clientName: 'Bruno Souza'),
        ]),
      );

      await pumpScreen(tester);
      await tester.enterText(find.byType(TextField), 'bruno');
      await tester.pumpAndSettle();

      expect(find.text('Alice Silva'), findsNothing);
      expect(find.text('Bruno Souza'), findsOneWidget);
      expect(find.text('1 atendimento'), findsOneWidget);
    });

    testWidgets('renders the filter dropdowns with available options', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Servico'), findsOneWidget);
      expect(find.text('Cliente'), findsOneWidget);

      await tester.tap(find.text('Servico'));
      await tester.pumpAndSettle();

      expect(find.text('Todos'), findsWidgets);
      expect(find.text('Banho'), findsWidgets);
    });

    testWidgets('shows collapsible filters on narrow screens', (tester) async {
      await pumpScreen(tester, size: const Size(400, 2400));

      expect(find.text('Filtros'), findsOneWidget);
      expect(find.text('Servico'), findsNothing);

      await tester.tap(find.text('Filtros'));
      await tester.pumpAndSettle();

      expect(find.text('Servico'), findsOneWidget);
    });
  });
}
