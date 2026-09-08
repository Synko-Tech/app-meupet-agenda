import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/models/payment_model.dart';

void main() {
  group('PaymentModel.fromMap', () {
    test('parses a PAGO payment with data_pagamento as Timestamp', () {
      final payment = PaymentModel.fromMap('pay-1', {
        'id_cliente': 'c1',
        'clientName': 'Cliente',
        'tipo': 'AGENDAMENTO',
        'valor': 80.0,
        'forma_pagamento': 'PIX',
        'status': 'PAGO',
        'data_pagamento': Timestamp.fromDate(DateTime(2026, 5, 18, 10, 30)),
      });

      expect(payment.id, 'pay-1');
      expect(payment.clientId, 'c1');
      expect(payment.clientName, 'Cliente');
      expect(payment.type, PaymentType.appointment);
      expect(payment.amount, 80.0);
      expect(payment.method, PaymentMethod.pix);
      expect(payment.status, PaymentStatus.paid);
      expect(payment.paidAt, DateTime(2026, 5, 18, 10, 30));
    });

    test('parses data_pagamento as ISO string', () {
      final payment = PaymentModel.fromMap('pay-2', {
        'id_cliente': 'c1',
        'tipo': 'AGENDAMENTO',
        'valor': 80.0,
        'forma_pagamento': 'PIX',
        'status': 'PAGO',
        'data_pagamento': '2026-05-18T10:30:00.000',
      });

      expect(payment.status, PaymentStatus.paid);
      expect(payment.paidAt, DateTime(2026, 5, 18, 10, 30));
    });

    test('PAGO prefers paidAt over legacy data_pagamento', () {
      final payment = PaymentModel.fromMap('pay-4', {
        'id_cliente': 'c1',
        'tipo': 'PACOTE',
        'valor': 150.0,
        'forma_pagamento': 'PIX',
        'status': 'PAGO',
        'data_pagamento': Timestamp.fromDate(DateTime(2026, 5, 1)),
        'paidAt': Timestamp.fromDate(DateTime(2026, 5, 20)),
      });

      expect(payment.paidAt, DateTime(2026, 5, 20));
    });

    test('PENDENTE ignores legacy data_pagamento — a fabricated date must not '
        'be shown as the paid date', () {
      final payment = PaymentModel.fromMap('pay-5', {
        'id_cliente': 'c1',
        'tipo': 'AGENDAMENTO',
        'valor': 80.0,
        'forma_pagamento': 'PIX',
        'status': 'PENDENTE',
        'data_pagamento': Timestamp.fromDate(DateTime(2026, 5, 18, 10, 30)),
      });

      expect(payment.status, PaymentStatus.pending);
      expect(payment.paidAt, isNull);
    });

    test('REEMBOLSADO falls back to legacy data_pagamento when paidAt is '
        'missing', () {
      final payment = PaymentModel.fromMap('pay-6', {
        'id_cliente': 'c1',
        'tipo': 'AGENDAMENTO',
        'valor': 80.0,
        'forma_pagamento': 'PIX',
        'status': 'REEMBOLSADO',
        'data_pagamento': Timestamp.fromDate(DateTime(2026, 5, 18, 10, 30)),
      });

      expect(payment.status, PaymentStatus.refunded);
      expect(payment.paidAt, DateTime(2026, 5, 18, 10, 30));
    });

    test('PENDENTE without data_pagamento keeps paidAt null — the UI shows '
        '"Aguardando pagamento" instead of a fabricated date', () {
      final payment = PaymentModel.fromMap('pay-3', {
        'id_cliente': 'c1',
        'clientName': 'Cliente',
        'tipo': 'AGENDAMENTO',
        'valor': 80.0,
        'forma_pagamento': 'PIX',
        'status': 'PENDENTE',
      });

      expect(payment.status, PaymentStatus.pending);
      expect(payment.paidAt, isNull);
    });

    test('parses all status values', () {
      PaymentStatus statusFrom(String raw) => PaymentModel.fromMap('p', {
        'id_cliente': 'c1',
        'tipo': 'AGENDAMENTO',
        'valor': 80.0,
        'forma_pagamento': 'PIX',
        'status': raw,
      }).status;

      expect(statusFrom('PENDENTE'), PaymentStatus.pending);
      expect(statusFrom('PAGO'), PaymentStatus.paid);
      expect(statusFrom('CANCELADO'), PaymentStatus.canceled);
      expect(statusFrom('REEMBOLSADO'), PaymentStatus.refunded);
      expect(statusFrom('EM_ANALISE'), PaymentStatus.underReview);
      expect(statusFrom('desconhecido'), PaymentStatus.pending);
    });
  });

  test('toMap/fromMap round-trip preserves all fields', () {
    final original = PaymentModel(
      id: 'pay-9',
      clientId: 'c1',
      clientName: 'Cliente',
      type: PaymentType.package,
      appointmentId: null,
      customerPackageId: 'pkg-1',
      amount: 150.0,
      method: PaymentMethod.card,
      paidAt: DateTime(2026, 5, 18, 10, 30),
      status: PaymentStatus.paid,
    );

    final restored = PaymentModel.fromMap(original.id, original.toMap());

    expect(restored.id, original.id);
    expect(restored.clientId, original.clientId);
    expect(restored.clientName, original.clientName);
    expect(restored.type, PaymentType.package);
    expect(restored.customerPackageId, 'pkg-1');
    expect(restored.amount, 150.0);
    expect(restored.method, PaymentMethod.card);
    expect(restored.paidAt, DateTime(2026, 5, 18, 10, 30));
    expect(restored.status, PaymentStatus.paid);
    expect(restored.toMap()['tipo'], 'PACOTE');
    expect(restored.toMap()['status'], 'PAGO');
  });
}
