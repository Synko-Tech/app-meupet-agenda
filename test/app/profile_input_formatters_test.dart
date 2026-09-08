import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/app/profile_input_formatters.dart';
import 'package:meupet_agenda_app/services/profile_validators.dart';

void main() {
  TextEditingValue apply(TextInputFormatter formatter, String text) {
    return formatter.formatEditUpdate(
      const TextEditingValue(),
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
  }

  group('CpfInputFormatter', () {
    test('masks digits as the user types', () {
      final formatter = CpfInputFormatter();
      expect(apply(formatter, '529').text, '529');
      expect(apply(formatter, '5299').text, '529.9');
      expect(apply(formatter, '52998224725').text, '529.982.247-25');
    });

    test('normalizes already masked pasted input', () {
      final formatter = CpfInputFormatter();
      expect(apply(formatter, '529.982.247-25').text, '529.982.247-25');
      expect(apply(formatter, 'abc52998224725xyz').text, '529.982.247-25');
    });

    test('limits length to 11 digits', () {
      final formatter = CpfInputFormatter();
      expect(apply(formatter, '52998224725123').text, '529.982.247-25');
    });

    test('mask does not alter the canonical digits', () {
      final formatter = CpfInputFormatter();
      final formatted = apply(formatter, '52998224725').text;
      expect(digitsOnly(formatted), '52998224725');
    });
  });

  group('CepInputFormatter', () {
    test('masks digits as the user types', () {
      final formatter = CepInputFormatter();
      expect(apply(formatter, '8601').text, '8601');
      expect(apply(formatter, '86010').text, '86010');
      expect(apply(formatter, '860101').text, '86010-1');
      expect(apply(formatter, '86010170').text, '86010-170');
    });

    test('normalizes already masked pasted input', () {
      final formatter = CepInputFormatter();
      expect(apply(formatter, '86010-170').text, '86010-170');
      expect(apply(formatter, 'abc86010170xyz').text, '86010-170');
    });

    test('limits length to 8 digits', () {
      final formatter = CepInputFormatter();
      expect(apply(formatter, '8601017012').text, '86010-170');
    });

    test('mask does not alter the canonical digits', () {
      final formatter = CepInputFormatter();
      final formatted = apply(formatter, '86010170').text;
      expect(digitsOnly(formatted), '86010170');
    });
  });

  group('CnpjInputFormatter', () {
    test('masks digits as the user types', () {
      final formatter = CnpjInputFormatter();
      expect(apply(formatter, '11').text, '11');
      expect(apply(formatter, '11222').text, '11.222');
      expect(apply(formatter, '11222333').text, '11.222.333');
      expect(apply(formatter, '112223330001').text, '11.222.333/0001');
      expect(apply(formatter, '11222333000181').text, '11.222.333/0001-81');
    });

    test('normalizes already masked pasted input', () {
      final formatter = CnpjInputFormatter();
      expect(apply(formatter, '11.222.333/0001-81').text, '11.222.333/0001-81');
      expect(apply(formatter, 'abc11222333000181xyz').text, '11.222.333/0001-81');
    });

    test('limits length to 14 digits', () {
      final formatter = CnpjInputFormatter();
      expect(apply(formatter, '11222333000181123').text, '11.222.333/0001-81');
    });

    test('mask does not alter the canonical digits', () {
      final formatter = CnpjInputFormatter();
      final formatted = apply(formatter, '11222333000181').text;
      expect(digitsOnly(formatted), '11222333000181');
    });
  });
}
