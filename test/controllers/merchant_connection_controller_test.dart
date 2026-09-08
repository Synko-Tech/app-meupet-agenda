import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/controllers/business_context_controller.dart';
import 'package:meupet_agenda_app/controllers/merchant_connection_controller.dart';
import 'package:meupet_agenda_app/models/merchant_connection_summary.dart';
import 'package:meupet_agenda_app/repositories/merchant_connection_repository.dart';
import 'package:meupet_agenda_app/services/checkout_launcher.dart';
import 'package:mocktail/mocktail.dart';

class MockMerchantConnectionRepository extends Mock
    implements MerchantConnectionRepository {}

class MockBusinessContextController extends Mock
    implements BusinessContextController {}

class MockCheckoutLauncher extends Mock implements CheckoutLauncher {}

void main() {
  late MockMerchantConnectionRepository repository;
  late MockBusinessContextController businessContext;
  late MockCheckoutLauncher launcher;

  setUpAll(() {
    registerFallbackValue(
      Uri.parse('https://auth.mercadopago.com/authorization?state=abc'),
    );
  });

  setUp(() {
    repository = MockMerchantConnectionRepository();
    businessContext = MockBusinessContextController();
    launcher = MockCheckoutLauncher();
    when(() => businessContext.activeBusinessId).thenReturn('b1');
    when(() => repository.merchantSummaryStream('b1')).thenAnswer(
      (_) => const Stream.empty(),
    );
  });

  MerchantConnectionController buildController() {
    final controller = MerchantConnectionController(
      repository: repository,
      businessContext: businessContext,
      launcher: launcher,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  group('MerchantConnectionController', () {
    test('subscribes to the summary stream of the active business', () async {
      final stream = StreamController<MerchantConnectionSummary>();
      addTearDown(stream.close);
      when(() => repository.merchantSummaryStream('b1')).thenAnswer(
        (_) => stream.stream,
      );

      final controller = buildController();
      stream.add(
        MerchantConnectionSummary(
          status: MerchantConnectionStatus.connected,
          collectorId: 'seller-42',
          liveMode: true,
          connectedAt: DateTime(2026, 8, 1),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.summary.isConnected, isTrue);
      expect(controller.summary.collectorId, 'seller-42');
    });

    test('connect opens the authorization URL in the browser', () async {
      when(() => repository.startConnection('b1')).thenAnswer(
        (_) async => MerchantOAuthStart(
          authorizationUrl: Uri.parse(
            'https://auth.mercadopago.com/authorization?state=abc',
          ),
        ),
      );
      when(() => launcher.open(any())).thenAnswer((_) async => true);

      final controller = buildController();

      await controller.connect();

      verify(() => launcher.open(any())).called(1);
      expect(controller.errorMessage, isNull);
    });

    test('connect surfaces an error when the browser cannot open', () async {
      when(() => repository.startConnection('b1')).thenAnswer(
        (_) async => MerchantOAuthStart(
          authorizationUrl: Uri.parse(
            'https://auth.mercadopago.com/authorization?state=abc',
          ),
        ),
      );
      when(() => launcher.open(any())).thenAnswer((_) async => false);

      final controller = buildController();

      await expectLater(controller.connect(), throwsA(isA<StateError>()));
      expect(controller.errorMessage, isNotNull);
    });

    test('connect maps repository errors to a friendly message', () async {
      when(() => repository.startConnection('b1'))
          .thenThrow(StateError('Resposta invalida do servidor.'));

      final controller = buildController();

      await expectLater(controller.connect(), throwsA(isA<StateError>()));
      expect(controller.errorMessage, 'Resposta invalida do servidor.');
    });

    test('refresh and disconnect forward to the repository', () async {
      when(() => repository.refreshConnection('b1'))
          .thenAnswer((_) async => true);
      when(() => repository.disconnectConnection('b1'))
          .thenAnswer((_) async {});

      final controller = buildController();

      await controller.refresh();
      expect(controller.errorMessage, isNull);
      await controller.disconnect();
      expect(controller.errorMessage, isNull);

      verify(() => repository.refreshConnection('b1')).called(1);
      verify(() => repository.disconnectConnection('b1')).called(1);
    });
  });
}
