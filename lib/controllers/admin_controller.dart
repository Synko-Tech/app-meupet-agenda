import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/package_model.dart';
import '../models/service_model.dart';
import '../repositories/package_repository.dart';
import '../repositories/service_repository.dart';
import '../repositories/user_repository.dart';
import '../services/access_control.dart';
import '../services/function_error.dart';
import 'auth_controller.dart';
import 'business_context_controller.dart';

class AdminController extends ChangeNotifier {
  AdminController({
    required ServiceRepository serviceRepository,
    required PackageRepository packageRepository,
    required UserRepository userRepository,
    required AuthController authController,
    required BusinessContextController businessContext,
  }) : _serviceRepository = serviceRepository,
       _packageRepository = packageRepository,
       _userRepository = userRepository,
       _authController = authController,
       _businessContext = businessContext;

  final ServiceRepository _serviceRepository;
  final PackageRepository _packageRepository;
  final UserRepository _userRepository;
  final AuthController _authController;
  final BusinessContextController _businessContext;

  bool isBusy = false;
  String? errorMessage;

  String get _businessId {
    final businessId = _businessContext.activeBusinessId;
    if (businessId == null) {
      throw StateError('Nenhuma loja ativa.');
    }
    return businessId;
  }

  Future<void> saveService(ServiceModel service) {
    return _run(() {
      AccessControl.requireCatalogManager(_authController.profile);
      return _serviceRepository.saveService(_businessId, service);
    });
  }

  Future<void> savePackage(BusinessPackageModel package) {
    return _run(() {
      AccessControl.requireCatalogManager(_authController.profile);
      return _packageRepository.savePackage(_businessId, package);
    });
  }

  Future<void> setServiceActive(String serviceId, bool isActive) {
    return _run(() {
      AccessControl.requireCatalogManager(_authController.profile);
      return _serviceRepository.setActive(_businessId, serviceId, isActive);
    });
  }

  Future<void> updateUserRole({
    required String userId,
    required UserRole role,
  }) {
    return _run(() {
      AccessControl.requireUserManager(_authController.profile);
      if (!AccessControl.canAssignRole(_authController.profile, role)) {
        throw StateError('Seu perfil nao pode atribuir esta permissao.');
      }
      return _userRepository.updateUserRole(userId: userId, role: role);
    });
  }

  Future<void> setUserActive({required String userId, required bool isActive}) {
    return _run(() {
      AccessControl.requireUserManager(_authController.profile);
      return _userRepository.setUserActive(userId: userId, isActive: isActive);
    });
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
