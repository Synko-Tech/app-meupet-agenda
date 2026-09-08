// Role-based navigation decision layer.
//
// SCOPE NOTE: The full HomeShell widget test (pumping HomeShell with a
// Provider-wrapped AuthController and asserting the NavigationBar destinations
// toggle with the role) is deferred. HomeShell builds AppointmentScreen,
// PackagesScreen, PaymentScreen, AdminDashboardScreen and AccountScreen, each
// of which pulls Firebase-backed controllers from Provider — pumping that
// tree requires a real AuthController constructed with Firebase repositories
// or a testing seam AuthController does not expose (its constructor requires
// concrete repository instances). These tests cover the decision layer
// HomeShell consults (home_shell.dart `canAccessAdminPanel` -> AppUser
// `canAccessAdminPanel` -> `isStaff`, and `isSuperAdmin` for the admin shell)
// plus AccessControl, which every admin screen calls to gate itself
// (admin_dashboard_screen.dart, payment_screen.dart). Widget-level coverage is
// tracked for the Task 18 / final review follow-up.
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/models/app_user.dart';
import 'package:meupet_agenda_app/services/access_control.dart';

AppUser userWithRole(UserRole role) {
  return AppUser(
    id: 'u-${role.name}',
    name: 'Usuario',
    email: 'usuario@exemplo.com',
    role: role,
  );
}

void main() {
  group('AppUser role matrix (drives HomeShell tabs)', () {
    test('client has no admin access', () {
      final user = userWithRole(UserRole.client);
      expect(user.isSuperAdmin, isFalse);
      expect(user.isAdmin, isFalse);
      expect(user.isStaff, isFalse);
      expect(user.canAccessAdminPanel, isFalse);
      expect(user.canManageUsers, isFalse);
      expect(user.canManageCatalog, isFalse);
    });

    test('collaborator can access the admin panel but not manage users', () {
      final user = userWithRole(UserRole.collaborator);
      expect(user.isSuperAdmin, isFalse);
      expect(user.isAdmin, isFalse);
      expect(user.isStaff, isTrue);
      expect(user.canAccessAdminPanel, isTrue);
      expect(user.canManageUsers, isFalse);
      expect(user.canManageCatalog, isFalse);
    });

    test('admin can access the panel and manage users and catalog', () {
      final user = userWithRole(UserRole.admin);
      expect(user.isSuperAdmin, isFalse);
      expect(user.isAdmin, isTrue);
      expect(user.isStaff, isTrue);
      expect(user.canAccessAdminPanel, isTrue);
      expect(user.canManageUsers, isTrue);
      expect(user.canManageCatalog, isTrue);
    });

    test('super admin has full access', () {
      final user = userWithRole(UserRole.superAdmin);
      expect(user.isSuperAdmin, isTrue);
      expect(user.isAdmin, isTrue);
      expect(user.isStaff, isTrue);
      expect(user.canAccessAdminPanel, isTrue);
      expect(user.canManageUsers, isTrue);
      expect(user.canManageCatalog, isTrue);
    });
  });

  group('AccessControl gates', () {
    test('canAccessAdminPanel follows the staff role and null profile', () {
      expect(AccessControl.canAccessAdminPanel(null), isFalse);
      expect(
        AccessControl.canAccessAdminPanel(userWithRole(UserRole.client)),
        isFalse,
      );
      expect(
        AccessControl.canAccessAdminPanel(userWithRole(UserRole.collaborator)),
        isTrue,
      );
      expect(
        AccessControl.canAccessAdminPanel(userWithRole(UserRole.admin)),
        isTrue,
      );
      expect(
        AccessControl.canAccessAdminPanel(userWithRole(UserRole.superAdmin)),
        isTrue,
      );
    });

    test('payments, professionals and admin calendar are super-admin only', () {
      for (final role in [
        UserRole.client,
        UserRole.collaborator,
        UserRole.admin,
      ]) {
        expect(
          AccessControl.canManagePayments(userWithRole(role)),
          isFalse,
          reason: 'role $role should not manage payments',
        );
        expect(
          AccessControl.canAccessAdminCalendar(userWithRole(role)),
          isFalse,
          reason: 'role $role should not access the admin calendar',
        );
      }
      final superAdmin = userWithRole(UserRole.superAdmin);
      expect(AccessControl.canManagePayments(superAdmin), isTrue);
      expect(AccessControl.canAccessAdminCalendar(superAdmin), isTrue);
    });

    test('canAssignRole: admin cannot grant admin or super admin', () {
      final superAdmin = userWithRole(UserRole.superAdmin);
      for (final role in UserRole.values) {
        expect(
          AccessControl.canAssignRole(superAdmin, role),
          isTrue,
          reason: 'super admin should assign $role',
        );
      }

      final admin = userWithRole(UserRole.admin);
      expect(AccessControl.canAssignRole(admin, UserRole.client), isTrue);
      expect(AccessControl.canAssignRole(admin, UserRole.collaborator), isTrue);
      expect(AccessControl.canAssignRole(admin, UserRole.admin), isFalse);
      expect(AccessControl.canAssignRole(admin, UserRole.superAdmin), isFalse);

      final collaborator = userWithRole(UserRole.collaborator);
      for (final role in UserRole.values) {
        expect(
          AccessControl.canAssignRole(collaborator, role),
          isFalse,
          reason: 'collaborator should not assign $role',
        );
      }
    });

    test('require* helpers throw for insufficient privileges', () {
      final client = userWithRole(UserRole.client);
      expect(
        () => AccessControl.requireCatalogManager(client),
        throwsStateError,
      );
      expect(() => AccessControl.requireUserManager(client), throwsStateError);
      expect(
        () => AccessControl.requirePaymentManager(client),
        throwsStateError,
      );
      expect(
        () => AccessControl.requireAdminCalendarAccess(client),
        throwsStateError,
      );

      // No throw for sufficient privileges.
      final superAdmin = userWithRole(UserRole.superAdmin);
      expect(
        () => AccessControl.requireCatalogManager(superAdmin),
        returnsNormally,
      );
      expect(
        () => AccessControl.requirePaymentManager(superAdmin),
        returnsNormally,
      );
    });
  });
}
