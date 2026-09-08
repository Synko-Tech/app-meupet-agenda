/**
 * Unit tests for CPF and postal address validation helpers.
 *
 * Pure functions: no emulator required.
 */

import 'mocha';
import assert from 'node:assert/strict';
import { HttpsError } from 'firebase-functions/v2/https';

import {
  normalizeCpf,
  validateCpf,
  validateAddress,
} from '../src/profile/profile-validation';
import type { PostalAddressRecord } from '../src/profile/profile-validation';

function expectInvalidArgument(fn: () => unknown): HttpsError {
  try {
    fn();
  } catch (err) {
    assert.ok(err instanceof HttpsError, 'esperava HttpsError');
    assert.equal((err as HttpsError).code, 'invalid-argument');
    return err as HttpsError;
  }
  assert.fail('esperava apiError de invalid-argument');
}

describe('normalizeCpf', () => {
  it('converte CPF formatado para apenas digitos', () => {
    assert.equal(normalizeCpf('123.456.789-09'), '12345678909');
  });

  it('aceita CPF canonico', () => {
    assert.equal(normalizeCpf('12345678909'), '12345678909');
  });

  it('ignora espacos em volta', () => {
    assert.equal(normalizeCpf(' 123.456.789-09 '), '12345678909');
  });

  it('rejeita valor que nao e string', () => {
    expectInvalidArgument(() => normalizeCpf(12345678909));
  });

  it('rejeita quantidade de digitos diferente de 11', () => {
    expectInvalidArgument(() => normalizeCpf('123456789'));
    expectInvalidArgument(() => normalizeCpf('123456789091'));
    expectInvalidArgument(() => normalizeCpf(''));
  });
});

describe('validateCpf', () => {
  it('valida CPF formatado e retorna canonico', () => {
    assert.equal(validateCpf('123.456.789-09'), '12345678909');
  });

  it('valida CPF canonico', () => {
    assert.equal(validateCpf('12345678909'), '12345678909');
  });

  it('rejeita checksum incorreto', () => {
    expectInvalidArgument(() => validateCpf('123.456.789-00'));
    expectInvalidArgument(() => validateCpf('12345678900'));
    expectInvalidArgument(() => validateCpf('98765432101'));
  });

  it('rejeita sequencia repetida', () => {
    expectInvalidArgument(() => validateCpf('111.111.111-11'));
    expectInvalidArgument(() => validateCpf('00000000000'));
    expectInvalidArgument(() => validateCpf('99999999999'));
  });

  it('rejeita valor nao string', () => {
    expectInvalidArgument(() => validateCpf(null));
    expectInvalidArgument(() => validateCpf(undefined));
  });
});

describe('validateAddress', () => {
  const validAddress = {
    postalCode: '01310-100',
    street: 'Av. Paulista',
    number: '1000',
    complement: 'Cj 12',
    neighborhood: 'Bela Vista',
    city: 'Sao Paulo',
    state: 'sp',
    country: 'BR',
  };

  it('valida endereco completo e canoniza CEP e UF', () => {
    const record: PostalAddressRecord = validateAddress(validAddress);
    assert.equal(record.postalCode, '01310100');
    assert.equal(record.state, 'SP');
    assert.equal(record.country, 'BR');
    assert.equal(record.street, 'Av. Paulista');
    assert.equal(record.number, '1000');
    assert.equal(record.complement, 'Cj 12');
    assert.equal(record.neighborhood, 'Bela Vista');
    assert.equal(record.city, 'Sao Paulo');
  });

  it('aceita endereco sem complemento', () => {
    const { complement, ...semComplemento } = validAddress;
    const record: PostalAddressRecord = validateAddress(semComplemento);
    assert.equal(record.complement, undefined);
    assert.ok(!('complement' in record));
  });

  it('aceita complemento vazio como ausente', () => {
    const record: PostalAddressRecord = validateAddress({
      ...validAddress,
      complement: '  ',
    });
    assert.equal(record.complement, undefined);
  });

  it('rejeita CEP com menos de 8 digitos', () => {
    expectInvalidArgument(() =>
      validateAddress({ ...validAddress, postalCode: '12345' }),
    );
  });

  it('rejeita CEP nao numerico', () => {
    expectInvalidArgument(() =>
      validateAddress({ ...validAddress, postalCode: 'abcdefgh' }),
    );
  });

  it('rejeita UF invalida', () => {
    expectInvalidArgument(() =>
      validateAddress({ ...validAddress, state: 'SAO' }),
    );
    expectInvalidArgument(() =>
      validateAddress({ ...validAddress, state: 's1' }),
    );
  });

  it('rejeita campos obrigatorios vazios', () => {
    expectInvalidArgument(() =>
      validateAddress({ ...validAddress, street: ' ' }),
    );
    expectInvalidArgument(() =>
      validateAddress({ ...validAddress, number: '' }),
    );
    expectInvalidArgument(() =>
      validateAddress({ ...validAddress, neighborhood: undefined }),
    );
    expectInvalidArgument(() =>
      validateAddress({ ...validAddress, city: '' }),
    );
  });

  it('rejeita pais diferente de BR', () => {
    expectInvalidArgument(() =>
      validateAddress({ ...validAddress, country: 'US' }),
    );
  });

  it('rejeita entrada que nao e objeto', () => {
    expectInvalidArgument(() => validateAddress(null));
    expectInvalidArgument(() => validateAddress('endereco'));
    expectInvalidArgument(() => validateAddress([]));
  });
});
