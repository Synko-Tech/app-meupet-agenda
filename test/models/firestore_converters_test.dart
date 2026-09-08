import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/models/firestore_converters.dart';

void main() {
  group('dateTimeFromFirestore', () {
    test('converts a Timestamp to DateTime', () {
      final ts = Timestamp.fromDate(DateTime(2026, 5, 18, 10, 30));
      expect(dateTimeFromFirestore(ts), DateTime(2026, 5, 18, 10, 30));
    });

    test('passes a DateTime through unchanged', () {
      final dt = DateTime(2026, 5, 18, 10, 30);
      expect(dateTimeFromFirestore(dt), dt);
    });

    test('parses an ISO string', () {
      expect(
        dateTimeFromFirestore('2026-05-18T10:30:00.000'),
        DateTime(2026, 5, 18, 10, 30),
      );
    });

    test('uses the fallback for an invalid string', () {
      final fallback = DateTime(2025, 1, 1);
      expect(dateTimeFromFirestore('nao-e-data', fallback: fallback), fallback);
    });

    test('uses the fallback for null', () {
      final fallback = DateTime(2025, 1, 1);
      expect(dateTimeFromFirestore(null, fallback: fallback), fallback);
    });

    test('falls back to now when no fallback is given', () {
      final before = DateTime.now();
      final result = dateTimeFromFirestore(null);
      final after = DateTime.now();
      expect(result.isBefore(before), isFalse);
      expect(result.isAfter(after), isFalse);
    });
  });

  group('dateTimeRequiredFromFirestore', () {
    test('converts a Timestamp', () {
      final ts = Timestamp.fromDate(DateTime(2026, 5, 18, 10, 30));
      expect(dateTimeRequiredFromFirestore(ts), DateTime(2026, 5, 18, 10, 30));
    });

    test('parses an ISO string', () {
      expect(
        dateTimeRequiredFromFirestore('2026-05-18T10:30:00.000'),
        DateTime(2026, 5, 18, 10, 30),
      );
    });

    test('throws for null without fallback', () {
      expect(
        () => dateTimeRequiredFromFirestore(null, field: 'validUntil'),
        throwsStateError,
      );
    });

    test('throws for invalid string without fallback', () {
      expect(
        () => dateTimeRequiredFromFirestore('nao-e-data', field: 'startAt'),
        throwsStateError,
      );
    });

    test('uses fallback when provided', () {
      final fallback = DateTime(2025, 1, 1);
      expect(
        dateTimeRequiredFromFirestore(
          null,
          field: 'validUntil',
          fallback: fallback,
        ),
        fallback,
      );
    });
  });

  group('doubleFromFirestore', () {
    test('converts an int', () {
      expect(doubleFromFirestore(80), 80.0);
    });

    test('passes a double through', () {
      expect(doubleFromFirestore(80.5), 80.5);
    });

    test('parses a dot-separated string', () {
      expect(doubleFromFirestore('150.5'), 150.5);
    });

    test('parses a comma-separated string', () {
      expect(doubleFromFirestore('150,5'), 150.5);
    });

    test('returns 0 for an unparseable string', () {
      expect(doubleFromFirestore('abc'), 0);
    });

    test('returns 0 for null', () {
      expect(doubleFromFirestore(null), 0);
    });
  });

  group('intFromFirestore', () {
    test('converts an int', () {
      expect(intFromFirestore(5), 5);
    });

    test('truncates a double', () {
      expect(intFromFirestore(5.9), 5);
    });

    test('parses a string', () {
      expect(intFromFirestore('7'), 7);
    });

    test('returns 0 for an unparseable string', () {
      expect(intFromFirestore('abc'), 0);
    });

    test('returns 0 for null', () {
      expect(intFromFirestore(null), 0);
    });
  });
}
