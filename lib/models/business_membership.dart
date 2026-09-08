import 'firestore_converters.dart';

/// Papel operacional do usuario dentro de uma loja. O papel global
/// (`super_admin`, `client`, etc.) permanece em `users/{uid}`; o papel por
/// loja vive no membership.
enum BusinessRole {
  owner,
  admin,
  collaborator,
  client;

  String get firestoreValue {
    switch (this) {
      case BusinessRole.owner:
        return 'owner';
      case BusinessRole.admin:
        return 'admin';
      case BusinessRole.collaborator:
        return 'collaborator';
      case BusinessRole.client:
        return 'client';
    }
  }

  String get label {
    switch (this) {
      case BusinessRole.owner:
        return 'Dono';
      case BusinessRole.admin:
        return 'Administrador';
      case BusinessRole.collaborator:
        return 'Colaborador';
      case BusinessRole.client:
        return 'Cliente';
    }
  }

  bool get isStaff {
    switch (this) {
      case BusinessRole.owner:
      case BusinessRole.admin:
      case BusinessRole.collaborator:
        return true;
      case BusinessRole.client:
        return false;
    }
  }

  bool get canManageBusiness =>
      this == BusinessRole.owner || this == BusinessRole.admin;

  static BusinessRole fromFirestore(Object? value) {
    final normalized = value?.toString().toLowerCase();
    return switch (normalized) {
      'owner' || 'dono' => BusinessRole.owner,
      'admin' || 'administrador' => BusinessRole.admin,
      'collaborator' || 'colaborador' || 'staff' => BusinessRole.collaborator,
      _ => BusinessRole.client,
    };
  }
}

/// Membership de um usuario em uma loja. A projecao canonica fica em
/// `businesses/{businessId}/members/{uid}`; uma copia denormalizada em
/// `users/{uid}/businessMemberships/{businessId}` permite listar lojas sem
/// abrir acesso cruzado.
class BusinessMembership {
  const BusinessMembership({
    required this.userId,
    required this.businessId,
    required this.role,
    this.businessName = '',
    this.isActive = true,
    this.createdAt,
  });

  final String userId;
  final String businessId;
  final BusinessRole role;
  final String businessName;
  final bool isActive;
  final DateTime? createdAt;

  factory BusinessMembership.fromMap(String userId, Map<String, dynamic> map) {
    return BusinessMembership(
      userId: userId,
      businessId:
          map['businessId']?.toString() ?? map['id_loja']?.toString() ?? '',
      role: BusinessRole.fromFirestore(map['role']),
      businessName:
          map['businessName']?.toString() ?? map['nome']?.toString() ?? '',
      isActive: map['ativo'] as bool? ?? map['isActive'] as bool? ?? true,
      createdAt: map['createdAt'] == null
          ? null
          : dateTimeFromFirestore(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'businessId': businessId,
      'businessName': businessName,
      'role': role.firestoreValue,
      'ativo': isActive,
    };
  }
}
