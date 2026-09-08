import 'package:flutter_test/flutter_test.dart';
import 'package:meupet_agenda_app/services/profile_validators.dart';

void main() {
  group('digitsOnly', () {
    test('removes mask characters', () {
      expect(digitsOnly('529.982.247-25'), '52998224725');
      expect(digitsOnly('(43) 9999-0000'), '4399990000');
    });

    test('returns empty string when there are no digits', () {
      expect(digitsOnly('abc'), '');
      expect(digitsOnly(''), '');
    });
  });

  group('isValidCpf', () {
    test('accepts a valid formatted CPF', () {
      expect(isValidCpf('529.982.247-25'), isTrue);
      expect(isValidCpf('111.444.777-35'), isTrue);
    });

    test('accepts a valid digits-only CPF', () {
      expect(isValidCpf('52998224725'), isTrue);
    });

    test('rejects CPF with wrong verifier digits', () {
      expect(isValidCpf('529.982.247-20'), isFalse);
      expect(isValidCpf('52998224720'), isFalse);
      expect(isValidCpf('111.444.777-36'), isFalse);
    });

    test('rejects repeated sequences', () {
      expect(isValidCpf('111.111.111-11'), isFalse);
      expect(isValidCpf('00000000000'), isFalse);
      expect(isValidCpf('999.999.999-99'), isFalse);
    });

    test('rejects wrong length and non-digit input', () {
      expect(isValidCpf(''), isFalse);
      expect(isValidCpf('123'), isFalse);
      expect(isValidCpf('5299822472'), isFalse);
      expect(isValidCpf('abc'), isFalse);
    });
  });

  group('validateRequiredCpf', () {
    test('requires a value', () {
      expect(validateRequiredCpf(null), 'Campo obrigatorio');
      expect(validateRequiredCpf(''), 'Campo obrigatorio');
      expect(validateRequiredCpf('   '), 'Campo obrigatorio');
    });

    test('accepts valid formatted and canonical CPF', () {
      expect(validateRequiredCpf('529.982.247-25'), isNull);
      expect(validateRequiredCpf('52998224725'), isNull);
    });

    test('rejects invalid CPF', () {
      expect(validateRequiredCpf('111.111.111-11'), 'CPF invalido');
      expect(validateRequiredCpf('529.982.247-20'), 'CPF invalido');
    });
  });

  group('validateRequiredCep', () {
    test('requires a value', () {
      expect(validateRequiredCep(null), 'Campo obrigatorio');
      expect(validateRequiredCep(''), 'Campo obrigatorio');
      expect(validateRequiredCep('   '), 'Campo obrigatorio');
    });

    test('accepts formatted and canonical 8-digit CEP', () {
      expect(validateRequiredCep('86010-170'), isNull);
      expect(validateRequiredCep('86010170'), isNull);
    });

    test('rejects CEP without exactly 8 digits', () {
      expect(validateRequiredCep('8601-017'), 'CEP invalido');
      expect(validateRequiredCep('860101701'), 'CEP invalido');
      expect(validateRequiredCep('86010-17'), 'CEP invalido');
      expect(validateRequiredCep('abc'), 'CEP invalido');
    });
  });

  group('validateRequiredUf', () {
    test('requires a value', () {
      expect(validateRequiredUf(null), 'Campo obrigatorio');
      expect(validateRequiredUf(''), 'Campo obrigatorio');
      expect(validateRequiredUf('   '), 'Campo obrigatorio');
    });

    test('accepts exactly two letters regardless of case', () {
      expect(validateRequiredUf('PR'), isNull);
      expect(validateRequiredUf('sp'), isNull);
      expect(validateRequiredUf(' PR '), isNull);
    });

    test('rejects anything that is not exactly two letters', () {
      expect(validateRequiredUf('P'), 'UF invalida');
      expect(validateRequiredUf('PRS'), 'UF invalida');
      expect(validateRequiredUf('P1'), 'UF invalida');
      expect(validateRequiredUf('12'), 'UF invalida');
      expect(validateRequiredUf(''), 'Campo obrigatorio');
    });
  });

  group('formatCpf', () {
    test('formats 11 digits with the CPF mask', () {
      expect(formatCpf('52998224725'), '529.982.247-25');
      expect(formatCpf('529.982.247-25'), '529.982.247-25');
    });

    test('formats partial input progressively', () {
      expect(formatCpf('529'), '529');
      expect(formatCpf('52998'), '529.98');
      expect(formatCpf('5299822472'), '529.982.247-2');
    });

    test('ignores extra digits beyond 11', () {
      expect(formatCpf('52998224725123'), '529.982.247-25');
    });
  });

  group('formatCep', () {
    test('formats 8 digits with the CEP mask', () {
      expect(formatCep('86010170'), '86010-170');
      expect(formatCep('86010-170'), '86010-170');
    });

    test('formats partial input progressively without trailing separator', () {
      expect(formatCep('8601'), '8601');
      expect(formatCep('86010'), '86010');
      expect(formatCep('860101'), '86010-1');
    });

    test('ignores extra digits beyond 8', () {
      expect(formatCep('8601017012'), '86010-170');
    });
  });

  group('isValidCnpj', () {
    test('accepts a valid formatted CNPJ', () {
      expect(isValidCnpj('11.222.333/0001-81'), isTrue);
      expect(isValidCnpj('12.345.678/0001-95'), isTrue);
    });

    test('accepts a valid digits-only CNPJ', () {
      expect(isValidCnpj('11222333000181'), isTrue);
    });

    test('rejects CNPJ with wrong verifier digits', () {
      expect(isValidCnpj('11.222.333/0001-82'), isFalse);
      expect(isValidCnpj('11222333000182'), isFalse);
      expect(isValidCnpj('12.345.678/0001-96'), isFalse);
    });

    test('rejects repeated sequences', () {
      expect(isValidCnpj('11.111.111/1111-11'), isFalse);
      expect(isValidCnpj('00000000000000'), isFalse);
      expect(isValidCnpj('99.999.999/9999-99'), isFalse);
    });

    test('rejects wrong length and non-digit input', () {
      expect(isValidCnpj(''), isFalse);
      expect(isValidCnpj('1234'), isFalse);
      expect(isValidCnpj('1122233300018'), isFalse);
      expect(isValidCnpj('abc'), isFalse);
    });
  });

  group('validateRequiredCnpj', () {
    test('requires a value', () {
      expect(validateRequiredCnpj(null), 'Campo obrigatorio');
      expect(validateRequiredCnpj(''), 'Campo obrigatorio');
      expect(validateRequiredCnpj('   '), 'Campo obrigatorio');
    });

    test('accepts valid formatted and canonical CNPJ', () {
      expect(validateRequiredCnpj('11.222.333/0001-81'), isNull);
      expect(validateRequiredCnpj('11222333000181'), isNull);
    });

    test('rejects invalid CNPJ', () {
      expect(validateRequiredCnpj('11.111.111/1111-11'), 'CNPJ invalido');
      expect(validateRequiredCnpj('11.222.333/0001-82'), 'CNPJ invalido');
    });
  });

  group('formatCnpj', () {
    test('formats 14 digits with the CNPJ mask', () {
      expect(formatCnpj('11222333000181'), '11.222.333/0001-81');
      expect(formatCnpj('11.222.333/0001-81'), '11.222.333/0001-81');
    });

    test('formats partial input progressively', () {
      expect(formatCnpj('11'), '11');
      expect(formatCnpj('11222'), '11.222');
      expect(formatCnpj('11222333'), '11.222.333');
      expect(formatCnpj('112223330001'), '11.222.333/0001');
    });

    test('ignores extra digits beyond 14', () {
      expect(formatCnpj('11222333000181123'), '11.222.333/0001-81');
    });
  });
}
