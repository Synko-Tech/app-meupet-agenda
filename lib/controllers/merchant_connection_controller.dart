import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/merchant_connection_summary.dart';
import '../repositories/merchant_connection_repository.dart';
import '../services/checkout_launcher.dart';
import '../services/function_error.dart';
import 'business_context_controller.dart';

/// Controla a conexão Mercado Pago da loja ativa (card de recebimentos).
/// Somente o owner conecta/desconecta — o backend valida o membership.
class MerchantConnectionController extends ChangeNotifier {
  MerchantConnectionController({
    required MerchantConnectionRepository repository,
    required BusinessContextController businessContext,
    CheckoutLauncher? launcher,
  }) : _repository = repository,
       _businessContext = businessContext,
       _launcher = launcher ?? const UrlLauncherCheckout() {
    _businessContext.addListener(_handleBusinessChanged);
    _handleBusinessChanged();
  }

  final MerchantConnectionRepository _repository;
  final BusinessContextController _businessContext;
  final CheckoutLauncher _launcher;

  StreamSubscription<MerchantConnectionSummary>? _summarySubscription;

  MerchantConnectionSummary summary = MerchantConnectionSummary.disconnected;
  bool isBusy = false;
  String? errorMessage;

  String? get _businessId => _businessContext.activeBusinessId;

  void _handleBusinessChanged() {
    _summarySubscription?.cancel();
    _summarySubscription = null;
    final businessId = _businessContext.activeBusinessId;
    if (businessId == null) {
      summary = MerchantConnectionSummary.disconnected;
      notifyListeners();
      return;
    }
    _summarySubscription = _repository
        .merchantSummaryStream(businessId)
        .listen((summary) {
      this.summary = summary;
      notifyListeners();
    }, onError: (Object error) {
      errorMessage = friendlyErrorMessage(error);
      notifyListeners();
    });
  }

  /// Abre o fluxo OAuth no navegador. O estado "conectado" só chega quando o
  /// callback do backend publica o resumo — a stream atualiza sozinha.
  Future<void> connect() async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final businessId = _businessId;
      if (businessId == null) {
        throw StateError('Nenhuma loja ativa.');
      }
      final start = await _repository.startConnection(businessId);
      final opened = await _launcher.open(start.authorizationUrl);
      if (!opened) {
        throw StateError(
          'Abra o link de autorização no navegador para conectar a conta.',
        );
      }
    } catch (error) {
      errorMessage = friendlyErrorMessage(error);
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final businessId = _businessId;
      if (businessId == null) {
        throw StateError('Nenhuma loja ativa.');
      }
      await _repository.refreshConnection(businessId);
    } catch (error) {
      errorMessage = friendlyErrorMessage(error);
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final businessId = _businessId;
      if (businessId == null) {
        throw StateError('Nenhuma loja ativa.');
      }
      await _repository.disconnectConnection(businessId);
    } catch (error) {
      errorMessage = friendlyErrorMessage(error);
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _businessContext.removeListener(_handleBusinessChanged);
    _summarySubscription?.cancel();
    super.dispose();
  }
}
