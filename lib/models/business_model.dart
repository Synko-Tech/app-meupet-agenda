import 'firestore_converters.dart';
import 'postal_address.dart';

enum BusinessStatus {
  active,
  inactive,
  suspended;

  String get firestoreValue {
    switch (this) {
      case BusinessStatus.active:
        return 'ATIVO';
      case BusinessStatus.inactive:
        return 'INATIVO';
      case BusinessStatus.suspended:
        return 'SUSPENSO';
    }
  }

  String get label {
    switch (this) {
      case BusinessStatus.active:
        return 'Ativa';
      case BusinessStatus.inactive:
        return 'Inativa';
      case BusinessStatus.suspended:
        return 'Suspensa';
    }
  }

  static BusinessStatus fromFirestore(Object? value) {
    final normalized = value?.toString().toUpperCase();
    return switch (normalized) {
      'INATIVO' => BusinessStatus.inactive,
      'SUSPENSO' => BusinessStatus.suspended,
      _ => BusinessStatus.active,
    };
  }
}

class BusinessModel {
  const BusinessModel({
    required this.id,
    required this.name,
    this.description,
    this.legalName,
    this.cnpj,
    this.phone,
    this.address,
    this.timezone = 'America/Sao_Paulo',
    this.status = BusinessStatus.active,
    this.ownerId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;

  /// Razao social (nome juridico) da empresa.
  final String? legalName;

  /// CNPJ canonico (14 digitos, sem mascara).
  final String? cnpj;
  final String? description;
  final String? phone;
  final PostalAddress? address;
  final String timezone;
  final BusinessStatus status;
  final String? ownerId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == BusinessStatus.active;

  /// CNPJ para exibicao (`**.***.***/****-NN`): apenas os 2 ultimos digitos
  /// visiveis, consistente com o `cnpjLast2` gravado pelo backend.
  String? get cnpjMasked {
    final cnpj = this.cnpj;
    if (cnpj == null || cnpj.isEmpty) {
      return null;
    }
    final tail = cnpj.length >= 2
        ? cnpj.substring(cnpj.length - 2)
        : cnpj;
    return '**.***.***/****-$tail';
  }

  factory BusinessModel.fromMap(String id, Map<String, dynamic> map) {
    return BusinessModel(
      id: id,
      name: map['nome']?.toString() ?? map['name']?.toString() ?? '',
      description:
          map['descricao']?.toString() ?? map['description']?.toString(),
      legalName:
          map['razaoSocial']?.toString() ?? map['legalName']?.toString(),
      cnpj: map['cnpj']?.toString(),
      phone: map['telefone']?.toString() ?? map['phone']?.toString(),
      address: map['endereco'] is Map
          ? PostalAddress.fromMap(
              (map['endereco'] as Map).cast<String, dynamic>(),
            )
          : null,
      timezone: map['timezone']?.toString() ?? 'America/Sao_Paulo',
      status: BusinessStatus.fromFirestore(map['status']),
      ownerId: map['ownerId']?.toString() ?? map['id_dono']?.toString(),
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
      'razaoSocial': legalName,
      'cnpj': cnpj,
      'descricao': description,
      'telefone': phone,
      'endereco': address?.toMap(),
      'timezone': timezone,
      'status': status.firestoreValue,
      'ownerId': ownerId,
      'updatedAt': updatedAt,
    };
  }
}
