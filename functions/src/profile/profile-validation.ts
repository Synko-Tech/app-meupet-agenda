import { apiError } from '../shared/errors';
import { requireText } from '../shared/validation';

/**
 * Endereco postal validado e canonizado, gravado em `userPrivate/{uid}`.
 */
export interface PostalAddressRecord {
  postalCode: string;
  street: string;
  number: string;
  complement?: string;
  neighborhood: string;
  city: string;
  state: string;
  country: string;
}

const CPF_DIGITS = 11;
const CEP_DIGITS = 8;
const UF_REGEX = /^[A-Z]{2}$/;
const REPEATED_SEQUENCE_REGEX = /^(\d)\1{10}$/;

/**
 * Extrai apenas os digitos do CPF. Aceita CPF formatado
 * (`123.456.789-09`) ou canonico, rejeitando qualquer valor que nao
 * resulte em exatamente 11 digitos.
 */
export function normalizeCpf(value: unknown): string {
  if (typeof value !== 'string') {
    throw apiError('invalid-argument', 'CPF invalido.');
  }
  const digits = value.replace(/\D/g, '');
  if (digits.length !== CPF_DIGITS) {
    throw apiError('invalid-argument', 'CPF invalido.');
  }
  return digits;
}

/**
 * Valida o CPF (11 digitos canonicos): verifica os dois digitos
 * verificadores e rejeita sequencias repetidas (`111.111.111-11`).
 * Retorna o CPF canonico para ser usado como chave (ex.: HMAC).
 */
export function validateCpf(value: unknown): string {
  const digits = normalizeCpf(value);
  if (REPEATED_SEQUENCE_REGEX.test(digits)) {
    throw apiError('invalid-argument', 'CPF invalido.');
  }
  for (let i = 0; i < 2; i++) {
    let sum = 0;
    for (let j = 0; j < 9 + i; j++) {
      sum += Number(digits[j]) * (10 + i - j);
    }
    const remainder = sum % 11;
    const expected = remainder < 2 ? 0 : 11 - remainder;
    if (expected !== Number(digits[9 + i])) {
      throw apiError('invalid-argument', 'CPF invalido.');
    }
  }
  return digits;
}

/**
 * Valida e canoniza o endereco postal. O CEP vira 8 digitos, a UF vira
 * duas letras maiusculas e o complemento em branco e tratado como
 * ausente.
 */
export function validateAddress(value: unknown): PostalAddressRecord {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw apiError('invalid-argument', 'Endereco invalido.');
  }
  const record = value as Record<string, unknown>;
  if (record.country !== 'BR') {
    throw apiError('invalid-argument', 'Pais invalido.');
  }
  const complement = normalizeComplement(record.complement);
  return {
    postalCode: normalizePostalCode(record.postalCode),
    street: requireText(record.street, 'logradouro'),
    number: requireText(record.number, 'numero'),
    neighborhood: requireText(record.neighborhood, 'bairro'),
    city: requireText(record.city, 'cidade'),
    state: normalizeState(record.state),
    country: 'BR',
    ...(complement !== undefined ? { complement } : {}),
  };
}

function normalizePostalCode(value: unknown): string {
  if (typeof value !== 'string') {
    throw apiError('invalid-argument', 'CEP invalido.');
  }
  const digits = value.replace(/\D/g, '');
  if (digits.length !== CEP_DIGITS) {
    throw apiError('invalid-argument', 'CEP invalido.');
  }
  return digits;
}

function normalizeState(value: unknown): string {
  if (typeof value !== 'string') {
    throw apiError('invalid-argument', 'UF invalida.');
  }
  const state = value.trim().toUpperCase();
  if (!UF_REGEX.test(state)) {
    throw apiError('invalid-argument', 'UF invalida.');
  }
  return state;
}

function normalizeComplement(value: unknown): string | undefined {
  if (value === undefined || value === null || value === '') {
    return undefined;
  }
  if (typeof value !== 'string') {
    throw apiError('invalid-argument', 'Campo complemento invalido.');
  }
  const complement = value.trim();
  return complement === '' ? undefined : complement;
}
