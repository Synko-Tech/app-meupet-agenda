import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/controllers/appointment_controller.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/controllers/business_context_controller.dart';
import 'package:meupet_agenda_app/controllers/merchant_connection_controller.dart';
import 'package:meupet_agenda_app/controllers/theme_controller.dart';
import 'package:meupet_agenda_app/models/app_user.dart';
import 'package:meupet_agenda_app/models/business_membership.dart';
import 'package:meupet_agenda_app/models/merchant_connection_summary.dart';
import 'package:meupet_agenda_app/repositories/appointment_repository.dart';
import 'package:meupet_agenda_app/repositories/auth_repository.dart';
import 'package:meupet_agenda_app/repositories/business_repository.dart';
import 'package:meupet_agenda_app/repositories/merchant_connection_repository.dart';
import 'package:meupet_agenda_app/repositories/payment_repository.dart';
import 'package:meupet_agenda_app/repositories/private_profile_repository.dart';
import 'package:meupet_agenda_app/repositories/user_repository.dart';
import 'package:meupet_agenda_app/screens/account/account_screen.dart';
import 'package:meupet_agenda_app/screens/account/private_profile_screen.dart';
import 'package:meupet_agenda_app/services/notification_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockBusinessRepository extends Mock implements BusinessRepository {}

class MockMerchantConnectionRepository extends Mock
    implements MerchantConnectionRepository {}

class MockUserRepository extends Mock implements UserRepository {}

class MockNotificationService extends Mock implements NotificationService {}

class MockAppointmentRepository extends Mock implements AppointmentRepository {}

class MockPaymentRepository extends Mock implements PaymentRepository {}

class MockPrivateProfileRepository extends Mock
    implements PrivateProfileRepository {}

