/**
 * Unit tests for CNPJ validation helpers and the HMAC claim id.
 *
 * Pure functions: no emulator required.
 */

import 'mocha';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { HttpsError } from 'firebase-functions/v2/https';

import {
  normalizeCnpj,
  validateCnpj,
  validatePhone,
  cnpjClaimId,
} from '../src/businesses/cnpj-validation';

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

const CNPJ_A = '11222333000181';
const CNPJ_A_MASKED = '11.222.333/0001-81';
const CNPJ_B = '12345678000195';

describe('normalizeCnpj', () => {
  it('converte CNPJ formatado para apenas digitos', () => {
    assert.equal(normalizeCnpj(CNPJ_A_MASKED), CNPJ_A);
  });

  it('aceita CNPJ canonico', () => {
    assert.equal(normalizeCnpj(CNPJ_A), CNPJ_A);
  });

  it('ignora espacos em volta', () => {
    assert.equal(normalizeCnpj(` ${CNPJ_A_MASKED} `), CNPJ_A);
  });

  it('rejeita valor que nao e string', () => {
    expectInvalidArgument(() => normalizeCnpj(11222333000181));
  });

  it('rejeita quantidade de digitos diferente de 14', () => {
    expectInvalidArgument(() => normalizeCnpj('1122233300018'));
    expectInvalidArgument(() => normalizeCnpj('112223330001811'));
    expectInvalidArgument(() => normalizeCnpj(''));
  });
});

describe('validateCnpj', () => {
  it('valida CNPJ formatado e retorna canonico', () => {
    assert.equal(validateCnpj(CNPJ_A_MASKED), CNPJ_A);
  });

  it('valida CNPJ canonico', () => {
    assert.equal(validateCnpj(CNPJ_A), CNPJ_A);
    assert.equal(validateCnpj(CNPJ_B), CNPJ_B);
  });

  it('rejeita checksum incorreto', () => {
    expectInvalidArgument(() => validateCnpj('11222333000182'));
    expectInvalidArgument(() => validateCnpj('12345678000196'));
  });

  it('rejeita sequencia repetida', () => {
    expectInvalidArgument(() => validateCnpj('11111111111111'));
    expectInvalidArgument(() => validateCnpj('00000000000000'));
    expectInvalidArgument(() => validateCnpj('99999999999999'));
  });

  it('rejeita valor nao string', () => {
    expectInvalidArgument(() => validateCnpj(null));
    expectInvalidArgument(() => validateCnpj(undefined));
  });
});

describe('validatePhone', () => {
  it('canoniza telefone com mascara', () => {
    assert.equal(validatePhone('(11) 91234-5678'), '11912345678');
  });

  it('aceita 10 ou 11 digitos', () => {
    assert.equal(validatePhone('11912345678'), '11912345678');
    assert.equal(validatePhone('1191234567'), '1191234567');
  });

  it('retorna undefined para ausente/vazio', () => {
    assert.equal(validatePhone(undefined), undefined);
    assert.equal(validatePhone(null), undefined);
    assert.equal(validatePhone(''), undefined);
  });

  it('rejeita quantidade de digitos invalida', () => {
    expectInvalidArgument(() => validatePhone('119123456'));
    expectInvalidArgument(() => validatePhone('119123456789'));
    expectInvalidArgument(() => validatePhone(12345));
  });
});

describe('cnpjClaimId', () => {
  it('e deterministico para mesmo CNPJ e secret', () => {
    assert.equal(cnpjClaimId(CNPJ_A, 'secret-a'), cnpjClaimId(CNPJ_A, 'secret-a'));
  });

  it('diverge quando o secret muda', () => {
    assert.notEqual(cnpjClaimId(CNPJ_A, 'secret-a'), cnpjClaimId(CNPJ_A, 'secret-b'));
  });

  it('diverge quando o CNPJ muda', () => {
    assert.notEqual(cnpjClaimId(CNPJ_A, 'secret-a'), cnpjClaimId(CNPJ_B, 'secret-a'));
  });

  it('usa HMAC-SHA256 em hex minusculo (64 chars)', () => {
    const id = cnpjClaimId(CNPJ_A, 'test-secret');
    assert.match(id, /^[0-9a-f]{64}$/);
  });

  it('corresponde a referencia calculada com createHmac', () => {
    const expected = createHmac('sha256', 'test-secret')
      .update(CNPJ_A)
      .digest('hex');
    assert.equal(cnpjClaimId(CNPJ_A, 'test-secret'), expected);
  });
});