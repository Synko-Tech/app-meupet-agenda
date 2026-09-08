import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/controllers/admin_controller.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/controllers/business_context_controller.dart';
import 'package:meupet_agenda_app/models/app_user.dart';
import 'package:meupet_agenda_app/models/business_membership.dart';
import 'package:meupet_agenda_app/repositories/appointment_repository.dart';
import 'package:meupet_agenda_app/repositories/auth_repository.dart';
import 'package:meupet_agenda_app/repositories/business_repository.dart';
import 'package:meupet_agenda_app/repositories/package_repository.dart';
import 'package:meupet_agenda_app/repositories/payment_repository.dart';
import 'package:meupet_agenda_app/repositories/service_repository.dart';
import 'package:meupet_agenda_app/repositories/user_repository.dart';
import 'package:meupet_agenda_app/screens/customers/customers_screen.dart';
import 'package:meupet_agenda_app/services/notification_service.dart';
import 'package:meupet_agenda_app/widgets/app_skeleton.dart';
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

AppUser clientUser({
  required String id,
  required String name,
  required String email,
  String? phone,
  bool isActive = true,
}) {
  return AppUser(
    id: id,
    name: name,
    email: email,
    phone: phone,
    role: UserRole.client,
    isActive: isActive,
  );
}

const activeAlice = AppUser(
  id: 'c1',
  name: 'Alice',
  email: 'alice@exemplo.com',
  phone: '11999990001',
  role: UserRole.client,
  isActive: true,
);

const activeBruno = AppUser(
  id: 'c2',
  name: 'Bruno',
  email: 'bruno@exemplo.com',
  role: UserRole.client,
  isActive: true,
);

const inactiveCarol = AppUser(
  id: 'c3',
  name: 'Carol',
  email: 'carol@exemplo.com',
  phone: '11999990003',
  role: UserRole.client,
  isActive: false,
);

void main() {
  late MockUserRepository userRepository;
  late MockAppointmentRepository appointmentRepository;
  late MockPackageRepository packageRepository;
  late MockPaymentRepository paymentRepository;
  late MockAuthRepository authRepository;

  setUp(() {
    userRepository = MockUserRepository();
    appointmentRepository = MockAppointmentRepository();
    packageRepository = MockPackageRepository();
    paymentRepository = MockPaymentRepository();
    authRepository = MockAuthRepository();
    when(
      () => authRepository.authStateChanges(),
    ).thenAnswer((_) => const Stream.empty());
    when(() => userRepository.allClientsStream()).thenAnswer(
      (_) => Stream.value(const [activeAlice, activeBruno, inactiveCarol]),
    );
    when(
      () => userRepository.profileStream(any()),
    ).thenAnswer((_) => Stream.value(activeAlice));
    when(
      () => appointmentRepository.customerAppointmentsStream('b1', any()),
    ).thenAnswer((_) => Stream.value(const []));
    when(
      () => packageRepository.customerPackagesStream('b1', any()),
    ).thenAnswer((_) => Stream.value(const []));
    when(
      () => paymentRepository.customerPaymentsStream('b1', any()),
    ).thenAnswer((_) => Stream.value(const []));
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<UserRepository>(create: (_) => userRepository),
          Provider<AppointmentRepository>(create: (_) => appointmentRepository),
          Provider<PackageRepository>(create: (_) => packageRepository),
          Provider<PaymentRepository>(create: (_) => paymentRepository),
          Provider<ServiceRepository>(create: (_) => MockServiceRepository()),
          ChangeNotifierProvider(
            create: (_) => AuthController(
              authRepository: authRepository,
              userRepository: userRepository,
              notificationService: MockNotificationService(),
            ),
          ),
          ChangeNotifierProvider(
            create: (context) {
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
              final businessContext = BusinessContextController(
                repository: repository,
                authController: context.read<AuthController>(),
              );
              businessContext.selectBusiness('b1');
              return businessContext;
            },
          ),
          ChangeNotifierProvider(
            create: (context) => AdminController(
              serviceRepository: context.read<ServiceRepository>(),
              packageRepository: context.read<PackageRepository>(),
              userRepository: userRepository,
              authController: context.read<AuthController>(),
              businessContext: context.read<BusinessContextController>(),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: CustomersScreen()),
        ),
      ),
    );
    await tester.pump();
  }

  group('CustomersScreen', () {
    testWidgets('renders all clients with status badges', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Clientes'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bruno'), findsOneWidget);
      expect(find.text('Carol'), findsOneWidget);
      expect(find.text('Ativo'), findsNWidgets(2));
      expect(find.text('Inativo'), findsOneWidget);
      expect(find.text('3 resultados'), findsOneWidget);
    });

    testWidgets('renders phone when present', (tester) async {
      await pumpScreen(tester);

      expect(find.text('11999990001'), findsOneWidget);
      expect(find.text('11999990003'), findsOneWidget);
    });

    testWidgets('filters by status chips', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const ValueKey('customer-filter-inactive')));
      await tester.pump();

      expect(find.text('Carol'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      expect(find.text('1 resultado'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('customer-filter-active')));
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bruno'), findsOneWidget);
      expect(find.text('Carol'), findsNothing);
      expect(find.text('2 resultados'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('customer-filter-all')));
      await tester.pump();

      expect(find.text('3 resultados'), findsOneWidget);
    });

    testWidgets('searches by name, email and phone', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.byKey(const ValueKey('customer-search')),
        'bru',
      );
      await tester.pump();

      expect(find.text('Bruno'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('customer-search')),
        'carol@exemplo.com',
      );
      await tester.pump();

      expect(find.text('Carol'), findsOneWidget);
      expect(find.text('Bruno'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('customer-search')),
        '0001',
      );
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Carol'), findsNothing);
    });

    testWidgets('search that matches nothing shows the empty filtered state', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.byKey(const ValueKey('customer-search')),
        'zzz',
      );
      await tester.pump();

      expect(find.text('Nenhum resultado'), findsOneWidget);
      expect(find.text('0 resultados'), findsOneWidget);
    });

    testWidgets('shows loading skeleton while waiting', (tester) async {
      final controller = StreamController<List<AppUser>>();
      addTearDown(controller.close);
      when(
        () => userRepository.allClientsStream(),
      ).thenAnswer((_) => controller.stream);

      await pumpScreen(tester);

      expect(find.byType(AppSkeletonList), findsOneWidget);
    });

    testWidgets('shows empty state when there are no clients', (tester) async {
      when(
        () => userRepository.allClientsStream(),
      ).thenAnswer((_) => Stream.value(const []));

      await pumpScreen(tester);
      await tester.pump();

      expect(find.text('Nenhum cliente'), findsOneWidget);
    });

    testWidgets('shows error state and retry', (tester) async {
      var failing = true;
      when(() => userRepository.allClientsStream()).thenAnswer((_) {
        if (failing) {
          return Stream.error(Exception('falha'));
        }
        return Stream.value(const [activeAlice]);
      });

      await pumpScreen(tester);
      await tester.pump();

      expect(find.text('Nao foi possivel carregar'), findsOneWidget);

      failing = false;
      await tester.tap(find.text('Tentar novamente'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('tapping a card opens the details screen', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const ValueKey('customer-card-c1')));
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Cliente'), findsOneWidget);
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
