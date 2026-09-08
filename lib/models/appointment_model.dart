import 'firestore_converters.dart';

enum AppointmentStatus {
  scheduled,
  confirmed,
  completed,
  canceled;

  String get firestoreValue {
    switch (this) {
      case AppointmentStatus.scheduled:
        return 'AGENDADO';
      case AppointmentStatus.confirmed:
        return 'CONFIRMADO';
      case AppointmentStatus.completed:
        return 'CONCLUIDO';
      case AppointmentStatus.canceled:
        return 'CANCELADO';
    }
  }

  String get label {
    switch (this) {
      case AppointmentStatus.scheduled:
        return 'Agendado';
      case AppointmentStatus.confirmed:
        return 'Confirmado';
      case AppointmentStatus.completed:
        return 'Concluido';
      case AppointmentStatus.canceled:
        return 'Cancelado';
    }
  }

  static AppointmentStatus fromFirestore(Object? value) {
    final normalized = value?.toString().toUpperCase();
    return switch (normalized) {
      'CONFIRMADO' => AppointmentStatus.confirmed,
      'CONCLUIDO' => AppointmentStatus.completed,
      'CANCELADO' => AppointmentStatus.canceled,
      _ => AppointmentStatus.scheduled,
    };
  }
}

class AppointmentModel {
  const AppointmentModel({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.serviceId,
    required this.serviceName,
    required this.startAt,
    required this.endAt,
    required this.status,
    this.customerPackageId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String clientId;
  final String clientName;
  final String serviceId;
  final String serviceName;
  final String? customerPackageId;
  final DateTime startAt;
  final DateTime endAt;
  final AppointmentStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AppointmentModel.fromMap(String id, Map<String, dynamic> map) {
    return AppointmentModel(
      id: id,
      clientId:
          map['id_cliente']?.toString() ?? map['clientId']?.toString() ?? '',
      clientName: map['clientName']?.toString() ?? '',
      serviceId:
          map['id_servico']?.toString() ?? map['serviceId']?.toString() ?? '',
      serviceName: map['serviceName']?.toString() ?? '',
      customerPackageId:
          map['id_pacote_cliente']?.toString() ??
          map['customerPackageId']?.toString(),
      startAt: dateTimeRequiredFromFirestore(
        map['data_hora_inicio'] ?? map['startAt'],
        field: 'startAt',
      ),
      endAt: dateTimeRequiredFromFirestore(
        map['data_hora_fim'] ?? map['endAt'],
        field: 'endAt',
      ),
      status: AppointmentStatus.fromFirestore(map['status']),
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
      'id_cliente': clientId,
      'clientName': clientName,
      'id_servico': serviceId,
      'serviceName': serviceName,
      'id_pacote_cliente': customerPackageId,
      'data_hora_inicio': startAt,
      'data_hora_fim': endAt,
      'status': status.firestoreValue,
      'updatedAt': updatedAt,
    };
  }
}