AppUser userWithRole(UserRole role) {
  return AppUser(
    id: switch (role) {
      UserRole.superAdmin => 'sa1',
      UserRole.admin => 'a1',
      UserRole.collaborator => 'co1',
      UserRole.client => 'c1',
    },
    name: 'Alice Silva',
    email: 'alice@exemplo.com',
    role: role,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(userWithRole(UserRole.client));
  });

  late MockAuthRepository authRepository;
  late MockUserRepository userRepository;
  late MockNotificationService notificationService;
  late MockAppointmentRepository appointments;
  late MockPaymentRepository payments;
  late MockPrivateProfileRepository privateProfileRepository;

  setUp(() {
    authRepository = MockAuthRepository();
    userRepository = MockUserRepository();
    notificationService = MockNotificationService();
    appointments = MockAppointmentRepository();
    payments = MockPaymentRepository();
    privateProfileRepository = MockPrivateProfileRepository();
    when(
      () => privateProfileRepository.privateProfileStream(any()),
    ).thenAnswer((_) => Stream.value(null));
    when(
      () => authRepository.authStateChanges(),
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => appointments.customerAppointmentsStream('b1', any()),
    ).thenAnswer((_) => Stream.value(const []));
    when(
      () => appointments.allAppointmentsStream('b1'),
    ).thenAnswer((_) => Stream.value(const []));
    when(
      () => payments.customerPaymentsStream('b1', any()),
    ).thenAnswer((_) => Stream.value(const []));
  });

  BusinessContextController createBusinessContext(
    AuthController auth, {
    BusinessRole role = BusinessRole.owner,
  }) {
    final repository = MockBusinessRepository();
    when(() => repository.myMembershipsStream(any())).thenAnswer(
      (_) => Stream.value([
        BusinessMembership(
          userId: 'u1',
          businessId: 'b1',
          businessName: 'Loja Teste',
          role: role,
        ),
      ]),
    );
    final context = BusinessContextController(
      repository: repository,
      authController: auth,
    );
    // firebaseUser é null nos testes, então a stream de memberships não
    // assina; preenche o contexto diretamente para exercitar o card.
    context.memberships = [
      BusinessMembership(
        userId: 'u1',
        businessId: 'b1',
        businessName: 'Loja Teste',
        role: role,
      ),
    ];
    context.activeBusinessId = 'b1';
    context.activeMembership = context.memberships.first;
    context.isLoading = false;
    addTearDown(context.dispose);
    return context;
  }

  MockMerchantConnectionRepository createMerchantRepository() {
    final repository = MockMerchantConnectionRepository();
    when(
      () => repository.merchantSummaryStream('b1'),
    ).thenAnswer((_) => Stream.value(MerchantConnectionSummary.disconnected));
    return repository;
  }

  Future<void> pumpAccount(
    WidgetTester tester, {
    UserRole role = UserRole.client,
    BusinessRole businessRole = BusinessRole.owner,
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
    auth.profile = userWithRole(role);
    auth.isLoading = false;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppointmentRepository>(create: (_) => appointments),
          Provider<PaymentRepository>(create: (_) => payments),
          Provider<MerchantConnectionRepository>(
            create: (_) => createMerchantRepository(),
          ),
          Provider<PrivateProfileRepository>.value(
            value: privateProfileRepository,
          ),
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(
            value: createBusinessContext(auth, role: businessRole),
          ),
          ChangeNotifierProvider(
            create: (context) => AppointmentController(
              repository: appointments,
              businessContext: context.read<BusinessContextController>(),
            ),
          ),
          ChangeNotifierProvider(
            create: (context) => MerchantConnectionController(
              repository: context.read<MerchantConnectionRepository>(),
              businessContext: context.read<BusinessContextController>(),
            ),
          ),
          ChangeNotifierProvider(create: (_) => ThemeController()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AccountScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AccountScreen', () {
    testWidgets('clearing the phone field saves an empty phone', (
      tester,
    ) async {
      final profile = AppUser(
        id: 'c1',
        name: 'Alice Silva',
        email: 'alice@exemplo.com',
        phone: '(11) 99999-0000',
        role: UserRole.client,
      );
      authRepository = MockAuthRepository();
      when(
        () => authRepository.authStateChanges(),
      ).thenAnswer((_) => const Stream.empty());
      final auth = AuthController(
        authRepository: authRepository,
        userRepository: userRepository,
        notificationService: notificationService,
      );
      addTearDown(auth.dispose);
      auth.profile = profile;
      auth.isLoading = false;
      when(() => userRepository.updateProfile(any())).thenAnswer((_) async {});

      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AppointmentRepository>(create: (_) => appointments),
            Provider<PaymentRepository>(create: (_) => payments),
            Provider<MerchantConnectionRepository>(
              create: (_) => createMerchantRepository(),
            ),
            Provider<PrivateProfileRepository>.value(
              value: privateProfileRepository,
            ),
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: createBusinessContext(auth)),
            ChangeNotifierProvider(
              create: (context) => AppointmentController(
                repository: appointments,
                businessContext: context.read<BusinessContextController>(),
              ),
            ),
            ChangeNotifierProvider(
              create: (context) => MerchantConnectionController(
                repository: context.read<MerchantConnectionRepository>(),
                businessContext: context.read<BusinessContextController>(),
              ),
            ),
            ChangeNotifierProvider(create: (_) => ThemeController()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: AccountScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Editar perfil'));
      await tester.pumpAndSettle();

      final phoneField = find.byType(TextFormField).at(1);
      await tester.enterText(phoneField, '');
      await tester.tap(find.text('Salvar alteracoes'));
      await tester.pumpAndSettle();

      expect(find.text('Perfil atualizado.'), findsOneWidget);
      final captured = verify(
        () => userRepository.updateProfile(captureAny()),
      ).captured;
      expect(captured.single.phone, isNull);
    });

    testWidgets('admin sees history and financial summary buttons', (
      tester,
    ) async {
      await pumpAccount(tester, role: UserRole.admin);

      expect(find.text('Historico de agendamentos'), findsOneWidget);
      expect(find.text('Resumo financeiro'), findsOneWidget);
    });

    testWidgets('client does not see admin navigation buttons', (tester) async {
      await pumpAccount(tester, role: UserRole.client);

      expect(find.text('Historico de agendamentos'), findsNothing);
      expect(find.text('Resumo financeiro'), findsNothing);
    });

    testWidgets('tapping the history button opens the history screen', (
      tester,
    ) async {
      await pumpAccount(tester, role: UserRole.admin);

      await tester.tap(find.text('Historico de agendamentos'));
      await tester.pumpAndSettle();

      expect(find.text('Historico de agendamentos'), findsWidgets);
    });

    testWidgets('renders dark mode toggle', (tester) async {
      await pumpAccount(tester, role: UserRole.client);

      expect(find.text('Modo escuro'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('toggling switch changes theme', (tester) async {
      await pumpAccount(tester, role: UserRole.client);

      final themeController = tester
          .element(find.byType(AccountScreen))
          .read<ThemeController>();
      expect(themeController.isDark, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(themeController.isDark, isTrue);
    });

    testWidgets('staff owner sees the payments receiving card with the '
        'connect button', (tester) async {
      await pumpAccount(tester, role: UserRole.admin);

      expect(find.text('Recebimentos'), findsOneWidget);
      expect(find.text('Nao conectado'), findsOneWidget);
      expect(find.text('Conectar Mercado Pago'), findsOneWidget);
    });

    testWidgets('client does not see the payments receiving card', (
      tester,
    ) async {
      await pumpAccount(
        tester,
        role: UserRole.client,
        businessRole: BusinessRole.client,
      );

      expect(find.text('Recebimentos'), findsNothing);
      expect(find.text('Conectar Mercado Pago'), findsNothing);
    });

    testWidgets('owner sees connected state without financial details', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final auth = AuthController(
        authRepository: authRepository,
        userRepository: userRepository,
        notificationService: notificationService,
      );
      addTearDown(auth.dispose);
      auth.profile = userWithRole(UserRole.admin);
      auth.isLoading = false;

      final merchantRepository = MockMerchantConnectionRepository();
      when(() => merchantRepository.merchantSummaryStream('b1')).thenAnswer(
        (_) => Stream.value(
          MerchantConnectionSummary(
            status: MerchantConnectionStatus.connected,
            collectorId: 'seller-42',
            liveMode: true,
            connectedAt: DateTime(2026, 8, 1),
          ),
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AppointmentRepository>(create: (_) => appointments),
            Provider<PaymentRepository>(create: (_) => payments),
            Provider<MerchantConnectionRepository>(
              create: (_) => merchantRepository,
            ),
            Provider<PrivateProfileRepository>.value(
              value: privateProfileRepository,
            ),
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: createBusinessContext(auth)),
            ChangeNotifierProvider(
              create: (context) => AppointmentController(
                repository: appointments,
                businessContext: context.read<BusinessContextController>(),
              ),
            ),
            ChangeNotifierProvider(
              create: (context) => MerchantConnectionController(
                repository: context.read<MerchantConnectionRepository>(),
                businessContext: context.read<BusinessContextController>(),
              ),
            ),
            ChangeNotifierProvider(create: (_) => ThemeController()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: AccountScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mercado Pago conectado'), findsOneWidget);
      expect(find.text('Producao'), findsOneWidget);
      expect(find.text('Conta •••• r-42'), findsOneWidget);
      // O card esconde o collectorId cru e os tokens.
      expect(find.text('seller-42'), findsNothing);
      expect(find.text('Conectar Mercado Pago'), findsNothing);
    });

    testWidgets('all roles see the Dados pessoais button', (tester) async {
      await pumpAccount(tester, role: UserRole.client);

      expect(find.text('Dados pessoais'), findsOneWidget);
    });

    testWidgets('tapping Dados pessoais opens the private profile screen', (
      tester,
    ) async {
      await pumpAccount(tester, role: UserRole.admin);

      await tester.tap(find.text('Dados pessoais'));
      await tester.pumpAndSettle();

      final screen = tester.widget<PrivateProfileScreen>(
        find.byType(PrivateProfileScreen),
      );
      expect(screen.userId, 'a1');
    });

    testWidgets('only the super admin sees the private UID lookup entry', (
      tester,
    ) async {
      await pumpAccount(tester, role: UserRole.superAdmin);
      expect(find.byKey(const Key('private_lookup_uid_field')), findsOneWidget);
      expect(find.text('Ver dados privados'), findsOneWidget);
    });

    testWidgets('admin comum and collaborator do not see the private UID '
        'lookup', (tester) async {
      await pumpAccount(tester, role: UserRole.admin);
      expect(find.byKey(const Key('private_lookup_uid_field')), findsNothing);

      await pumpAccount(tester, role: UserRole.collaborator);
      expect(find.byKey(const Key('private_lookup_uid_field')), findsNothing);
    });

    testWidgets('super admin opens the private profile of a typed UID', (
      tester,
    ) async {
      await pumpAccount(tester, role: UserRole.superAdmin);

      await tester.enterText(
        find.byKey(const Key('private_lookup_uid_field')),
        'u99',
      );
      await tester.tap(find.text('Ver dados privados'));
      await tester.pumpAndSettle();

      final screen = tester.widget<PrivateProfileScreen>(
        find.byType(PrivateProfileScreen),
      );
      expect(screen.userId, 'u99');
    });
  });
}
