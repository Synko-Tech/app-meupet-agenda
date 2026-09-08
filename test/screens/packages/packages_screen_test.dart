import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/app/formatters.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/controllers/business_context_controller.dart';
import 'package:meupet_agenda_app/controllers/package_controller.dart';
import 'package:meupet_agenda_app/models/app_user.dart';
import 'package:meupet_agenda_app/models/appointment_model.dart';
import 'package:meupet_agenda_app/models/business_membership.dart';
import 'package:meupet_agenda_app/models/package_model.dart';
import 'package:meupet_agenda_app/repositories/appointment_repository.dart';
import 'package:meupet_agenda_app/repositories/auth_repository.dart';
import 'package:meupet_agenda_app/repositories/business_repository.dart';
import 'package:meupet_agenda_app/repositories/package_repository.dart';
import 'package:meupet_agenda_app/repositories/user_repository.dart';
import 'package:meupet_agenda_app/screens/packages/packages_screen.dart';
import 'package:meupet_agenda_app/services/checkout_launcher.dart';
import 'package:meupet_agenda_app/services/notification_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockUserRepository extends Mock implements UserRepository {}

class MockNotificationService extends Mock implements NotificationService {}

class MockPackageRepository extends Mock implements PackageRepository {}

class MockAppointmentRepository extends Mock implements AppointmentRepository {}

class MockBusinessRepository extends Mock implements BusinessRepository {}

class MockBusinessContextController extends Mock
    implements BusinessContextController {}

const clientUser = AppUser(
  id: 'c1',
  name: 'Alice',
  email: 'alice@exemplo.com',
  role: UserRole.client,
);

const staffUser = AppUser(
  id: 'c1',
  name: 'Alice',
  email: 'alice@exemplo.com',
  role: UserRole.collaborator,
);

CustomerPackageModel customerPackage({
  CustomerPackageStatus status = CustomerPackageStatus.active,
}) {
  return CustomerPackageModel(
    id: 'cp1',
    clientId: 'c1',
    packageId: 'bp1',
    serviceId: 's1',
    packageName: 'Pacote Banho 5x',
    serviceName: 'Banho',
    totalCredits: 5,
    usedCredits: 2,
    purchaseDate: DateTime(2026, 7, 1),
    validUntil: DateTime.now().add(const Duration(days: 30)),
    status: status,
  );
}

const businessPackage = BusinessPackageModel(
  id: 'bp1',
  serviceId: 's1',
  serviceName: 'Banho',
  name: 'Pacote Banho 5x',
  totalCredits: 5,
  price: 150.0,
  validityDays: 30,
);

AppointmentModel packageUsage() {
  return AppointmentModel(
    id: 'a1',
    clientId: 'c1',
    clientName: 'Alice',
    serviceId: 's1',
    serviceName: 'Banho',
    customerPackageId: 'cp1',
    startAt: DateTime(2026, 8, 1, 10, 0),
    endAt: DateTime(2026, 8, 1, 11, 0),
    status: AppointmentStatus.completed,
  );
}

