/**
 * Unit tests for the HMAC-based CPF claim id.
 *
 * Pure function: no emulator required.
 */

import 'mocha';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';

import { cpfClaimId } from '../src/profile/cpf-claim';

describe('cpfClaimId', () => {
  it('e deterministico para mesmo CPF e secret', () => {
    assert.equal(cpfClaimId('12345678909', 'secret-a'), cpfClaimId('12345678909', 'secret-a'));
  });

  it('diverge quando o secret muda', () => {
    assert.notEqual(cpfClaimId('12345678909', 'secret-a'), cpfClaimId('12345678909', 'secret-b'));
  });

  it('diverge quando o CPF muda', () => {
    assert.notEqual(cpfClaimId('12345678909', 'secret-a'), cpfClaimId('98765432100', 'secret-a'));
  });

  it('usa HMAC-SHA256 em hex minusculo (64 chars)', () => {
    const id = cpfClaimId('12345678909', 'test-secret');
    assert.match(id, /^[0-9a-f]{64}$/);
  });

  it('corresponde a referencia calculada com createHmac', () => {
    const expected = createHmac('sha256', 'test-secret')
      .update('12345678909')
      .digest('hex');
    assert.equal(cpfClaimId('12345678909', 'test-secret'), expected);
  });
});
