import 'firestore_converters.dart';

enum PaymentType {
  appointment,
  package,
  other;

  String get firestoreValue {
    switch (this) {
      case PaymentType.appointment:
        return 'AGENDAMENTO';
      case PaymentType.package:
        return 'PACOTE';
      case PaymentType.other:
        return 'OUTRO';
    }
  }

  String get label {
    switch (this) {
      case PaymentType.appointment:
        return 'Agendamento';
      case PaymentType.package:
        return 'Pacote de servicos';
      case PaymentType.other:
        return 'Outro';
    }
  }

  static PaymentType fromFirestore(Object? value) {
    final normalized = value?.toString().toUpperCase();
    return switch (normalized) {
      'AGENDAMENTO' => PaymentType.appointment,
      'PACOTE' || 'PACOTE DE SERVICOS' => PaymentType.package,
      _ => PaymentType.other,
    };
  }
}

enum PaymentMethod {
  cash,
  pix,
  card,
  other;

  String get firestoreValue {
    switch (this) {
      case PaymentMethod.cash:
        return 'DINHEIRO';
      case PaymentMethod.pix:
        return 'PIX';
      case PaymentMethod.card:
        return 'CARTAO';
      case PaymentMethod.other:
        return 'OUTRO';
    }
  }

  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Dinheiro';
      case PaymentMethod.pix:
        return 'PIX';
      case PaymentMethod.card:
        return 'Cartao';
      case PaymentMethod.other:
        return 'Outro';
    }
  }

  static PaymentMethod fromFirestore(Object? value) {
    final normalized = value?.toString().toUpperCase();
    return switch (normalized) {
      'DINHEIRO' => PaymentMethod.cash,
      'CARTAO' => PaymentMethod.card,
      'PIX' => PaymentMethod.pix,
      _ => PaymentMethod.other,
    };
  }
}

enum PaymentStatus {
  pending,
  paid,
  canceled,
  refunded,
  underReview;

  String get firestoreValue {
    switch (this) {
      case PaymentStatus.pending:
        return 'PENDENTE';
      case PaymentStatus.paid:
        return 'PAGO';
      case PaymentStatus.canceled:
        return 'CANCELADO';
      case PaymentStatus.refunded:
        return 'REEMBOLSADO';
      case PaymentStatus.underReview:
        return 'EM_ANALISE';
    }
  }

  String get label {
    switch (this) {
      case PaymentStatus.pending:
        return 'Pendente';
      case PaymentStatus.paid:
        return 'Pago';
      case PaymentStatus.canceled:
        return 'Cancelado';
      case PaymentStatus.refunded:
        return 'Reembolsado';
      case PaymentStatus.underReview:
        return 'Em analise';
    }
  }

  static PaymentStatus fromFirestore(Object? value) {
    final normalized = value?.toString().toUpperCase();
    return switch (normalized) {
      'PAGO' => PaymentStatus.paid,
      'CANCELADO' => PaymentStatus.canceled,
      'REEMBOLSADO' => PaymentStatus.refunded,
      'EM_ANALISE' || 'EM ANÁLISE' || 'EM ANALISE' => PaymentStatus.underReview,
      _ => PaymentStatus.pending,
    };
  }
}

class PaymentModel {
  const PaymentModel({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.type,
    required this.amount,
    required this.method,
    required this.status,
    required this.paidAt,
    this.appointmentId,
    this.customerPackageId,
    this.createdAt,
  });

  final String id;
  final String clientId;
  final String clientName;
  final PaymentType type;
  final String? appointmentId;
  final String? customerPackageId;
  final double amount;
  final PaymentMethod method;

  /// Payment date. Null while the payment is pending (`PENDENTE`); the UI
  /// must show "Aguardando pagamento" instead of a fabricated date.
  final DateTime? paidAt;
  final PaymentStatus status;
  final DateTime? createdAt;

  factory PaymentModel.fromMap(String id, Map<String, dynamic> map) {
    final status = PaymentStatus.fromFirestore(map['status']);
    // `paidAt` is the canonical payment date, written by the backend only when
    // the payment becomes PAGO. Legacy docs only have `data_pagamento` (written
    // at request time even while PENDENTE), so it is used strictly as a
    // fallback for statuses that carry a semantic paid date.
    final paidAtRaw =
        map['paidAt'] ??
        (status == PaymentStatus.paid || status == PaymentStatus.refunded
            ? map['data_pagamento']
            : null);
    return PaymentModel(
      id: id,
      clientId:
          map['id_cliente']?.toString() ?? map['clientId']?.toString() ?? '',
      clientName: map['clientName']?.toString() ?? '',
      type: PaymentType.fromFirestore(map['tipo'] ?? map['type']),
      appointmentId:
          map['id_agendamento']?.toString() ?? map['appointmentId']?.toString(),
      customerPackageId:
          map['id_pacote_cliente']?.toString() ??
          map['customerPackageId']?.toString(),
      amount: doubleFromFirestore(map['valor'] ?? map['amount']),
      method: PaymentMethod.fromFirestore(
        map['forma_pagamento'] ?? map['method'],
      ),
      paidAt: paidAtRaw == null ? null : dateTimeFromFirestore(paidAtRaw),
      status: status,
      createdAt: map['createdAt'] == null
          ? null
          : dateTimeFromFirestore(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id_cliente': clientId,
      'clientName': clientName,
      'tipo': type.firestoreValue,
      'id_agendamento': appointmentId,
      'id_pacote_cliente': customerPackageId,
      'valor': amount,
      'forma_pagamento': method.firestoreValue,
      'data_pagamento': paidAt,
      'status': status.firestoreValue,
    };
  }
}
