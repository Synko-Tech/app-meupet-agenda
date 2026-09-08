import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/models/service_model.dart';
import 'package:meupet_agenda_app/services/business_hours.dart';

void main() {
  test('ServiceModel converts Firestore style fields', () {
    final service = ServiceModel.fromMap('servico-1', {
      'nome': 'Banho e tosa',
      'descricao': 'Servico completo',
      'duracao_minutos': 60,
      'valor': 80.0,
      'ativo': true,
    });

    expect(service.id, 'servico-1');
    expect(service.name, 'Banho e tosa');
    expect(service.durationMinutes, 60);
    expect(service.price, 80.0);
    expect(service.toMap()['nome'], 'Banho e tosa');
  });

  test('BusinessHours applies banho and tosa restricted schedule', () {
    final monday = DateTime(2026, 5, 18);
    final saturday = DateTime(2026, 5, 23);

    expect(
      BusinessHours.isInsideBookingHours(
        time: '16:00',
        serviceName: 'Banho',
        date: monday,
      ),
      isTrue,
    );
    expect(
      BusinessHours.isInsideBookingHours(
        time: '16:30',
        serviceName: 'Tosa',
        date: monday,
      ),
      isFalse,
    );
    expect(
      BusinessHours.isInsideBookingHours(
        time: '10:00',
        serviceName: 'Tosa',
        date: saturday,
      ),
      isTrue,
    );
    expect(
      BusinessHours.isInsideBookingHours(
        time: '10:30',
        serviceName: 'Banho',
        date: saturday,
      ),
      isFalse,
    );
  });

  test('BusinessHours hides night schedule slots', () {
    expect(BusinessHours.shouldShowInSchedule('17:30'), isTrue);
    expect(BusinessHours.shouldShowInSchedule('18:00'), isFalse);
    expect(BusinessHours.shouldShowInSchedule('19:30'), isFalse);
  });
}
