import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/business_membership.dart';
import '../repositories/business_repository.dart';
import '../services/function_error.dart';
import 'auth_controller.dart';

/// Controla o contexto de loja ativo do usuario logado.
///
/// O papel operacional (owner/admin/collaborator/client) vive no membership
/// da loja, nao no perfil global. Toda navegacao de dados depende de um
/// [activeBusinessId] resolvido por este controller.
class BusinessContextController extends ChangeNotifier {
  BusinessContextController({
    required BusinessRepository repository,
    required AuthController authController,
  }) : _repository = repository,
       _authController = authController {
    _authController.addListener(_handleAuthChanged);
    _handleAuthChanged();
  }

  final BusinessRepository _repository;
  final AuthController _authController;

  StreamSubscription<List<BusinessMembership>>? _membershipsSubscription;

  List<BusinessMembership> memberships = const [];
  String? activeBusinessId;
  BusinessMembership? activeMembership;
  bool isLoading = true;
  bool isBusy = false;
  String? errorMessage;

  bool get hasActiveBusiness => activeBusinessId != null;

  BusinessRole? get activeRole => activeMembership?.role;

  /// Cria uma loja via backend (onboarding do owner) e a seleciona como
  /// ativa. O backend grava `businesses/{id}` + membership owner na mesma
  /// transacao; a projecao `users/{uid}/businessMemberships/{id}` chega pela
  /// stream e atualiza a lista.
  Future<void> createBusiness({
    required String name,
    String? description,
  }) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final created = await _repository.createBusiness(
        name: name,
        description: description,
      );
      await selectBusiness(created.businessId);
    } catch (error) {
      errorMessage = friendlyErrorMessage(error);
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  /// Seleciona a loja ativa, se o usuario tiver membership nela.
  Future<void> selectBusiness(String businessId) async {
    final membership = _membershipFor(businessId);
    activeBusinessId = businessId;
    activeMembership = membership;
    notifyListeners();
  }

  /// Entra em um pet shop como cliente: cria a membership via backend e
  /// seleciona a loja como ativa. A projecao
  /// `users/{uid}/businessMemberships/{id}` chega pela stream e atualiza a
  /// lista de memberships.
  Future<void> joinBusiness(String businessId) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _repository.joinBusiness(businessId: businessId);
      await selectBusiness(businessId);
    } catch (error) {
      errorMessage = friendlyErrorMessage(error);
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  void clearBusiness() {
    activeBusinessId = null;
    activeMembership = null;
    notifyListeners();
  }

  BusinessMembership? _membershipFor(String businessId) {
    for (final membership in memberships) {
      if (membership.businessId == businessId && membership.isActive) {
        return membership;
      }
    }
    return null;
  }

  void _handleAuthChanged() {
    _membershipsSubscription?.cancel();
    _membershipsSubscription = null;

    final userId = _authController.firebaseUser?.uid;
    if (userId == null) {
      memberships = const [];
      activeBusinessId = null;
      activeMembership = null;
      isLoading = false;
      notifyListeners();
      return;
    }

    isLoading = true;
    notifyListeners();
    _membershipsSubscription = _repository
        .myMembershipsStream(userId)
        .listen(
          (memberships) {
            this.memberships = memberships;
            // Mantem a loja ativa se o usuario ainda tiver membership valida.
            final current = activeBusinessId;
            final stillMember =
                current != null && _membershipFor(current) != null;
            if (!stillMember) {
              activeBusinessId = null;
              activeMembership = null;
            } else {
              activeMembership = _membershipFor(current);
            }
            isLoading = false;
            notifyListeners();
          },
          onError: (Object error) {
            errorMessage = friendlyErrorMessage(error);
            isLoading = false;
            notifyListeners();
          },
        );
  }

  @override
  void dispose() {
    _authController.removeListener(_handleAuthChanged);
    _membershipsSubscription?.cancel();
    super.dispose();
  }
}
