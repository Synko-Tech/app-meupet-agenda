import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/services/idempotency.dart';

void main() {
  group('newIdempotencyKey', () {
    test('produces keys in the <epochMicros>_<sequence> format', () {
      final key = newIdempotencyKey();
      expect(RegExp(r'^\d+_\d+$').hasMatch(key), isTrue);
    });

    test('produces unique keys on consecutive calls', () {
      final first = newIdempotencyKey();
      final second = newIdempotencyKey();
      expect(second, isNot(first));
    });

    test('keys embed the current epoch in microseconds', () {
      final before = DateTime.now().microsecondsSinceEpoch;
      final key = newIdempotencyKey();
      final after = DateTime.now().microsecondsSinceEpoch;
      final stamp = int.parse(key.split('_').first);
      expect(stamp, greaterThanOrEqualTo(before));
      expect(stamp, lessThanOrEqualTo(after));
    });
  });
}
