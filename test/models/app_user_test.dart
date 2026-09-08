import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/models/app_user.dart';

void main() {
  group('UserRole.firestoreValue', () {
    test('maps every role to its firestore string', () {
      expect(UserRole.superAdmin.firestoreValue, 'super_admin');
      expect(UserRole.admin.firestoreValue, 'admin');
      expect(UserRole.collaborator.firestoreValue, 'collaborator');
      expect(UserRole.client.firestoreValue, 'client');
    });
  });

  group('UserRole.label', () {
    test('exposes a display label per role', () {
      expect(UserRole.superAdmin.label, 'Super admin');
      expect(UserRole.admin.label, 'Administrador');
      expect(UserRole.collaborator.label, 'Colaborador');
      expect(UserRole.client.label, 'Cliente');
    });
  });

  group('UserRole.fromFirestore', () {
    test('parses super admin variants', () {
      expect(UserRole.fromFirestore('super_admin'), UserRole.superAdmin);
      expect(UserRole.fromFirestore('superadmin'), UserRole.superAdmin);
      expect(UserRole.fromFirestore('SUPER_ADMIN'), UserRole.superAdmin);
    });

    test('parses admin variants', () {
      expect(UserRole.fromFirestore('admin'), UserRole.admin);
      expect(UserRole.fromFirestore('administrador'), UserRole.admin);
    });

    test('parses collaborator variants', () {
      expect(UserRole.fromFirestore('collaborator'), UserRole.collaborator);
      expect(UserRole.fromFirestore('colaborador'), UserRole.collaborator);
      expect(UserRole.fromFirestore('staff'), UserRole.collaborator);
    });

    test('falls back to client for unknown or null values', () {
      expect(UserRole.fromFirestore('desconhecido'), UserRole.client);
      expect(UserRole.fromFirestore(null), UserRole.client);
    });
  });

  group('AppUser.fromMap', () {
    test('parses the Portuguese firestore keys', () {
      final createdAt = Timestamp.fromDate(DateTime(2026, 1, 2, 3, 4));
      final user = AppUser.fromMap('u1', {
        'nome': 'Ana',
        'email': 'ana@exemplo.com',
        'telefone': '11999999999',
        'tipo_usuario': 'admin',
        'ativo': false,
        'createdAt': createdAt,
        'updatedAt': createdAt,
      });

      expect(user.id, 'u1');
      expect(user.name, 'Ana');
      expect(user.email, 'ana@exemplo.com');
      expect(user.phone, '11999999999');
      expect(user.role, UserRole.admin);
      expect(user.isActive, isFalse);
      expect(user.createdAt, DateTime(2026, 1, 2, 3, 4));
      expect(user.updatedAt, DateTime(2026, 1, 2, 3, 4));
    });

    test('parses the English fallback keys', () {
      final user = AppUser.fromMap('u2', {
        'name': 'Bruno',
        'email': 'bruno@exemplo.com',
        'phone': '11988888888',
        'role': 'client',
        'isActive': true,
      });

      expect(user.name, 'Bruno');
      expect(user.phone, '11988888888');
      expect(user.role, UserRole.client);
      expect(user.isActive, isTrue);
    });

    test('applies defaults for missing fields', () {
      final user = AppUser.fromMap('u3', {'email': 'x@exemplo.com'});
      expect(user.name, '');
      expect(user.phone, isNull);
      expect(user.role, UserRole.client);
      expect(user.isActive, isTrue);
      expect(user.createdAt, isNull);
      expect(user.updatedAt, isNull);
    });

    test('old users without profileComplete are incomplete', () {
      final user = AppUser.fromMap('u4', {'email': 'x@exemplo.com'});
      expect(user.profileComplete, isFalse);
    });

    test('parses profileComplete and schemaVersion when present', () {
      final user = AppUser.fromMap('u5', {
        'email': 'x@exemplo.com',
        'profileComplete': true,
        'schemaVersion': 2,
      });
      expect(user.profileComplete, isTrue);
      expect(user.schemaVersion, 2);
    });

    test('schemaVersion defaults to 0 for old documents', () {
      final user = AppUser.fromMap('u6', {'email': 'x@exemplo.com'});
      expect(user.schemaVersion, 0);
    });
  });

  test('toMap/fromMap round-trip preserves all fields', () {
    final original = AppUser(
      id: 'u4',
      name: 'Carla',
      email: 'carla@exemplo.com',
      phone: '11977777777',
      role: UserRole.superAdmin,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 2, 1),
    );

    final restored = AppUser.fromMap(original.id, original.toMap());

    expect(restored.id, original.id);
    expect(restored.name, original.name);
    expect(restored.email, original.email);
    expect(restored.phone, original.phone);
    expect(restored.role, UserRole.superAdmin);
    expect(restored.isActive, isTrue);
    expect(restored.createdAt, isNull);
    expect(restored.updatedAt, DateTime(2026, 2, 1));
    expect(original.toMap()['role'], 'super_admin');
    expect(original.toMap()['ativo'], isTrue);
  });

  group('AppUser role helpers', () {
    AppUser userWith(UserRole role) =>
        AppUser(id: 'u', name: 'N', email: 'n@exemplo.com', role: role);

    test('isSuperAdmin', () {
      expect(userWith(UserRole.superAdmin).isSuperAdmin, isTrue);
      expect(userWith(UserRole.admin).isSuperAdmin, isFalse);
    });

    test('isAdmin includes superAdmin and admin', () {
      expect(userWith(UserRole.superAdmin).isAdmin, isTrue);
      expect(userWith(UserRole.admin).isAdmin, isTrue);
      expect(userWith(UserRole.collaborator).isAdmin, isFalse);
    });

    test('isStaff includes all staff roles', () {
      expect(userWith(UserRole.superAdmin).isStaff, isTrue);
      expect(userWith(UserRole.admin).isStaff, isTrue);
      expect(userWith(UserRole.collaborator).isStaff, isTrue);
      expect(userWith(UserRole.client).isStaff, isFalse);
    });

    test('canManageUsers and canManageCatalog are admin-only', () {
      expect(userWith(UserRole.superAdmin).canManageUsers, isTrue);
      expect(userWith(UserRole.admin).canManageUsers, isTrue);
      expect(userWith(UserRole.collaborator).canManageUsers, isFalse);
      expect(userWith(UserRole.superAdmin).canManageCatalog, isTrue);
      expect(userWith(UserRole.admin).canManageCatalog, isTrue);
      expect(userWith(UserRole.collaborator).canManageCatalog, isFalse);
    });

    test('canAccessAdminPanel follows isStaff', () {
      expect(userWith(UserRole.collaborator).canAccessAdminPanel, isTrue);
      expect(userWith(UserRole.client).canAccessAdminPanel, isFalse);
    });
  });

  group('AppUser.copyWith', () {
    const user = AppUser(
      id: 'u1',
      name: 'Ana',
      email: 'ana@exemplo.com',
      phone: '11999999999',
      role: UserRole.client,
    );

    test('keeps unchanged values', () {
      final copy = user.copyWith(name: 'Ana Maria');
      expect(copy.id, 'u1');
      expect(copy.name, 'Ana Maria');
      expect(copy.phone, '11999999999');
      expect(copy.role, UserRole.client);
    });

    test('clears the phone when explicitly passed null', () {
      final copy = user.copyWith(phone: null);
      expect(copy.phone, isNull);
    });

    test('keeps the phone when the argument is omitted', () {
      final copy = user.copyWith(name: 'Ana');
      expect(copy.phone, '11999999999');
    });

    test('changes the role', () {
      final copy = user.copyWith(role: UserRole.admin);
      expect(copy.role, UserRole.admin);
    });
  });
}
