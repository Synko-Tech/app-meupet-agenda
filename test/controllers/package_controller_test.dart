import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/controllers/business_context_controller.dart';
import 'package:meupet_agenda_app/controllers/package_controller.dart';
import 'package:meupet_agenda_app/models/package_model.dart';
import 'package:meupet_agenda_app/repositories/package_repository.dart';
import 'package:meupet_agenda_app/services/checkout_launcher.dart';
import 'package:mocktail/mocktail.dart';

class MockPackageRepository extends Mock implements PackageRepository {}

class MockBusinessContextController extends Mock
    implements BusinessContextController {}

void main() {
  late MockPackageRepository packageRepository;
  late MockBusinessContextController businessContext;
  late FakeCheckoutLauncher launcher;

  const package = BusinessPackageModel(
    id: 'p1',
    serviceId: 's1',
    name: 'Banho 5x',
    totalCredits: 5,
    price: 150.0,
    validityDays: 30,
  );

  final checkout = MercadoPagoCheckout(
    paymentId: 'pay-1',
    preferenceId: 'pref-1',
    initPoint: Uri.parse('https://checkout.mercadopago.com.br/abc'),
  );

  setUp(() {
    packageRepository = MockPackageRepository();
    businessContext = MockBusinessContextController();
    when(() => businessContext.activeBusinessId).thenReturn('b1');
    launcher = FakeCheckoutLauncher();
  });

  PackageController buildController() => PackageController(
    packageRepository: packageRepository,
    businessContext: businessContext,
    checkoutLauncher: launcher,
  );

  group('purchasePackage', () {
    test('forwards the package id and method to the repository', () async {
      when(
        () => packageRepository.purchasePackage(
          businessId: any(named: 'businessId'),
          packageId: any(named: 'packageId'),
          method: any(named: 'method'),
        ),
      ).thenAnswer((_) async => 'pay-1');

      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.purchasePackage(package: package, method: 'PIX');

      verify(
        () => packageRepository.purchasePackage(
          businessId: 'b1',
          packageId: 'p1',
          method: 'PIX',
        ),
      ).called(1);
      expect(controller.errorMessage, isNull);
    });

    test('forwards a null method when omitted', () async {
      when(
        () => packageRepository.purchasePackage(
          businessId: any(named: 'businessId'),
          packageId: any(named: 'packageId'),
          method: any(named: 'method'),
        ),
      ).thenAnswer((_) async => 'pay-2');

      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.purchasePackage(package: package);

      verify(
        () => packageRepository.purchasePackage(
          businessId: 'b1',
          packageId: 'p1',
          method: any(named: 'method', that: isNull),
        ),
      ).called(1);
    });

    test('maps the error to a friendly message', () async {
      when(
        () => packageRepository.purchasePackage(
          businessId: any(named: 'businessId'),
          packageId: any(named: 'packageId'),
          method: any(named: 'method'),
        ),
      ).thenThrow(StateError('Resposta invalida do servidor.'));

      final controller = buildController();
      addTearDown(controller.dispose);

      await expectLater(
        controller.purchasePackage(package: package),
        throwsA(isA<StateError>()),
      );
      expect(controller.errorMessage, 'Resposta invalida do servidor.');
    });
  });

  group('checkoutWithMercadoPago', () {
    test('creates the checkout and opens the init point', () async {
      when(
        () => packageRepository.createMercadoPagoCheckout(
          businessId: any(named: 'businessId'),
          packageId: any(named: 'packageId'),
        ),
      ).thenAnswer((_) async => checkout);

      final controller = buildController();
      addTearDown(controller.dispose);

      final result = await controller.checkoutWithMercadoPago(package);

      verify(
        () => packageRepository.createMercadoPagoCheckout(
          businessId: 'b1',
          packageId: 'p1',
        ),
      ).called(1);
      expect(result.paymentId, 'pay-1');
      expect(launcher.opened, [checkout.initPoint]);
      expect(controller.errorMessage, isNull);
    });

    test(
      'throws a friendly message when the browser cannot be opened',
      () async {
        when(
          () => packageRepository.createMercadoPagoCheckout(
            businessId: any(named: 'businessId'),
            packageId: any(named: 'packageId'),
          ),
        ).thenAnswer((_) async => checkout);
        launcher.shouldOpen = false;

        final controller = buildController();
        addTearDown(controller.dispose);

        await expectLater(
          controller.checkoutWithMercadoPago(package),
          throwsA(isA<StateError>()),
        );
        expect(controller.errorMessage, contains('Mercado Pago'));
        expect(launcher.opened, [checkout.initPoint]);
      },
    );

    test('rethrows a repository failure and exposes the message', () async {
      when(
        () => packageRepository.createMercadoPagoCheckout(
          businessId: any(named: 'businessId'),
          packageId: any(named: 'packageId'),
        ),
      ).thenThrow(StateError('Resposta invalida do servidor.'));

      final controller = buildController();
      addTearDown(controller.dispose);

      await expectLater(
        controller.checkoutWithMercadoPago(package),
        throwsA(isA<StateError>()),
      );
      expect(controller.errorMessage, 'Resposta invalida do servidor.');
      expect(launcher.opened, isEmpty);
    });
  });

  group('isBusy lifecycle', () {
    test('is true while the purchase runs and false afterwards', () async {
      var release = false;
      when(
        () => packageRepository.purchasePackage(
          businessId: any(named: 'businessId'),
          packageId: any(named: 'packageId'),
          method: any(named: 'method'),
        ),
      ).thenAnswer(
        (_) async => release
            ? 'pay-3'
            : Future<String>.delayed(Duration.zero, () => 'pay-3'),
      );

      final controller = buildController();
      addTearDown(controller.dispose);

      final future = controller.purchasePackage(package: package);
      expect(controller.isBusy, isTrue);
      release = true;
      await future;
      expect(controller.isBusy, isFalse);
    });

    test('is true while the checkout runs and false afterwards', () async {
      var release = false;
      when(
        () => packageRepository.createMercadoPagoCheckout(
          businessId: any(named: 'businessId'),
          packageId: any(named: 'packageId'),
        ),
      ).thenAnswer(
        (_) async => release
            ? checkout
            : Future<MercadoPagoCheckout>.delayed(
                Duration.zero,
                () => checkout,
              ),
      );

      final controller = buildController();
      addTearDown(controller.dispose);

      final future = controller.checkoutWithMercadoPago(package);
      expect(controller.isBusy, isTrue);
      release = true;
      await future;
      expect(controller.isBusy, isFalse);
    });
  });
}
