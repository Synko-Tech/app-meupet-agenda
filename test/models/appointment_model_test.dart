import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/models/appointment_model.dart';

void main() {
  group('AppointmentStatus.firestoreValue', () {
    test('maps every status to its firestore string', () {
      expect(AppointmentStatus.scheduled.firestoreValue, 'AGENDADO');
      expect(AppointmentStatus.confirmed.firestoreValue, 'CONFIRMADO');
      expect(AppointmentStatus.completed.firestoreValue, 'CONCLUIDO');
      expect(AppointmentStatus.canceled.firestoreValue, 'CANCELADO');
    });
  });

  group('AppointmentStatus.label', () {
    test('exposes a display label per status', () {
      expect(AppointmentStatus.scheduled.label, 'Agendado');
      expect(AppointmentStatus.confirmed.label, 'Confirmado');
      expect(AppointmentStatus.completed.label, 'Concluido');
      expect(AppointmentStatus.canceled.label, 'Cancelado');
    });
  });

  group('AppointmentStatus.fromFirestore', () {
    test('parses every known status case-insensitively', () {
      expect(
        AppointmentStatus.fromFirestore('CONFIRMADO'),
        AppointmentStatus.confirmed,
      );
      expect(
        AppointmentStatus.fromFirestore('confirmado'),
        AppointmentStatus.confirmed,
      );
      expect(
        AppointmentStatus.fromFirestore('CONCLUIDO'),
        AppointmentStatus.completed,
      );
      expect(
        AppointmentStatus.fromFirestore('CANCELADO'),
        AppointmentStatus.canceled,
      );
    });

    test('falls back to scheduled for unknown or null values', () {
      expect(
        AppointmentStatus.fromFirestore('desconhecido'),
        AppointmentStatus.scheduled,
      );
      expect(
        AppointmentStatus.fromFirestore(null),
        AppointmentStatus.scheduled,
      );
    });
  });

  group('AppointmentModel.fromMap', () {
    test('parses the Portuguese firestore keys', () {
      final start = Timestamp.fromDate(DateTime(2026, 5, 18, 10, 0));
      final end = Timestamp.fromDate(DateTime(2026, 5, 18, 11, 0));
      final appointment = AppointmentModel.fromMap('a1', {
        'id_cliente': 'c1',
        'clientName': 'Ana',
        'id_servico': 's1',
        'serviceName': 'Banho',
        'id_pacote_cliente': 'cp1',
        'data_hora_inicio': start,
        'data_hora_fim': end,
        'status': 'CONFIRMADO',
      });

      expect(appointment.id, 'a1');
      expect(appointment.clientId, 'c1');
      expect(appointment.clientName, 'Ana');
      expect(appointment.serviceId, 's1');
      expect(appointment.serviceName, 'Banho');
      expect(appointment.customerPackageId, 'cp1');
      expect(appointment.startAt, DateTime(2026, 5, 18, 10, 0));
      expect(appointment.endAt, DateTime(2026, 5, 18, 11, 0));
      expect(appointment.status, AppointmentStatus.confirmed);
    });

    test('parses the English fallback keys', () {
      final appointment = AppointmentModel.fromMap('a2', {
        'clientId': 'c2',
        'serviceId': 's2',
        'customerPackageId': 'cp2',
        'startAt': '2026-05-18T10:00:00.000',
        'endAt': '2026-05-18T11:00:00.000',
        'status': 'AGENDADO',
      });

      expect(appointment.clientId, 'c2');
      expect(appointment.serviceId, 's2');
      expect(appointment.customerPackageId, 'cp2');
      expect(appointment.startAt, DateTime(2026, 5, 18, 10, 0));
      expect(appointment.status, AppointmentStatus.scheduled);
    });

    test('applies defaults for missing fields', () {
      final appointment = AppointmentModel.fromMap('a3', {
        'data_hora_inicio': Timestamp.fromDate(DateTime(2026, 5, 18)),
        'data_hora_fim': Timestamp.fromDate(DateTime(2026, 5, 18)),
      });

      expect(appointment.clientId, '');
      expect(appointment.customerPackageId, isNull);
      expect(appointment.status, AppointmentStatus.scheduled);
      expect(appointment.createdAt, isNull);
    });
  });

  test('toMap/fromMap round-trip preserves all fields', () {
    final original = AppointmentModel(
      id: 'a9',
      clientId: 'c1',
      clientName: 'Ana',
      serviceId: 's1',
      serviceName: 'Banho',
      customerPackageId: 'cp1',
      startAt: DateTime(2026, 5, 18, 10, 0),
      endAt: DateTime(2026, 5, 18, 11, 0),
      status: AppointmentStatus.completed,
      createdAt: DateTime(2026, 5, 1),
      updatedAt: DateTime(2026, 5, 19),
    );

    final restored = AppointmentModel.fromMap(original.id, original.toMap());

    expect(restored.id, original.id);
    expect(restored.clientId, original.clientId);
    expect(restored.clientName, original.clientName);
    expect(restored.serviceId, original.serviceId);
    expect(restored.customerPackageId, 'cp1');
    expect(restored.startAt, original.startAt);
    expect(restored.endAt, original.endAt);
    expect(restored.status, AppointmentStatus.completed);
    expect(restored.updatedAt, DateTime(2026, 5, 19));
    expect(original.toMap()['status'], 'CONCLUIDO');
  });
}
