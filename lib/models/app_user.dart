import 'firestore_converters.dart';

enum UserRole {
  superAdmin,
  admin,
  collaborator,
  client;

  String get firestoreValue {
    switch (this) {
      case UserRole.superAdmin:
        return 'super_admin';
      case UserRole.admin:
        return 'admin';
      case UserRole.collaborator:
        return 'collaborator';
      case UserRole.client:
        return 'client';
    }
  }

  String get label {
    switch (this) {
      case UserRole.superAdmin:
        return 'Super admin';
      case UserRole.admin:
        return 'Administrador';
      case UserRole.collaborator:
        return 'Colaborador';
      case UserRole.client:
        return 'Cliente';
    }
  }

  static UserRole fromFirestore(Object? value) {
    final normalized = value?.toString().toLowerCase();
    return switch (normalized) {
      'super_admin' || 'superadmin' => UserRole.superAdmin,
      'administrador' || 'admin' => UserRole.admin,
      'colaborador' || 'collaborator' || 'staff' => UserRole.collaborator,
      _ => UserRole.client,
    };
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.phone,
    this.isActive = true,
    this.profileComplete = false,
    this.schemaVersion = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String email;
  final String? phone;
  final UserRole role;
  final bool isActive;
  final bool profileComplete;
  final int schemaVersion;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isSuperAdmin => role == UserRole.superAdmin;
  bool get isAdmin => role == UserRole.admin || role == UserRole.superAdmin;
  bool get isStaff =>
      role == UserRole.superAdmin ||
      role == UserRole.admin ||
      role == UserRole.collaborator;
  bool get canManageUsers => isSuperAdmin || role == UserRole.admin;
  bool get canManageCatalog => isSuperAdmin || role == UserRole.admin;
  bool get canAccessAdminPanel => isStaff;

  factory AppUser.fromMap(String id, Map<String, dynamic> map) {
    return AppUser(
      id: id,
      name: map['nome']?.toString() ?? map['name']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      phone: map['telefone']?.toString() ?? map['phone']?.toString(),
      role: UserRole.fromFirestore(map['role'] ?? map['tipo_usuario']),
      isActive: map['ativo'] as bool? ?? map['isActive'] as bool? ?? true,
      profileComplete: map['profileComplete'] == true,
      schemaVersion: intFromFirestore(map['schemaVersion']),
      createdAt: map['createdAt'] == null
          ? null
          : dateTimeFromFirestore(map['createdAt']),
      updatedAt: map['updatedAt'] == null
          ? null
          : dateTimeFromFirestore(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nome': name,
      'email': email,
      'telefone': phone,
      'role': role.firestoreValue,
      'ativo': isActive,
      'profileComplete': profileComplete,
      'schemaVersion': schemaVersion,
      'updatedAt': updatedAt,
    };
  }

  /// Sentinel so `phone` can be explicitly cleared (null means "clear"),
  /// while omitting the argument keeps the current value.
  static const Object _unsetPhone = Object();

  AppUser copyWith({
    String? id,
    String? name,
    String? email,
    Object? phone = _unsetPhone,
    UserRole? role,
    bool? isActive,
    bool? profileComplete,
    int? schemaVersion,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: identical(phone, _unsetPhone) ? this.phone : phone as String?,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      profileComplete: profileComplete ?? this.profileComplete,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
