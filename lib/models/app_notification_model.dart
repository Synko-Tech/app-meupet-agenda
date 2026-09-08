import 'firestore_converters.dart';

enum AppNotificationStatus {
  pending,
  sent,
  canceled;

  String get firestoreValue {
    switch (this) {
      case AppNotificationStatus.pending:
        return 'PENDENTE';
      case AppNotificationStatus.sent:
        return 'ENVIADA';
      case AppNotificationStatus.canceled:
        return 'CANCELADA';
    }
  }

  static AppNotificationStatus fromFirestore(Object? value) {
    final normalized = value?.toString().toUpperCase();
    return switch (normalized) {
      'ENVIADA' => AppNotificationStatus.sent,
      'CANCELADA' => AppNotificationStatus.canceled,
      _ => AppNotificationStatus.pending,
    };
  }
}

class AppNotificationModel {
  const AppNotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    required this.sendAt,
    required this.status,
    this.appointmentId,
  });

  final String id;
  final String userId;
  final String? appointmentId;
  final String title;
  final String message;
  final DateTime sendAt;
  final AppNotificationStatus status;

  factory AppNotificationModel.fromMap(String id, Map<String, dynamic> map) {
    return AppNotificationModel(
      id: id,
      userId: map['id_usuario']?.toString() ?? map['userId']?.toString() ?? '',
      appointmentId:
          map['id_agendamento']?.toString() ?? map['appointmentId']?.toString(),
      title: map['titulo']?.toString() ?? map['title']?.toString() ?? '',
      message: map['mensagem']?.toString() ?? map['message']?.toString() ?? '',
      sendAt: dateTimeRequiredFromFirestore(
        map['data_envio'] ?? map['sendAt'],
        field: 'sendAt',
      ),
      status: AppNotificationStatus.fromFirestore(map['status']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id_usuario': userId,
      'id_agendamento': appointmentId,
      'titulo': title,
      'mensagem': message,
      'data_envio': sendAt,
      'status': status.firestoreValue,
    };
  }
}
