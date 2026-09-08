import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/services/business_hours.dart';

void main() {
  // Fixed dates: 2026-05-18 is a Monday, 2026-05-23 a Saturday,
  // 2026-05-24 a Sunday.
  final monday = DateTime(2026, 5, 18);
  final saturday = DateTime(2026, 5, 23);
  final sunday = DateTime(2026, 5, 24);

  group('isInsideBookingHours', () {
    test('is closed on Sunday at any time', () {
      for (final time in ['08:00', '09:00', '12:00', '18:00']) {
        expect(
          BusinessHours.isInsideBookingHours(
            time: time,
            serviceName: 'Consulta',
            date: sunday,
          ),
          isFalse,
          reason: 'time $time on Sunday should be rejected',
        );
      }
    });

    test(
      'weekday closes at 18:00 for regular services (17:59 is the last slot)',
      () {
        expect(
          BusinessHours.isInsideBookingHours(
            time: '17:59',
            serviceName: 'Consulta',
            date: monday,
          ),
          isTrue,
        );
        expect(
          BusinessHours.isInsideBookingHours(
            time: '18:00',
            serviceName: 'Consulta',
            date: monday,
          ),
          isFalse,
        );
      },
    );

    test('weekday opens at 08:00 for regular services', () {
      expect(
        BusinessHours.isInsideBookingHours(
          time: '08:00',
          serviceName: 'Consulta',
          date: monday,
        ),
        isTrue,
      );
      expect(
        BusinessHours.isInsideBookingHours(
          time: '07:59',
          serviceName: 'Consulta',
          date: monday,
        ),
        isFalse,
      );
    });

    test('Saturday regular services close at 12:00', () {
      expect(
        BusinessHours.isInsideBookingHours(
          time: '12:00',
          serviceName: 'Consulta',
          date: saturday,
        ),
        isTrue,
      );
      expect(
        BusinessHours.isInsideBookingHours(
          time: '12:30',
          serviceName: 'Consulta',
          date: saturday,
        ),
        isFalse,
      );
    });

    test('Saturday bath/grooming is restricted to 08:00-10:00 inclusive', () {
      expect(
        BusinessHours.isInsideBookingHours(
          time: '08:00',
          serviceName: 'Banho',
          date: saturday,
        ),
        isTrue,
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

    test('weekday bath/grooming closes at 16:00', () {
      expect(
        BusinessHours.isInsideBookingHours(
          time: '16:00',
          serviceName: 'Banho e Tosa',
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
    });
  });

  group('shouldShowInSchedule', () {
    test('hides slots from 18:00 onwards', () {
      expect(BusinessHours.shouldShowInSchedule('17:30'), isTrue);
      expect(BusinessHours.shouldShowInSchedule('17:59'), isTrue);
      expect(BusinessHours.shouldShowInSchedule('18:00'), isFalse);
      expect(BusinessHours.shouldShowInSchedule('19:30'), isFalse);
    });
  });

  group('isBathOrGrooming / normalize', () {
    test('detects bath and grooming regardless of case and accents', () {
      expect(BusinessHours.isBathOrGrooming('Banho'), isTrue);
      expect(BusinessHours.isBathOrGrooming('banho'), isTrue);
      expect(BusinessHours.isBathOrGrooming('Tosa'), isTrue);
      expect(BusinessHours.isBathOrGrooming('Banho e tosa'), isTrue);
      expect(BusinessHours.isBathOrGrooming('Banho e tosa premium'), isTrue);
      expect(BusinessHours.isBathOrGrooming('Consulta'), isFalse);
      expect(BusinessHours.isBathOrGrooming('Vacina'), isFalse);
    });
  });
}
