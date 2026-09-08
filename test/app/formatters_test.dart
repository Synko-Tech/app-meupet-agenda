import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/formatters.dart';

void main() {
  group('formatCurrency', () {
    test('formats whole values with comma', () {
      expect(formatCurrency(80), 'R\$ 80,00');
      expect(formatCurrency(0), 'R\$ 0,00');
    });

    test('formats decimal values with comma', () {
      expect(formatCurrency(150.5), 'R\$ 150,50');
      expect(formatCurrency(150.55), 'R\$ 150,55');
    });
  });

  group('formatDate', () {
    test('pads day and month', () {
      expect(formatDate(DateTime(2026, 5, 3)), '03/05/2026');
      expect(formatDate(DateTime(2026, 12, 30)), '30/12/2026');
    });
  });

  group('formatShortDate', () {
    test('returns day/month without year', () {
      expect(formatShortDate(DateTime(2026, 5, 3)), '03/05');
    });
  });

  group('formatTime', () {
    test('pads hour and minute', () {
      expect(formatTime(DateTime(2026, 5, 3, 9, 5)), '09:05');
      expect(formatTime(DateTime(2026, 5, 3, 23, 59)), '23:59');
    });
  });

  group('formatDayKey', () {
    test('produces a zero-padded yyyy-MM-dd key', () {
      expect(formatDayKey(DateTime(2026, 5, 3)), '2026-05-03');
    });
  });

  group('weekdayLabel', () {
    test('maps Monday through Sunday to abbreviated labels', () {
      expect(weekdayLabel(DateTime(2026, 5, 4)), 'Seg');
      expect(weekdayLabel(DateTime(2026, 5, 5)), 'Ter');
      expect(weekdayLabel(DateTime(2026, 5, 6)), 'Qua');
      expect(weekdayLabel(DateTime(2026, 5, 7)), 'Qui');
      expect(weekdayLabel(DateTime(2026, 5, 8)), 'Sex');
      expect(weekdayLabel(DateTime(2026, 5, 9)), 'Sab');
      expect(weekdayLabel(DateTime(2026, 5, 10)), 'Dom');
    });
  });

  group('isoForCall', () {
    test('encodes a local DateTime as a UTC instant with Z suffix', () {
      final local = DateTime(2026, 5, 18, 10, 0);
      final iso = isoForCall(local);
      expect(iso, local.toUtc().toIso8601String());
      expect(iso.endsWith('Z'), isTrue);
    });

    test('round-trips through DateTime.parse to the same instant', () {
      final local = DateTime(2026, 5, 18, 10, 0);
      expect(DateTime.parse(isoForCall(local)).toUtc(), local.toUtc());
    });
  });
}
