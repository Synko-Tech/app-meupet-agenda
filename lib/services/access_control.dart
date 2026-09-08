import '../models/app_user.dart';

class AccessControl {
  const AccessControl._();

  static bool canAccessAdminPanel(AppUser? user) {
    return user?.canAccessAdminPanel ?? false;
  }

  static bool canManageCatalog(AppUser? user) {
    return user?.canManageCatalog ?? false;
  }

  static bool canManageUsers(AppUser? user) {
    return user?.canManageUsers ?? false;
  }

  static bool canManagePayments(AppUser? user) {
    return user?.isSuperAdmin ?? false;
  }

  static bool canAccessAdminCalendar(AppUser? user) {
    return user?.isSuperAdmin ?? false;
  }

  static bool canAssignRole(AppUser? actor, UserRole role) {
    if (actor == null) {
      return false;
    }
    if (actor.isSuperAdmin) {
      return true;
    }
    return actor.role == UserRole.admin &&
        role != UserRole.superAdmin &&
        role != UserRole.admin;
  }

  static void requireCatalogManager(AppUser? user) {
    if (!canManageCatalog(user)) {
      throw StateError('Acesso administrativo necessario para esta acao.');
    }
  }

  static void requireUserManager(AppUser? user) {
    if (!canManageUsers(user)) {
      throw StateError('Permissao insuficiente para gerenciar usuarios.');
    }
  }

  static void requirePaymentManager(AppUser? user) {
    if (!canManagePayments(user)) {
      throw StateError('Apenas super admin pode alterar pagamentos.');
    }
  }

  static void requireAdminCalendarAccess(AppUser? user) {
    if (!canAccessAdminCalendar(user)) {
      throw StateError('Apenas super admin pode acessar o calendario.');
    }
  }
}
