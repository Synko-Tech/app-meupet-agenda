import { createHmac } from 'node:crypto';

import { apiError } from '../shared/errors';

const CNPJ_DIGITS = 14;
const REPEATED_SEQUENCE_REGEX = /^(\d)\1{13}$/;

/** Weights for the first verifier digit (12 base digits). */
const FIRST_WEIGHTS = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
/** Weights for the second verifier digit (12 base digits + first DV). */
const SECOND_WEIGHTS = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];

/**
 * Extrai apenas os digitos do CNPJ. Aceita CNPJ formatado
 * (`12.345.678/0001-90`) ou canonico, rejeitando qualquer valor que nao
 * resulte em exatamente 14 digitos.
 */
export function normalizeCnpj(value: unknown): string {
  if (typeof value !== 'string') {
    throw apiError('invalid-argument', 'CNPJ invalido.');
  }
  const digits = value.replace(/\D/g, '');
  if (digits.length !== CNPJ_DIGITS) {
    throw apiError('invalid-argument', 'CNPJ invalido.');
  }
  return digits;
}

/**
 * Valida o CNPJ (14 digitos canonicos): verifica os dois digitos
 * verificadores e rejeita sequencias repetidas (`11.111.111/1111-11`).
 * Retorna o CNPJ canonico para ser usado como chave (ex.: HMAC).
 */
export function validateCnpj(value: unknown): string {
  const digits = normalizeCnpj(value);
  if (REPEATED_SEQUENCE_REGEX.test(digits)) {
    throw apiError('invalid-argument', 'CNPJ invalido.');
  }
  if (!verifyDigit(digits.slice(0, 12), FIRST_WEIGHTS, digits[12])) {
    throw apiError('invalid-argument', 'CNPJ invalido.');
  }
  if (!verifyDigit(digits.slice(0, 13), SECOND_WEIGHTS, digits[13])) {
    throw apiError('invalid-argument', 'CNPJ invalido.');
  }
  return digits;
}

/**
 * Telefone opcional (comercial ou pessoal). Aceita qualquer formatacao,
 * canonizado para 10 ou 11 digitos.
 */
export function validatePhone(value: unknown): string | undefined {
  if (value === undefined || value === null || value === '') {
    return undefined;
  }
  if (typeof value !== 'string') {
    throw apiError('invalid-argument', 'Telefone invalido.');
  }
  const digits = value.replace(/\D/g, '');
  if (digits.length !== 10 && digits.length !== 11) {
    throw apiError('invalid-argument', 'Telefone invalido.');
  }
  return digits;
}

/** Computes one verifier digit: weighted sum, `11 - remainder`, 0 when >= 10. */
function verifyDigit(
  base: string,
  weights: number[],
  expected: string,
): boolean {
  let sum = 0;
  for (let i = 0; i < base.length; i++) {
    sum += Number(base[i]) * weights[i];
  }
  const remainder = sum % 11;
  const digit = remainder < 2 ? 0 : 11 - remainder;
  return digit === Number(expected);
}

/**
 * Id da claim de unicidade do CNPJ (`cnpjClaims/{id}`): HMAC-SHA256 em hex
 * do CNPJ canonico usando o secret `CNPJ_HMAC_SECRET`. O CNPJ nunca e
 * armazenado em claro.
 */
export function cnpjClaimId(cnpj: string, secret: string): string {
  return createHmac('sha256', secret).update(cnpj).digest('hex');
}