import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/controllers/admin_controller.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/controllers/business_context_controller.dart';
import 'package:meupet_agenda_app/models/app_user.dart';
import 'package:meupet_agenda_app/models/package_model.dart';
import 'package:meupet_agenda_app/models/service_model.dart';
import 'package:meupet_agenda_app/repositories/package_repository.dart';
import 'package:meupet_agenda_app/repositories/service_repository.dart';
import 'package:meupet_agenda_app/repositories/user_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockServiceRepository extends Mock implements ServiceRepository {}

class MockPackageRepository extends Mock implements PackageRepository {}

class MockUserRepository extends Mock implements UserRepository {}

class MockAuthController extends Mock implements AuthController {}

class MockBusinessContextController extends Mock
    implements BusinessContextController {}

void main() {
  late MockServiceRepository serviceRepository;
  late MockPackageRepository packageRepository;
  late MockUserRepository userRepository;
  late MockAuthController authController;
  late MockBusinessContextController businessContext;

  const service = ServiceModel(
    id: 's1',
    name: 'Banho',
    description: 'Banho completo',
    durationMinutes: 60,
    price: 80.0,
  );

  const package = BusinessPackageModel(
    id: 'p1',
    serviceId: 's1',
    name: 'Banho 5x',
    totalCredits: 5,
    price: 150.0,
    validityDays: 30,
  );

  const admin = AppUser(
    id: 'a1',
    name: 'Admin',
    email: 'admin@exemplo.com',
    role: UserRole.admin,
  );

  const superAdmin = AppUser(
    id: 'sa1',
    name: 'Super',
    email: 'super@exemplo.com',
    role: UserRole.superAdmin,
  );

  const client = AppUser(
    id: 'c1',
    name: 'Cliente',
    email: 'cliente@exemplo.com',
    role: UserRole.client,
  );

  setUpAll(() {
    registerFallbackValue(UserRole.client);
  });

  setUp(() {
    serviceRepository = MockServiceRepository();
    packageRepository = MockPackageRepository();
    userRepository = MockUserRepository();
    authController = MockAuthController();
    businessContext = MockBusinessContextController();
    when(() => businessContext.activeBusinessId).thenReturn('b1');
  });

  AdminController buildController() => AdminController(
    serviceRepository: serviceRepository,
    packageRepository: packageRepository,
    userRepository: userRepository,
    authController: authController,
    businessContext: businessContext,
  );

  group('saveService', () {
    test(
      'calls the repository when the profile can manage the catalog',
      () async {
        when(() => authController.profile).thenReturn(admin);
        when(
          () => serviceRepository.saveService('b1', service),
        ).thenAnswer((_) async => 's1');

        final controller = buildController();
        addTearDown(controller.dispose);

        await controller.saveService(service);

        verify(() => serviceRepository.saveService('b1', service)).called(1);
        expect(controller.errorMessage, isNull);
      },
    );

    test('blocks clients without calling the repository', () async {
      when(() => authController.profile).thenReturn(client);

      final controller = buildController();
      addTearDown(controller.dispose);

      await expectLater(
        controller.saveService(service),
        throwsA(isA<StateError>()),
      );

      verifyNever(() => serviceRepository.saveService('b1', service));
      expect(
        controller.errorMessage,
        'Acesso administrativo necessario para esta acao.',
      );
    });

    test('exposes the repository error in errorMessage', () async {
      when(() => authController.profile).thenReturn(admin);
      when(
        () => serviceRepository.saveService('b1', service),
      ).thenThrow(Exception('Falha ao salvar'));

      final controller = buildController();
      addTearDown(controller.dispose);

      await expectLater(
        controller.saveService(service),
        throwsA(isA<Exception>()),
      );

      expect(controller.errorMessage, 'Falha ao salvar');
    });

    test('strips the Bad state prefix from StateError messages', () async {
      when(() => authController.profile).thenReturn(client);

      final controller = buildController();
      addTearDown(controller.dispose);

      await expectLater(
        controller.saveService(service),
        throwsA(isA<StateError>()),
      );

      expect(controller.errorMessage, contains('Acesso administrativo'));
      expect(controller.errorMessage, isNot(contains('Bad state:')));
    });
  });

  group('savePackage', () {
    test('calls the repository for catalog managers', () async {
      when(() => authController.profile).thenReturn(admin);
      when(
        () => packageRepository.savePackage('b1', package),
      ).thenAnswer((_) async => 'p1');

      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.savePackage(package);

      verify(() => packageRepository.savePackage('b1', package)).called(1);
    });

    test('blocks clients', () async {
      when(() => authController.profile).thenReturn(client);

      final controller = buildController();
      addTearDown(controller.dispose);

      await expectLater(
        controller.savePackage(package),
        throwsA(isA<StateError>()),
      );
      verifyNever(() => packageRepository.savePackage('b1', package));
    });
  });

  group('setServiceActive', () {
    test('calls the repository for catalog managers', () async {
      when(() => authController.profile).thenReturn(admin);
      when(
        () => serviceRepository.setActive('b1', 's1', false),
      ).thenAnswer((_) async {});

      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.setServiceActive('s1', false);

      verify(() => serviceRepository.setActive('b1', 's1', false)).called(1);
    });

    test('blocks clients', () async {
      when(() => authController.profile).thenReturn(client);

      final controller = buildController();
      addTearDown(controller.dispose);

      await expectLater(
        controller.setServiceActive('s1', false),
        throwsA(isA<StateError>()),
      );
      verifyNever(() => serviceRepository.setActive('b1', 's1', false));
    });
  });

  group('updateUserRole', () {
    test('super admin can assign any role', () async {
      when(() => authController.profile).thenReturn(superAdmin);
      when(
        () => userRepository.updateUserRole(
          userId: 'u1',
          role: UserRole.superAdmin,
        ),
      ).thenAnswer((_) async {});

      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.updateUserRole(userId: 'u1', role: UserRole.superAdmin);

      verify(
        () => userRepository.updateUserRole(
          userId: 'u1',
          role: UserRole.superAdmin,
        ),
      ).called(1);
    });

    test('admin can assign collaborator and client roles', () async {
      when(() => authController.profile).thenReturn(admin);
      when(
        () =>
            userRepository.updateUserRole(userId: 'u1', role: UserRole.client),
      ).thenAnswer((_) async {});

      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.updateUserRole(userId: 'u1', role: UserRole.client);

      verify(
        () =>
            userRepository.updateUserRole(userId: 'u1', role: UserRole.client),
      ).called(1);
    });

    test('admin cannot assign admin or super admin roles', () async {
      when(() => authController.profile).thenReturn(admin);

      final controller = buildController();
      addTearDown(controller.dispose);

      await expectLater(
        controller.updateUserRole(userId: 'u1', role: UserRole.admin),
        throwsA(isA<StateError>()),
      );

      verifyNever(
        () => userRepository.updateUserRole(userId: 'u1', role: UserRole.admin),
      );
      expect(
        controller.errorMessage,
        'Seu perfil nao pode atribuir esta permissao.',
      );
    });

    test('clients cannot manage users at all', () async {
      when(() => authController.profile).thenReturn(client);

      final controller = buildController();
      addTearDown(controller.dispose);

      await expectLater(
        controller.updateUserRole(userId: 'u1', role: UserRole.client),
        throwsA(isA<StateError>()),
      );
      verifyNever(
        () =>
            userRepository.updateUserRole(userId: 'u1', role: UserRole.client),
      );
    });
  });

  group('isBusy lifecycle', () {
    test('toggles isBusy and notifies during the operation', () async {
      when(() => authController.profile).thenReturn(admin);
      var release = false;
      when(() => serviceRepository.saveService('b1', service)).thenAnswer(
        (_) async =>
            release ? 's1' : Future<String>.delayed(Duration.zero, () => 's1'),
      );

      final controller = buildController();
      addTearDown(controller.dispose);

      var notifiedDuring = false;
      controller.addListener(() {
        if (controller.isBusy) {
          notifiedDuring = true;
        }
      });

      final future = controller.saveService(service);
      expect(controller.isBusy, isTrue);
      release = true;
      await future;
      expect(controller.isBusy, isFalse);
      expect(notifiedDuring, isTrue);
    });
  });
}
