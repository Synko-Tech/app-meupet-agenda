import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/controllers/auth_controller.dart';
import 'package:meupet_agenda_app/controllers/business_context_controller.dart';
import 'package:meupet_agenda_app/models/business_membership.dart';
import 'package:meupet_agenda_app/repositories/business_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockBusinessRepository extends Mock implements BusinessRepository {}

class MockAuthController extends Mock implements AuthController {}

class MockFirebaseUser extends Mock implements User {
  MockFirebaseUser() {
    when(() => uid).thenReturn('u1');
  }
}

void main() {
  late MockBusinessRepository repository;
  late MockAuthController authController;

  BusinessMembership membership(
    String businessId, {
    BusinessRole role = BusinessRole.owner,
    bool isActive = true,
  }) {
    return BusinessMembership(
      userId: 'u1',
      businessId: businessId,
      businessName: 'Loja $businessId',
      role: role,
      isActive: isActive,
    );
  }

  setUp(() {
    repository = MockBusinessRepository();
    authController = MockAuthController();
    when(() => authController.firebaseUser).thenReturn(null);
    when(() => authController.addListener(any())).thenReturn(null);
    when(() => authController.removeListener(any())).thenReturn(null);
  });

  BusinessContextController buildController() {
    final controller = BusinessContextController(
      repository: repository,
      authController: authController,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  group('membership loading', () {
    test('starts empty when the user is signed out', () {
      final controller = buildController();

      expect(controller.memberships, isEmpty);
      expect(controller.activeBusinessId, isNull);
      expect(controller.isLoading, isFalse);
    });

    test('loads memberships from the user projection stream', () async {
      final controller = StreamController<List<BusinessMembership>>();
      addTearDown(controller.close);
      final firebaseUser = MockFirebaseUser();
      when(() => authController.firebaseUser).thenReturn(firebaseUser);
      when(
        () => repository.myMembershipsStream('u1'),
      ).thenAnswer((_) => controller.stream);

      final businessContext = buildController();
      controller.add([
        membership('b1'),
        membership('b2', role: BusinessRole.admin),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(businessContext.memberships.length, 2);
      expect(businessContext.isLoading, isFalse);
    });
  });

  group('selectBusiness', () {
    test('selects a business the user belongs to', () async {
      final controller = StreamController<List<BusinessMembership>>();
      addTearDown(controller.close);
      final firebaseUser = MockFirebaseUser();
      when(() => authController.firebaseUser).thenReturn(firebaseUser);
      when(
        () => repository.myMembershipsStream('u1'),
      ).thenAnswer((_) => controller.stream);

      final businessContext = buildController();
      controller.add([membership('b1')]);
      await Future<void>.delayed(Duration.zero);

      await businessContext.selectBusiness('b1');

      expect(businessContext.activeBusinessId, 'b1');
      expect(businessContext.activeMembership?.role, BusinessRole.owner);
      expect(businessContext.hasActiveBusiness, isTrue);
    });

    test('ignores memberships that are inactive or unknown', () async {
      final controller = StreamController<List<BusinessMembership>>();
      addTearDown(controller.close);
      final firebaseUser = MockFirebaseUser();
      when(() => authController.firebaseUser).thenReturn(firebaseUser);
      when(
        () => repository.myMembershipsStream('u1'),
      ).thenAnswer((_) => controller.stream);

      final businessContext = buildController();
      controller.add([membership('b1', isActive: false)]);
      await Future<void>.delayed(Duration.zero);

      await businessContext.selectBusiness('b1');

      expect(businessContext.activeBusinessId, 'b1');
      expect(businessContext.activeMembership, isNull);
    });

    test('clearBusiness resets the active context', () async {
      final controller = StreamController<List<BusinessMembership>>();
      addTearDown(controller.close);
      final firebaseUser = MockFirebaseUser();
      when(() => authController.firebaseUser).thenReturn(firebaseUser);
      when(
        () => repository.myMembershipsStream('u1'),
      ).thenAnswer((_) => controller.stream);

      final businessContext = buildController();
      controller.add([membership('b1')]);
      await Future<void>.delayed(Duration.zero);
      await businessContext.selectBusiness('b1');

      businessContext.clearBusiness();

      expect(businessContext.activeBusinessId, isNull);
      expect(businessContext.activeMembership, isNull);
    });

    test(
      'membership removed from the stream clears the active business',
      () async {
        final controller = StreamController<List<BusinessMembership>>();
        addTearDown(controller.close);
        final firebaseUser = MockFirebaseUser();
        when(() => authController.firebaseUser).thenReturn(firebaseUser);
        when(
          () => repository.myMembershipsStream('u1'),
        ).thenAnswer((_) => controller.stream);

        final businessContext = buildController();
        controller.add([membership('b1')]);
        await Future<void>.delayed(Duration.zero);
        await businessContext.selectBusiness('b1');

        controller.add(const []);
        await Future<void>.delayed(Duration.zero);

        expect(businessContext.activeBusinessId, isNull);
        expect(businessContext.activeMembership, isNull);
      },
    );
  });

  group('createBusiness', () {
    test('forwards the name and selects the created business', () async {
      when(
        () => repository.createBusiness(
          name: any(named: 'name'),
          description: any(named: 'description'),
        ),
      ).thenAnswer((_) async => const CreatedBusiness(businessId: 'b9'));

      final controller = StreamController<List<BusinessMembership>>();
      addTearDown(controller.close);
      final firebaseUser = MockFirebaseUser();
      when(() => authController.firebaseUser).thenReturn(firebaseUser);
      when(
        () => repository.myMembershipsStream('u1'),
      ).thenAnswer((_) => controller.stream);

      final businessContext = buildController();
      controller.add([membership('b9')]);
      await Future<void>.delayed(Duration.zero);

      await businessContext.createBusiness(name: 'Nova Loja');

      verify(
        () => repository.createBusiness(
          name: 'Nova Loja',
          description: any(named: 'description', that: isNull),
        ),
      ).called(1);
      expect(businessContext.activeBusinessId, 'b9');
      expect(businessContext.errorMessage, isNull);
    });

    test('maps repository errors to a friendly message', () async {
      when(
        () => repository.createBusiness(
          name: any(named: 'name'),
          description: any(named: 'description'),
        ),
      ).thenThrow(StateError('Resposta invalida do servidor.'));

      final businessContext = buildController();

      await expectLater(
        businessContext.createBusiness(name: 'Nova Loja'),
        throwsA(isA<StateError>()),
      );
      expect(businessContext.errorMessage, 'Resposta invalida do servidor.');
      expect(businessContext.activeBusinessId, isNull);
    });
  });

  group('joinBusiness', () {
    test('calls the repository and selects the joined business', () async {
      when(
        () => repository.joinBusiness(businessId: 'b1'),
      ).thenAnswer((_) async {});

      final controller = StreamController<List<BusinessMembership>>();
      addTearDown(controller.close);
      final firebaseUser = MockFirebaseUser();
      when(() => authController.firebaseUser).thenReturn(firebaseUser);
      when(
        () => repository.myMembershipsStream('u1'),
      ).thenAnswer((_) => controller.stream);

      final businessContext = buildController();
      controller.add([membership('b1', role: BusinessRole.client)]);
      await Future<void>.delayed(Duration.zero);

      await businessContext.joinBusiness('b1');

      verify(() => repository.joinBusiness(businessId: 'b1')).called(1);
      expect(businessContext.activeBusinessId, 'b1');
      expect(businessContext.errorMessage, isNull);
    });

    test('maps repository errors to a friendly message', () async {
      when(
        () => repository.joinBusiness(businessId: 'b1'),
      ).thenThrow(StateError('Resposta invalida do servidor.'));

      final businessContext = buildController();

      await expectLater(
        businessContext.joinBusiness('b1'),
        throwsA(isA<StateError>()),
      );
      expect(businessContext.errorMessage, 'Resposta invalida do servidor.');
      expect(businessContext.activeBusinessId, isNull);
    });
  });
}
