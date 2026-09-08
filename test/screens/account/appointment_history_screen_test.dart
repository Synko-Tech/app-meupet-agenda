import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/controllers/appointment_controller.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/controllers/business_context_controller.dart';
import 'package:meupet_agenda_app/models/app_user.dart';
import 'package:meupet_agenda_app/models/appointment_model.dart';
import 'package:meupet_agenda_app/models/business_membership.dart';
import 'package:meupet_agenda_app/repositories/appointment_repository.dart';
import 'package:meupet_agenda_app/repositories/auth_repository.dart';
import 'package:meupet_agenda_app/repositories/business_repository.dart';
import 'package:meupet_agenda_app/repositories/user_repository.dart';
import 'package:meupet_agenda_app/screens/account/appointment_history_screen.dart';
import 'package:meupet_agenda_app/services/notification_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockBusinessRepository extends Mock implements BusinessRepository {}

class MockUserRepository extends Mock implements UserRepository {}

class MockNotificationService extends Mock implements NotificationService {}

class MockAppointmentRepository extends Mock implements AppointmentRepository {}

AppUser clientUser() {
  return AppUser(
    id: 'c1',
    name: 'Alice Silva',
    email: 'alice@exemplo.com',
    role: UserRole.client,
  );
}

AppointmentModel appointment({AppointmentStatus status = AppointmentStatus.scheduled}) {
  final start = DateTime(2026, 8, 15, 10);
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

void main() {
  late MockAuthRepository authRepository;
  late MockUserRepository userRepository;
  late MockNotificationService notificationService;
  late MockAppointmentRepository appointments;

  setUp(() {
    authRepository = MockAuthRepository();
    userRepository = MockUserRepository();
    notificationService = MockNotificationService();
    appointments = MockAppointmentRepository();
    when(
      () => authRepository.authStateChanges(),
    ).thenAnswer((_) => const Stream.empty());
  });

  Future<void> pumpHistory(
    WidgetTester tester, {
    AppUser? profile,
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
    auth.profile = profile ?? clientUser();
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
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: businessContext),
          ChangeNotifierProvider(
            create: (_) => AppointmentController(
              repository: appointments,
              businessContext: businessContext,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AppointmentHistoryScreen(profile: auth.profile!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AppointmentHistoryScreen', () {
    testWidgets('renders header and empty state', (tester) async {
      when(() => appointments.customerAppointmentsStream('b1', 'c1')).thenAnswer(
        (_) => Stream.value(const []),
      );

      await pumpHistory(tester);

      expect(find.text('Historico de agendamentos'), findsOneWidget);
      expect(find.text('Sem agendamentos ainda'), findsOneWidget);
    });

    testWidgets('renders the four filter chips', (tester) async {
      when(() => appointments.customerAppointmentsStream('b1', 'c1')).thenAnswer(
        (_) => Stream.value([appointment()]),
      );

      await pumpHistory(tester);

      expect(find.text('Todos'), findsOneWidget);
      expect(find.text('Agendados'), findsOneWidget);
      expect(find.text('Concluidos'), findsOneWidget);
      expect(find.text('Cancelados'), findsOneWidget);
    });

    testWidgets('client sees own appointments with status badge', (tester) async {
      when(() => appointments.customerAppointmentsStream('b1', 'c1')).thenAnswer(
        (_) => Stream.value([appointment()]),
      );

      await pumpHistory(tester);

      expect(find.text('Banho'), findsOneWidget);
      expect(find.text('15/08/2026 as 10:00'), findsOneWidget);
      expect(find.text('Agendado'), findsOneWidget);
    });

    testWidgets('staff sees all appointments including client name', (
      tester,
    ) async {
      when(() => appointments.allAppointmentsStream('b1')).thenAnswer(
        (_) => Stream.value([appointment(status: AppointmentStatus.completed)]),
      );

      await pumpHistory(
        tester,
        profile: AppUser(
          id: 'a1',
          name: 'Bruno',
          email: 'bruno@exemplo.com',
          role: UserRole.admin,
        ),
      );

      expect(find.text('Banho'), findsOneWidget);
      expect(find.textContaining('Alice Silva'), findsOneWidget);
      expect(find.text('Concluido'), findsOneWidget);
    });

    testWidgets('filters by canceled status', (tester) async {
      when(() => appointments.customerAppointmentsStream('b1', 'c1')).thenAnswer(
        (_) => Stream.value([
          appointment(),
          appointment(status: AppointmentStatus.canceled),
        ]),
      );

      await pumpHistory(tester);
      await tester.tap(find.text('Cancelados'));
      await tester.pumpAndSettle();

      expect(find.text('Cancelado'), findsOneWidget);
    });
  });
}
