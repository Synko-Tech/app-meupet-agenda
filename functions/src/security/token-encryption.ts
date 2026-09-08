import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from 'node:crypto';

/**
 * Token encryption at rest (AES-256-GCM).
 *
 * Seller OAuth tokens are sensitive: they grant access to the seller's
 * Mercado Pago account. They are never stored in plaintext. This module
 * encrypts them with AES-256-GCM using a master key supplied via the
 * environment (MERCADOPAGO_TOKEN_ENC_KEY). In production the master key is
 * provisioned through Firebase Secret Manager / Cloud KMS and injected as an
 * env var; the encryption primitive here is deterministic and KMS-agnostic.
 */

export const TOKEN_ENC_KEY_ENV = 'MERCADOPAGO_TOKEN_ENC_KEY';

/** 12-byte random IV per encryption; never reused as a nonce. */
const IV_LENGTH = 12;
const AUTH_TAG_LENGTH = 16;

function masterKey(): Buffer {
  const raw = process.env[TOKEN_ENC_KEY_ENV] ?? '';
  if (raw === '') {
    throw new Error(`${TOKEN_ENC_KEY_ENV} não configurada.`);
  }
  // Aceita uma chave hex de 64 chars OU um raw secret com entropia minima.
  // Uma passphrase curta (ex.: "minha-chave") seria hasheada e daria uma
  // falsa sensacao de seguranca: AES-256-GCM com chave derivada de poucos
  // bytes e trivialmente quebravel por forca bruta. Falhamos fechado.
  const hex = /^[0-9a-fA-F]{64}$/.test(raw);
  if (hex) {
    return Buffer.from(raw, 'hex');
  }
  if (raw.length < 32) {
    throw new Error(
      `${TOKEN_ENC_KEY_ENV} deve ser uma chave hex de 64 caracteres ou um segredo com pelo menos 32 bytes.`,
    );
  }
  return createHash('sha256').update(raw).digest();
}

/** Encrypts a UTF-8 secret. Returns base64(iv + ciphertext + authTag). */
export function encryptSecret(plain: string): string {
  const key = masterKey();
  const iv = randomBytes(IV_LENGTH);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return Buffer.concat([iv, ciphertext, authTag]).toString('base64');
}

/** Decrypts the output of [encryptSecret]. Throws on tampering. */
export function decryptSecret(payload: string): string {
  const key = masterKey();
  const raw = Buffer.from(payload, 'base64');
  if (raw.length < IV_LENGTH + AUTH_TAG_LENGTH) {
    throw new Error('Payload criptografado inválido.');
  }
  const iv = raw.subarray(0, IV_LENGTH);
  const authTag = raw.subarray(raw.length - AUTH_TAG_LENGTH);
  const ciphertext = raw.subarray(IV_LENGTH, raw.length - AUTH_TAG_LENGTH);
  const decipher = createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(authTag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8');
}

/** True when a master key is configured (used to fail closed in prod). */
export function isTokenEncryptionConfigured(): boolean {
  return (process.env[TOKEN_ENC_KEY_ENV] ?? '') !== '';
}
