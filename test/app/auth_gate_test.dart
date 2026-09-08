import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/app_theme.dart';
import 'package:meupet_agenda_app/app/auth_gate.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/controllers/business_context_controller.dart';
import 'package:meupet_agenda_app/models/app_user.dart';
import 'package:meupet_agenda_app/models/business_membership.dart';
import 'package:meupet_agenda_app/repositories/appointment_repository.dart';
import 'package:meupet_agenda_app/repositories/auth_repository.dart';
import 'package:meupet_agenda_app/repositories/business_repository.dart';
import 'package:meupet_agenda_app/repositories/package_repository.dart';
import 'package:meupet_agenda_app/repositories/payment_repository.dart';
import 'package:meupet_agenda_app/repositories/user_repository.dart';
import 'package:meupet_agenda_app/screens/account/complete_profile_screen.dart';
import 'package:meupet_agenda_app/screens/auth/login_screen.dart';
import 'package:meupet_agenda_app/screens/business/business_selector_screen.dart';
import 'package:meupet_agenda_app/screens/business/create_business_screen.dart';
import 'package:meupet_agenda_app/screens/home/home_shell.dart';
import 'package:meupet_agenda_app/services/notification_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockAuthController extends Mock implements AuthController {}

class MockAuthRepository extends Mock implements AuthRepository {}

class MockUserRepository extends Mock implements UserRepository {}

class MockNotificationService extends Mock implements NotificationService {}

class MockAppointmentRepository extends Mock implements AppointmentRepository {}

class MockPackageRepository extends Mock implements PackageRepository {}

class MockPaymentRepository extends Mock implements PaymentRepository {}

class MockBusinessRepository extends Mock implements BusinessRepository {}

class MockFirebaseUser extends Mock implements User {
  MockFirebaseUser() {
    when(() => uid).thenReturn('u1');
  }
}

