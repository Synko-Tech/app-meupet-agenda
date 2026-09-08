import 'package:flutter/foundation.dart';

import '../models/package_model.dart';
import '../repositories/package_repository.dart';
import '../services/checkout_launcher.dart';
import '../services/function_error.dart';
import 'business_context_controller.dart';

class PackageController extends ChangeNotifier {
  PackageController({
    required PackageRepository packageRepository,
    required BusinessContextController businessContext,
    CheckoutLauncher? checkoutLauncher,
  }) : _packageRepository = packageRepository,
       _businessContext = businessContext,
       _checkoutLauncher = checkoutLauncher ?? const UrlLauncherCheckout();

  final PackageRepository _packageRepository;
  final BusinessContextController _businessContext;
  final CheckoutLauncher _checkoutLauncher;

  bool isBusy = false;
  String? errorMessage;

  String get _businessId {
    final businessId = _businessContext.activeBusinessId;
    if (businessId == null) {
      throw StateError('Nenhuma loja ativa.');
    }
    return businessId;
  }

  /// Legacy purchase path (used when no gateway flow applies).
  Future<void> purchasePackage({
    required BusinessPackageModel package,
    String? method,
  }) {
    return _run(
      () => _packageRepository.purchasePackage(
        businessId: _businessId,
        packageId: package.id,
        method: method,
      ),
    );
  }

  /// Starts a Mercado Pago Checkout Pro flow and opens the init point in the
  /// external browser. Returning to the app never marks the payment as
  /// completed — only the official webhook changes the status.
  ///
  /// Returns the started checkout on success; throws with a friendly message
  /// when the preference cannot be created or the link cannot be opened.
  Future<MercadoPagoCheckout> checkoutWithMercadoPago(
    BusinessPackageModel package,
  ) {
    return _runCheckout(() async {
      final checkout = await _packageRepository.createMercadoPagoCheckout(
        businessId: _businessId,
        packageId: package.id,
      );
      final opened = await _checkoutLauncher.open(checkout.initPoint);
      if (!opened) {
        throw StateError(
          'Conclua o pagamento no Mercado Pago: abra o link abaixo do app.',
        );
      }
      return checkout;
    });
  }

  Future<T> _runCheckout<T>(Future<T> Function() action) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      return await action();
    } catch (error) {
      errorMessage = friendlyErrorMessage(error);
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      errorMessage = friendlyErrorMessage(error);
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }
}
