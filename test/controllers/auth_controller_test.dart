import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/models/app_user.dart';
import 'package:meupet_agenda_app/models/postal_address.dart';
import 'package:meupet_agenda_app/repositories/auth_repository.dart';
import 'package:meupet_agenda_app/repositories/user_repository.dart';
import 'package:meupet_agenda_app/services/notification_service.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockUserRepository extends Mock implements UserRepository {}

class MockNotificationService extends Mock implements NotificationService {}

class MockFirebaseUser extends Mock implements User {}

void main() {
  late MockAuthRepository authRepository;
  late MockUserRepository userRepository;
  late MockNotificationService notificationService;

  setUpAll(() {
    registerFallbackValue(
      AppUser(
        id: 'fallback',
        name: 'Fallback',
        email: 'fallback@exemplo.com',
        role: UserRole.client,
      ),
    );
    registerFallbackValue(
      PostalAddress(
        postalCode: '01310100',
        street: 'Avenida Paulista',
        number: '1000',
        neighborhood: 'Bela Vista',
        city: 'Sao Paulo',
        state: 'SP',
      ),
    );
  });

  setUp(() {
    authRepository = MockAuthRepository();
    userRepository = MockUserRepository();
    notificationService = MockNotificationService();
    when(
      () => authRepository.authStateChanges(),
    ).thenAnswer((_) => const Stream.empty());
  });

  group('isAuthenticatedAndActive', () {
    test(
      'is false when the profile is inactive (blocked at the gate)',
      () async {
        final authStream = StreamController<User?>.broadcast();
        when(
          () => authRepository.authStateChanges(),
        ).thenAnswer((_) => authStream.stream);
        final inactiveClient = AppUser(
          id: 'u1',
          name: 'Cliente',
          email: 'cliente@exemplo.com',
          role: UserRole.client,
          isActive: false,
        );
        when(
          () => userRepository.profileStream(any()),
        ).thenAnswer((_) => Stream.value(inactiveClient));

        final controller = AuthController(
          authRepository: authRepository,
          userRepository: userRepository,
          notificationService: notificationService,
        );
        addTearDown(() {
          controller.dispose();
          authStream.close();
        });

        final firebaseUser = MockFirebaseUser();
        when(() => firebaseUser.uid).thenReturn('u1');
        authStream.add(firebaseUser);
        await pumpEventQueue();
        await pumpEventQueue();

        expect(controller.profile, isNotNull);
        expect(controller.profile?.isActive, isFalse);
        expect(controller.isAuthenticated, isFalse);
        expect(controller.isAuthenticatedAndActive, isFalse);
      },
    );

    test('is true when the profile is active', () async {
      final authStream = StreamController<User?>.broadcast();
      when(
        () => authRepository.authStateChanges(),
      ).thenAnswer((_) => authStream.stream);
      final activeClient = AppUser(
        id: 'u1',
        name: 'Cliente',
        email: 'cliente@exemplo.com',
        role: UserRole.client,
        isActive: true,
      );
      when(
        () => userRepository.profileStream(any()),
      ).thenAnswer((_) => Stream.value(activeClient));

      final controller = AuthController(
        authRepository: authRepository,
        userRepository: userRepository,
        notificationService: notificationService,
      );
      addTearDown(() {
        controller.dispose();
        authStream.close();
      });

      final firebaseUser = MockFirebaseUser();
      when(() => firebaseUser.uid).thenReturn('u1');
      authStream.add(firebaseUser);
      await pumpEventQueue();
      await pumpEventQueue();

      expect(controller.profile?.isActive, isTrue);
      expect(controller.isAuthenticated, isTrue);
      expect(controller.isAuthenticatedAndActive, isTrue);
    });
  });

  group('registerClient', () {
    test('forwards the CPF and structured address to the repository', () async {
      when(
        () => authRepository.registerClient(
          name: any(named: 'name'),
          email: any(named: 'email'),
          password: any(named: 'password'),
          phone: any(named: 'phone'),
          cpf: any(named: 'cpf'),
          address: any(named: 'address'),
        ),
      ).thenAnswer((_) async {});

      final controller = AuthController(
        authRepository: authRepository,
        userRepository: userRepository,
        notificationService: notificationService,
      );
      addTearDown(controller.dispose);

      await controller.registerClient(
        name: 'Cliente',
        email: 'cliente@exemplo.com',
        password: '123456',
        phone: '11999999999',
        cpf: '52998224725',
        address: PostalAddress(
          postalCode: '01310100',
          street: 'Avenida Paulista',
          number: '1000',
          neighborhood: 'Bela Vista',
          city: 'Sao Paulo',
          state: 'SP',
        ),
      );

      verify(
        () => authRepository.registerClient(
          name: 'Cliente',
          email: 'cliente@exemplo.com',
          password: '123456',
          phone: '11999999999',
          cpf: '52998224725',
          address: any(
            named: 'address',
            that: isA<PostalAddress>().having(
              (address) => address.postalCode,
              'postalCode',
              '01310100',
            ),
          ),
        ),
      ).called(1);
    });

    test('maps a duplicate CPF to a friendly message', () async {
      when(
        () => authRepository.registerClient(
          name: any(named: 'name'),
          email: any(named: 'email'),
          password: any(named: 'password'),
          phone: any(named: 'phone'),
          cpf: any(named: 'cpf'),
          address: any(named: 'address'),
        ),
      ).thenThrow(
        FirebaseFunctionsException(
          code: 'already-exists',
          message: 'CPF ja cadastrado para outro usuario.',
        ),
      );

      final controller = AuthController(
        authRepository: authRepository,
        userRepository: userRepository,
        notificationService: notificationService,
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.registerClient(
          name: 'Cliente',
          email: 'cliente@exemplo.com',
          password: '123456',
          cpf: '52998224725',
          address: PostalAddress(
            postalCode: '01310100',
            street: 'Avenida Paulista',
            number: '1000',
            neighborhood: 'Bela Vista',
            city: 'Sao Paulo',
            state: 'SP',
          ),
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );

      expect(controller.errorMessage, 'CPF ja cadastrado para outro usuario.');
      expect(controller.isBusy, isFalse);
    });
  });

  group('registerBusiness', () {
    test('forwards business data and structured address to the repository', () async {
      when(
        () => authRepository.registerBusiness(
          name: any(named: 'name'),
          email: any(named: 'email'),
          password: any(named: 'password'),
          phone: any(named: 'phone'),
          cpf: any(named: 'cpf'),
          cnpj: any(named: 'cnpj'),
          businessName: any(named: 'businessName'),
          businessLegalName: any(named: 'businessLegalName'),
          businessPhone: any(named: 'businessPhone'),
          businessDescription: any(named: 'businessDescription'),
          address: any(named: 'address'),
        ),
      ).thenAnswer(
        (_) async => CreatedBusinessAccount(businessId: 'b1'),
      );

      final controller = AuthController(
        authRepository: authRepository,
        userRepository: userRepository,
        notificationService: notificationService,
      );
      addTearDown(controller.dispose);

      await controller.registerBusiness(
        name: 'Fulano de Tal',
        email: 'dono@pet.com',
        password: '123456',
        phone: '11999999999',
        cpf: '52998224725',
        cnpj: '11222333000181',
        businessName: 'Pet Shop Central',
        businessLegalName: 'Central Pet Comercio LTDA',
        businessPhone: '1140028922',
        businessDescription: 'Banho e tosa',
        address: PostalAddress(
          postalCode: '01310100',
          street: 'Avenida Paulista',
          number: '1000',
          neighborhood: 'Bela Vista',
          city: 'Sao Paulo',
          state: 'SP',
        ),
      );

      verify(
        () => authRepository.registerBusiness(
          name: 'Fulano de Tal',
          email: 'dono@pet.com',
          password: '123456',
          phone: '11999999999',
          cpf: '52998224725',
          cnpj: '11222333000181',
          businessName: 'Pet Shop Central',
          businessLegalName: 'Central Pet Comercio LTDA',
          businessPhone: '1140028922',
          businessDescription: 'Banho e tosa',
          address: any(
            named: 'address',
            that: isA<PostalAddress>().having(
              (address) => address.postalCode,
              'postalCode',
              '01310100',
            ),
          ),
        ),
      ).called(1);
    });

    test('maps a duplicate CNPJ to a friendly message', () async {
      when(
        () => authRepository.registerBusiness(
          name: any(named: 'name'),
          email: any(named: 'email'),
          password: any(named: 'password'),
          phone: any(named: 'phone'),
          cpf: any(named: 'cpf'),
          cnpj: any(named: 'cnpj'),
          businessName: any(named: 'businessName'),
          businessLegalName: any(named: 'businessLegalName'),
          businessPhone: any(named: 'businessPhone'),
          businessDescription: any(named: 'businessDescription'),
          address: any(named: 'address'),
        ),
      ).thenThrow(
        FirebaseFunctionsException(
          code: 'already-exists',
          message: 'CNPJ ja cadastrado para outra loja.',
        ),
      );

      final controller = AuthController(
        authRepository: authRepository,
        userRepository: userRepository,
        notificationService: notificationService,
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.registerBusiness(
          name: 'Fulano de Tal',
          email: 'dono@pet.com',
          password: '123456',
          cpf: '52998224725',
          cnpj: '11222333000181',
          businessName: 'Pet Shop Central',
          address: PostalAddress(
            postalCode: '01310100',
            street: 'Avenida Paulista',
            number: '1000',
            neighborhood: 'Bela Vista',
            city: 'Sao Paulo',
            state: 'SP',
          ),
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );

      expect(controller.errorMessage, 'CNPJ ja cadastrado para outra loja.');
      expect(controller.isBusy, isFalse);
    });
  });

  group('completeOwnProfile', () {
    test('forwards name, phone, CPF and address to the repository', () async {
      when(
        () => authRepository.completeOwnProfile(
          name: any(named: 'name'),
          phone: any(named: 'phone'),
          cpf: any(named: 'cpf'),
          address: any(named: 'address'),
        ),
      ).thenAnswer((_) async {});

      final controller = AuthController(
        authRepository: authRepository,
        userRepository: userRepository,
        notificationService: notificationService,
      );
      addTearDown(controller.dispose);

      await controller.completeOwnProfile(
        name: 'Cliente Antigo',
        phone: '11999999999',
        cpf: '52998224725',
        address: PostalAddress(
          postalCode: '01310100',
          street: 'Avenida Paulista',
          number: '1000',
          neighborhood: 'Bela Vista',
          city: 'Sao Paulo',
          state: 'SP',
        ),
      );

      verify(
        () => authRepository.completeOwnProfile(
          name: 'Cliente Antigo',
          phone: '11999999999',
          cpf: '52998224725',
          address: any(
            named: 'address',
            that: isA<PostalAddress>().having(
              (address) => address.postalCode,
              'postalCode',
              '01310100',
            ),
          ),
        ),
      ).called(1);
    });

    test('maps a duplicate CPF to a friendly message', () async {
      when(
        () => authRepository.completeOwnProfile(
          name: any(named: 'name'),
          phone: any(named: 'phone'),
          cpf: any(named: 'cpf'),
          address: any(named: 'address'),
        ),
      ).thenThrow(
        FirebaseFunctionsException(
          code: 'already-exists',
          message: 'CPF ja cadastrado para outro usuario.',
        ),
      );

      final controller = AuthController(
        authRepository: authRepository,
        userRepository: userRepository,
        notificationService: notificationService,
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.completeOwnProfile(
          name: 'Cliente Antigo',
          cpf: '52998224725',
          address: PostalAddress(
            postalCode: '01310100',
            street: 'Avenida Paulista',
            number: '1000',
            neighborhood: 'Bela Vista',
            city: 'Sao Paulo',
            state: 'SP',
          ),
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );

      expect(controller.errorMessage, 'CPF ja cadastrado para outro usuario.');
      expect(controller.isBusy, isFalse);
    });
  });

  group('signOut', () {
    test('clears a blank phone when updating the profile', () async {
      final authStream = StreamController<User?>.broadcast();
      when(
        () => authRepository.authStateChanges(),
      ).thenAnswer((_) => authStream.stream);
      final clientWithPhone = AppUser(
        id: 'u1',
        name: 'Cliente',
        email: 'cliente@exemplo.com',
        role: UserRole.client,
        isActive: true,
        phone: '11999999999',
      );
      when(
        () => userRepository.profileStream(any()),
      ).thenAnswer((_) => Stream.value(clientWithPhone));
      when(() => userRepository.updateProfile(any())).thenAnswer((_) async {});

      final controller = AuthController(
        authRepository: authRepository,
        userRepository: userRepository,
        notificationService: notificationService,
      );
      addTearDown(() {
        controller.dispose();
        authStream.close();
      });

      final firebaseUser = MockFirebaseUser();
      when(() => firebaseUser.uid).thenReturn('u1');
      authStream.add(firebaseUser);
      await pumpEventQueue();
      await pumpEventQueue();

      await controller.updateProfile(name: 'Cliente', phone: '   ');

      verify(
        () => userRepository.updateProfile(
          any(
            that: isA<AppUser>().having((user) => user.phone, 'phone', isNull),
          ),
        ),
      ).called(1);
    });

    test(
      'calls authRepository.signOut even when FCM token removal throws',
      () async {
        final firebaseUser = MockFirebaseUser();
        when(() => firebaseUser.uid).thenReturn('u1');
        when(
          () => notificationService.removeCurrentToken('u1'),
        ).thenThrow(Exception('FCM indisponivel'));
        when(() => authRepository.signOut()).thenAnswer((_) async {});

        final controller = AuthController(
          authRepository: authRepository,
          userRepository: userRepository,
          notificationService: notificationService,
        );
        addTearDown(controller.dispose);
        controller.firebaseUser = firebaseUser;

        await controller.signOut();

        verify(() => notificationService.removeCurrentToken('u1')).called(1);
        verify(() => authRepository.signOut()).called(1);
        expect(controller.errorMessage, isNull);
      },
    );

    test(
      'calls authRepository.signOut when FCM token removal succeeds',
      () async {
        final firebaseUser = MockFirebaseUser();
        when(() => firebaseUser.uid).thenReturn('u1');
        when(
          () => notificationService.removeCurrentToken('u1'),
        ).thenAnswer((_) async {});
        when(() => authRepository.signOut()).thenAnswer((_) async {});

        final controller = AuthController(
          authRepository: authRepository,
          userRepository: userRepository,
          notificationService: notificationService,
        );
        addTearDown(controller.dispose);
        controller.firebaseUser = firebaseUser;

        await controller.signOut();

        verify(() => notificationService.removeCurrentToken('u1')).called(1);
        verify(() => authRepository.signOut()).called(1);
      },
    );

    test('skips FCM cleanup when not signed in but still signs out', () async {
      when(() => authRepository.signOut()).thenAnswer((_) async {});

      final controller = AuthController(
        authRepository: authRepository,
        userRepository: userRepository,
        notificationService: notificationService,
      );
      addTearDown(controller.dispose);

      await controller.signOut();

      verifyNever(() => notificationService.removeCurrentToken(any()));
      verify(() => authRepository.signOut()).called(1);
    });
  });

  group('signIn error mapping', () {
    Future<void> expectFriendlyMessage(String code) async {
      when(
        () => authRepository.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(FirebaseAuthException(code: code));

      final controller = AuthController(
        authRepository: authRepository,
        userRepository: userRepository,
        notificationService: notificationService,
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.signIn(email: 'cliente@exemplo.com', password: 'x'),
        throwsA(isA<FirebaseAuthException>()),
      );

      expect(controller.errorMessage, 'E-mail ou senha invalidos.');
      expect(controller.isBusy, isFalse);
    }

    test(
      'invalid-login-credentials maps to the friendly credentials message',
      () => expectFriendlyMessage('invalid-login-credentials'),
    );

    test(
      'invalid-credential maps to the friendly credentials message',
      () => expectFriendlyMessage('invalid-credential'),
    );

    test(
      'user-not-found and wrong-password map to the friendly message',
      () async {
        await expectFriendlyMessage('user-not-found');
        await expectFriendlyMessage('wrong-password');
      },
    );
  });
}