void main() {
  late MockAuthController auth;

  setUp(() {
    auth = MockAuthController();
    when(() => auth.isBusy).thenReturn(false);
    when(() => auth.isLoading).thenReturn(false);
    when(() => auth.firebaseUser).thenReturn(null);
    when(() => auth.profile).thenReturn(null);
    when(() => auth.isAuthenticatedAndActive).thenReturn(false);
    when(() => auth.isSuperAdmin).thenReturn(false);
    when(() => auth.isStaff).thenReturn(false);
    when(() => auth.canAccessAdminPanel).thenReturn(false);
    when(() => auth.signOut()).thenAnswer((_) async {});
  });

  Future<void> pumpGate(
    WidgetTester tester, {
    MockAppointmentRepository? appointmentRepository,
    MockPackageRepository? packageRepository,
    MockPaymentRepository? paymentRepository,
    MockBusinessRepository? businessRepository,
    BusinessContextController? businessContext,
  }) async {
    final business = businessRepository ?? MockBusinessRepository();
    if (businessRepository == null) {
      when(
        () => business.myMembershipsStream(any()),
      ).thenAnswer((_) => Stream.value(const <BusinessMembership>[]));
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          Provider<AppointmentRepository>(
            create: (_) => appointmentRepository ?? MockAppointmentRepository(),
          ),
          Provider<PackageRepository>(
            create: (_) => packageRepository ?? MockPackageRepository(),
          ),
          Provider<PaymentRepository>(
            create: (_) => paymentRepository ?? MockPaymentRepository(),
          ),
          if (businessContext != null)
            ChangeNotifierProvider<BusinessContextController>.value(
              value: businessContext,
            )
          else
            ChangeNotifierProvider(
              create: (_) => BusinessContextController(
                repository: business,
                authController: auth,
              ),
            ),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const AuthGate()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AuthGate', () {
    testWidgets('shows the splash while loading', (tester) async {
      when(() => auth.isLoading).thenReturn(true);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthController>.value(value: auth),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const AuthGate()),
        ),
      );

      // O spinner e infinito: pump simples, sem pumpAndSettle.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('shows login when signed out', (tester) async {
      await pumpGate(tester);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Acessar'), findsOneWidget);
    });

    testWidgets('shows the missing-profile screen and signs out', (
      tester,
    ) async {
      final firebaseUser = MockFirebaseUser();
      when(() => auth.firebaseUser).thenReturn(firebaseUser);
      when(() => auth.profile).thenReturn(null);

      await pumpGate(tester);

      expect(find.text('Perfil nao encontrado'), findsOneWidget);
      await tester.tap(find.text('Sair'));
      await tester.pump();
      verify(() => auth.signOut()).called(1);
    });

    testWidgets('shows the blocked-account screen and signs out', (
      tester,
    ) async {
      final profile = AppUser(
        id: 'u1',
        name: 'Cliente',
        email: 'cliente@exemplo.com',
        role: UserRole.client,
        isActive: false,
      );
      final firebaseUser = MockFirebaseUser();
      when(() => auth.firebaseUser).thenReturn(firebaseUser);
      when(() => auth.profile).thenReturn(profile);

      await pumpGate(tester);

      expect(find.text('Conta desativada'), findsOneWidget);
      await tester.tap(find.text('Sair'));
      await tester.pump();
      verify(() => auth.signOut()).called(1);
    });

    testWidgets('client without business membership goes to the shell '
        'instead of creating a store', (tester) async {
      final profile = AppUser(
        id: 'u1',
        name: 'Cliente',
        email: 'cliente@exemplo.com',
        role: UserRole.client,
        isActive: true,
        profileComplete: true,
      );
      final firebaseUser = MockFirebaseUser();
      when(() => auth.firebaseUser).thenReturn(firebaseUser);
      when(() => auth.profile).thenReturn(profile);
      when(() => auth.isAuthenticatedAndActive).thenReturn(true);
      when(() => auth.isStaff).thenReturn(false);

      final businessRepository = MockBusinessRepository();
      when(
        () => businessRepository.myMembershipsStream(any()),
      ).thenAnswer((_) => Stream.value(const <BusinessMembership>[]));

      await pumpGate(tester, businessRepository: businessRepository);

      expect(find.byType(CreateBusinessScreen), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);
    });

    testWidgets('staff without business membership creates the first '
        'business', (tester) async {
      final profile = AppUser(
        id: 'u1',
        name: 'Admin',
        email: 'admin@exemplo.com',
        role: UserRole.admin,
        isActive: true,
        profileComplete: true,
      );
      final firebaseUser = MockFirebaseUser();
      when(() => auth.firebaseUser).thenReturn(firebaseUser);
      when(() => auth.profile).thenReturn(profile);
      when(() => auth.isAuthenticatedAndActive).thenReturn(true);
      when(() => auth.isStaff).thenReturn(true);

      final businessRepository = MockBusinessRepository();
      when(
        () => businessRepository.myMembershipsStream(any()),
      ).thenAnswer((_) => Stream.value(const <BusinessMembership>[]));

      await pumpGate(tester, businessRepository: businessRepository);

      expect(find.byType(CreateBusinessScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
    });

    testWidgets('active profile with memberships but no selection shows the '
        'business selector', (tester) async {
      final profile = AppUser(
        id: 'u1',
        name: 'Cliente',
        email: 'cliente@exemplo.com',
        role: UserRole.client,
        isActive: true,
        profileComplete: true,
      );
      final firebaseUser = MockFirebaseUser();
      when(() => auth.firebaseUser).thenReturn(firebaseUser);
      when(() => auth.profile).thenReturn(profile);
      when(() => auth.isAuthenticatedAndActive).thenReturn(true);

      final businessRepository = MockBusinessRepository();
      when(() => businessRepository.myMembershipsStream(any())).thenAnswer(
        (_) => Stream.value(const [
          BusinessMembership(
            userId: 'u1',
            businessId: 'b1',
            businessName: 'Pet Shop',
            role: BusinessRole.owner,
          ),
        ]),
      );

      await pumpGate(tester, businessRepository: businessRepository);

      expect(find.byType(BusinessSelectorScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
    });

    testWidgets('active profile shows the role-appropriate home shell', (
      tester,
    ) async {
      final profile = AppUser(
        id: 'u1',
        name: 'Cliente',
        email: 'cliente@exemplo.com',
        role: UserRole.client,
        isActive: true,
        profileComplete: true,
      );
      final firebaseUser = MockFirebaseUser();
      when(() => auth.firebaseUser).thenReturn(firebaseUser);
      when(() => auth.profile).thenReturn(profile);
      when(() => auth.isAuthenticatedAndActive).thenReturn(true);

      final appointmentRepository = MockAppointmentRepository();
      final packageRepository = MockPackageRepository();
      final paymentRepository = MockPaymentRepository();
      when(
        () => appointmentRepository.customerAppointmentsStream('b1', any()),
      ).thenAnswer((_) => Stream.value(const []));
      when(
        () => packageRepository.customerPackagesStream('b1', any()),
      ).thenAnswer((_) => Stream.value(const []));
      when(
        () => paymentRepository.customerPaymentsStream('b1', any()),
      ).thenAnswer((_) => Stream.value(const []));

      final businessRepository = MockBusinessRepository();
      when(() => businessRepository.myMembershipsStream(any())).thenAnswer(
        (_) => Stream.value(const [
          BusinessMembership(
            userId: 'u1',
            businessId: 'b1',
            businessName: 'Pet Shop',
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

      await pumpGate(
        tester,
        appointmentRepository: appointmentRepository,
        packageRepository: packageRepository,
        paymentRepository: paymentRepository,
        businessContext: businessContext,
      );

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('profile stream stays null: gate never shows login or shell', (
      tester,
    ) async {
      final firebaseUser = MockFirebaseUser();
      when(() => auth.firebaseUser).thenReturn(firebaseUser);
      when(() => auth.profile).thenReturn(null);

      await pumpGate(tester);

      expect(find.text('Perfil nao encontrado'), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('active incomplete profile shows the complete-profile screen '
        'instead of the shell', (tester) async {
      final profile = AppUser(
        id: 'u1',
        name: 'Cliente Antigo',
        email: 'cliente@exemplo.com',
        role: UserRole.client,
        isActive: true,
        profileComplete: false,
      );
      final firebaseUser = MockFirebaseUser();
      when(() => auth.firebaseUser).thenReturn(firebaseUser);
      when(() => auth.profile).thenReturn(profile);
      when(() => auth.isAuthenticatedAndActive).thenReturn(true);

      await pumpGate(tester);

      expect(find.byType(CompleteProfileScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('completing the profile replaces the completion screen with '
        'the shell', (tester) async {
      final authRepository = MockAuthRepository();
      final userRepository = MockUserRepository();
      final notificationService = MockNotificationService();
      final authStream = StreamController<User?>.broadcast();
      final profileStream = StreamController<AppUser?>.broadcast();
      when(
        () => authRepository.authStateChanges(),
      ).thenAnswer((_) => authStream.stream);
      when(
        () => userRepository.profileStream(any()),
      ).thenAnswer((_) => profileStream.stream);

      final realAuth = AuthController(
        authRepository: authRepository,
        userRepository: userRepository,
        notificationService: notificationService,
      );
      addTearDown(() {
        realAuth.dispose();
        authStream.close();
        profileStream.close();
      });

      final firebaseUser = MockFirebaseUser();
      authStream.add(firebaseUser);
      await tester.pump();
      profileStream.add(
        AppUser(
          id: 'u1',
          name: 'Cliente Antigo',
          email: 'cliente@exemplo.com',
          role: UserRole.client,
          isActive: true,
          profileComplete: false,
        ),
      );
      await tester.pump();
      await tester.pump();

      final businessRepository = MockBusinessRepository();
      when(() => businessRepository.myMembershipsStream(any())).thenAnswer(
        (_) => Stream.value(const [
          BusinessMembership(
            userId: 'u1',
            businessId: 'b1',
            businessName: 'Pet Shop',
            role: BusinessRole.owner,
          ),
        ]),
      );
      final businessContext = BusinessContextController(
        repository: businessRepository,
        authController: realAuth,
      );
      addTearDown(businessContext.dispose);
      await businessContext.selectBusiness('b1');

      final appointmentRepository = MockAppointmentRepository();
      final packageRepository = MockPackageRepository();
      final paymentRepository = MockPaymentRepository();
      when(
        () => appointmentRepository.customerAppointmentsStream('b1', any()),
      ).thenAnswer((_) => Stream.value(const []));
      when(
        () => packageRepository.customerPackagesStream('b1', any()),
      ).thenAnswer((_) => Stream.value(const []));
      when(
        () => paymentRepository.customerPaymentsStream('b1', any()),
      ).thenAnswer((_) => Stream.value(const []));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthController>.value(value: realAuth),
            ChangeNotifierProvider<BusinessContextController>.value(
              value: businessContext,
            ),
            Provider<AppointmentRepository>(
              create: (_) => appointmentRepository,
            ),
            Provider<PackageRepository>(create: (_) => packageRepository),
            Provider<PaymentRepository>(create: (_) => paymentRepository),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const AuthGate()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CompleteProfileScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);

      // O callable grava profileComplete: true; a stream do perfil notifica
      // o controller e o gate troca a tela pelo shell sem navegacao manual.
      profileStream.add(
        AppUser(
          id: 'u1',
          name: 'Cliente Antigo',
          email: 'cliente@exemplo.com',
          role: UserRole.client,
          isActive: true,
          profileComplete: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CompleteProfileScreen), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);
    });
  });
}
