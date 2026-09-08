import 'firestore_converters.dart';

enum CustomerPackageStatus {
  active,
  finished,
  expired,
  canceled,
  refunded;

  String get firestoreValue {
    switch (this) {
      case CustomerPackageStatus.active:
        return 'ATIVO';
      case CustomerPackageStatus.finished:
        return 'FINALIZADO';
      case CustomerPackageStatus.expired:
        return 'VENCIDO';
      case CustomerPackageStatus.canceled:
        return 'CANCELADO';
      case CustomerPackageStatus.refunded:
        return 'REEMBOLSADO';
    }
  }

  String get label {
    switch (this) {
      case CustomerPackageStatus.active:
        return 'Ativo';
      case CustomerPackageStatus.finished:
        return 'Finalizado';
      case CustomerPackageStatus.expired:
        return 'Vencido';
      case CustomerPackageStatus.canceled:
        return 'Cancelado';
      case CustomerPackageStatus.refunded:
        return 'Reembolsado';
    }
  }

  static CustomerPackageStatus fromFirestore(Object? value) {
    final normalized = value?.toString().toUpperCase();
    return switch (normalized) {
      'FINALIZADO' => CustomerPackageStatus.finished,
      'VENCIDO' => CustomerPackageStatus.expired,
      'CANCELADO' => CustomerPackageStatus.canceled,
      'REEMBOLSADO' => CustomerPackageStatus.refunded,
      _ => CustomerPackageStatus.active,
    };
  }
}

class BusinessPackageModel {
  const BusinessPackageModel({
    required this.id,
    required this.serviceId,
    required this.name,
    required this.totalCredits,
    required this.price,
    required this.validityDays,
    this.serviceName = '',
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String serviceId;
  final String serviceName;
  final String name;
  final int totalCredits;
  final double price;
  final int validityDays;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory BusinessPackageModel.fromMap(String id, Map<String, dynamic> map) {
    return BusinessPackageModel(
      id: id,
      serviceId:
          map['id_servico']?.toString() ?? map['serviceId']?.toString() ?? '',
      serviceName: map['serviceName']?.toString() ?? '',
      name: map['nome']?.toString() ?? map['name']?.toString() ?? '',
      totalCredits: intFromFirestore(
        map['quantidade_creditos'] ?? map['totalCredits'],
      ),
      price: doubleFromFirestore(map['valor'] ?? map['price']),
      validityDays: intFromFirestore(
        map['validade_dias'] ?? map['validityDays'],
      ),
      isActive: map['ativo'] as bool? ?? map['isActive'] as bool? ?? true,
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
      'id_servico': serviceId,
      'serviceName': serviceName,
      'nome': name,
      'quantidade_creditos': totalCredits,
      'valor': price,
      'validade_dias': validityDays,
      'ativo': isActive,
      'updatedAt': updatedAt,
    };
  }
}

class CustomerPackageModel {
  const CustomerPackageModel({
    required this.id,
    required this.clientId,
    required this.packageId,
    required this.serviceId,
    required this.packageName,
    required this.serviceName,
    required this.totalCredits,
    required this.usedCredits,
    required this.purchaseDate,
    required this.validUntil,
    required this.status,
  });

  final String id;
  final String clientId;
  final String packageId;
  final String serviceId;
  final String packageName;
  final String serviceName;
  final int totalCredits;
  final int usedCredits;
  final DateTime purchaseDate;
  final DateTime validUntil;
  final CustomerPackageStatus status;

  int get remainingCredits => totalCredits - usedCredits;
  bool get isExpired => !validUntil.isAfter(DateTime.now());
  bool get canUse =>
      status == CustomerPackageStatus.active &&
      remainingCredits > 0 &&
      !isExpired;
  double get usageProgress {
    if (totalCredits == 0) {
      return 0;
    }
    return (usedCredits / totalCredits).clamp(0, 1).toDouble();
  }

  factory CustomerPackageModel.fromMap(String id, Map<String, dynamic> map) {
    return CustomerPackageModel(
      id: id,
      clientId:
          map['id_cliente']?.toString() ?? map['clientId']?.toString() ?? '',
      packageId:
          map['id_pacote']?.toString() ?? map['packageId']?.toString() ?? '',
      serviceId:
          map['id_servico']?.toString() ?? map['serviceId']?.toString() ?? '',
      packageName:
          map['packageName']?.toString() ?? map['nome']?.toString() ?? '',
      serviceName: map['serviceName']?.toString() ?? '',
      totalCredits: intFromFirestore(
        map['creditos_totais'] ?? map['totalCredits'],
      ),
      usedCredits: intFromFirestore(
        map['creditos_usados'] ?? map['usedCredits'],
      ),
      purchaseDate: dateTimeRequiredFromFirestore(
        map['data_compra'] ?? map['purchaseDate'],
        field: 'purchaseDate',
      ),
      validUntil: dateTimeRequiredFromFirestore(
        map['data_validade'] ?? map['validUntil'],
        field: 'validUntil',
      ),
      status: CustomerPackageStatus.fromFirestore(map['status']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id_cliente': clientId,
      'id_pacote': packageId,
      'id_servico': serviceId,
      'packageName': packageName,
      'serviceName': serviceName,
      'creditos_totais': totalCredits,
      'creditos_usados': usedCredits,
      'data_compra': purchaseDate,
      'data_validade': validUntil,
      'status': status.firestoreValue,
    };
  }
}