void main() {
  late MockAuthRepository authRepository;
  late MockUserRepository userRepository;
  late MockNotificationService notificationService;
  late MockPackageRepository packageRepository;
  late MockAppointmentRepository appointmentRepository;
  late MockBusinessContextController businessContext;
  late AuthController authController;
  late PackageController packageController;
  late FakeCheckoutLauncher launcher;

  setUp(() {
    authRepository = MockAuthRepository();
    userRepository = MockUserRepository();
    notificationService = MockNotificationService();
    packageRepository = MockPackageRepository();
    appointmentRepository = MockAppointmentRepository();
    launcher = FakeCheckoutLauncher();
    businessContext = MockBusinessContextController();
    when(() => businessContext.activeBusinessId).thenReturn('b1');

    when(
      () => authRepository.authStateChanges(),
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => packageRepository.customerPackagesStream('b1', any()),
    ).thenAnswer((_) => Stream.value(const []));
    when(
      () => packageRepository.activePackagesStream('b1'),
    ).thenAnswer((_) => Stream.value(const []));
    when(
      () => appointmentRepository.customerAppointmentsStream('b1', any()),
    ).thenAnswer((_) => Stream.value(const []));

    authController = AuthController(
      authRepository: authRepository,
      userRepository: userRepository,
      notificationService: notificationService,
    );
    authController.profile = clientUser;
    authController.isLoading = false;

    packageController = PackageController(
      packageRepository: packageRepository,
      checkoutLauncher: launcher,
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
          Provider<PackageRepository>(create: (_) => packageRepository),
          Provider<AppointmentRepository>(create: (_) => appointmentRepository),
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
          ChangeNotifierProvider<PackageController>.value(
            value: packageController,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: PackagesScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('PackagesScreen', () {
    testWidgets('shows a loading spinner while customer packages load', (
      tester,
    ) async {
      final packagesController = StreamController<List<CustomerPackageModel>>();
      addTearDown(packagesController.close);
      when(
        () => packageRepository.customerPackagesStream('b1', any()),
      ).thenAnswer((_) => packagesController.stream);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<PackageRepository>(create: (_) => packageRepository),
            Provider<AppointmentRepository>(
              create: (_) => appointmentRepository,
            ),
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
            ChangeNotifierProvider<PackageController>.value(
              value: packageController,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: PackagesScreen()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows an empty state when the client has no packages', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Meus pacotes'), findsOneWidget);
      expect(find.text('Nenhum pacote comprado'), findsOneWidget);
    });

    testWidgets('renders customer packages with balance and validity', (
      tester,
    ) async {
      when(
        () => packageRepository.customerPackagesStream('b1', any()),
      ).thenAnswer((_) => Stream.value([customerPackage()]));

      await pumpScreen(tester);

      final validText =
          'Valido ate ${formatDate(DateTime.now().add(const Duration(days: 30)))}';
      expect(find.text('Pacote Banho 5x'), findsWidgets);
      expect(find.text(validText), findsOneWidget);
      expect(find.text('3 disponiveis'), findsOneWidget);
      expect(find.text('2 usados de 5'), findsOneWidget);
      expect(find.text('Ativo'), findsOneWidget);
    });

    testWidgets('shows the usage history empty message by default', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Ultimas utilizacoes'), findsOneWidget);
      expect(find.text('Nenhum credito utilizado ainda.'), findsOneWidget);
    });

    testWidgets('renders package usage from appointments', (tester) async {
      when(
        () => appointmentRepository.customerAppointmentsStream('b1', any()),
      ).thenAnswer((_) => Stream.value([packageUsage()]));

      await pumpScreen(tester);

      expect(find.text('01/08 - Banho'), findsOneWidget);
      expect(find.text('Nenhum credito utilizado ainda.'), findsNothing);
    });

    testWidgets('shows an empty state when the catalog has no packages', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Comprar pacote'), findsOneWidget);
      expect(find.text('Catalogo vazio'), findsOneWidget);
    });

    testWidgets('renders catalog packages with price and credits', (
      tester,
    ) async {
      when(
        () => packageRepository.activePackagesStream('b1'),
      ).thenAnswer((_) => Stream.value(const [businessPackage]));

      await pumpScreen(tester);

      expect(
        find.text('5 creditos para Banho. Validade de 30 dias.'),
        findsOneWidget,
      );
      expect(find.text('R\$ 150,00'), findsOneWidget);
    });

    testWidgets('clients see the buy button', (tester) async {
      when(
        () => packageRepository.activePackagesStream('b1'),
      ).thenAnswer((_) => Stream.value(const [businessPackage]));

      await pumpScreen(tester);

      expect(find.text('Comprar novo pacote'), findsOneWidget);
      expect(find.byKey(const Key('packages_buy_button')), findsOneWidget);
    });

    testWidgets('staff see the buy button', (tester) async {
      authController.profile = staffUser;
      when(
        () => packageRepository.activePackagesStream('b1'),
      ).thenAnswer((_) => Stream.value(const [businessPackage]));

      await pumpScreen(tester);

      expect(find.text('Comprar novo pacote'), findsOneWidget);
    });

    testWidgets('a successful purchase opens the Mercado Pago checkout', (
      tester,
    ) async {
      final checkout = MercadoPagoCheckout(
        paymentId: 'pay-1',
        preferenceId: 'pref-1',
        initPoint: Uri.parse('https://checkout.mercadopago.com.br/abc'),
      );
      when(
        () => packageRepository.activePackagesStream('b1'),
      ).thenAnswer((_) => Stream.value(const [businessPackage]));
      when(
        () => packageRepository.createMercadoPagoCheckout(
          businessId: 'b1',
          packageId: any(named: 'packageId'),
        ),
      ).thenAnswer((_) async => checkout);

      await pumpScreen(tester);
      await tester.tap(find.text('Comprar novo pacote'));
      await tester.pumpAndSettle();

      verify(
        () => packageRepository.createMercadoPagoCheckout(
          businessId: 'b1',
          packageId: 'bp1',
        ),
      ).called(1);
      expect(
        find.text('Conclua o pagamento no Mercado Pago para ativar o pacote.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed purchase shows the error message', (tester) async {
      authController.profile = staffUser;
      when(
        () => packageRepository.activePackagesStream('b1'),
      ).thenAnswer((_) => Stream.value(const [businessPackage]));
      when(
        () => packageRepository.createMercadoPagoCheckout(
          businessId: 'b1',
          packageId: any(named: 'packageId'),
        ),
      ).thenThrow(StateError('Resposta invalida do servidor.'));

      await pumpScreen(tester);
      await tester.tap(find.text('Comprar novo pacote'));
      await tester.pumpAndSettle();

      expect(find.text('Resposta invalida do servidor.'), findsOneWidget);
    });
  });
}
