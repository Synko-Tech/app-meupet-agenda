import { apiError } from './errors';

/**
 * Requires a non-blank string. Returns the TRIMMED value so callers store
 * canonical keys (a padded value must never break idempotency replay).
 */
export function requireText(value: unknown, field: string): string {
  if (typeof value !== 'string' || value.trim() === '') {
    throw apiError('invalid-argument', `Campo ${field} é obrigatório.`);
  }
  return value.trim();
}

/**
 * Optional idempotency key. Returns undefined when absent, otherwise the
 * TRIMMED value (padding must not fork the replay path). Rejects blank,
 * over-long, or slash-bearing keys so they can never collide with a
 * Firestore doc id path segment.
 */
export function optionalIdempotencyKey(value: unknown): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== 'string' || value.trim() === '') {
    throw apiError('invalid-argument', 'Campo idempotencyKey inválido.');
  }
  const trimmed = value.trim();
  if (trimmed.length > 1500 || trimmed.includes('/')) {
    throw apiError('invalid-argument', 'Campo idempotencyKey inválido.');
  }
  return trimmed;
}

/**
 * Requires a safe Firestore document id: non-blank, trimmed, and free of
 * characters that would break path segment construction (`/`, `\`, spaces,
 * control chars) or encourage traversal. Used for ids that become part of
 * document paths (businessId, professionalId, serviceId, packageId, ...).
 */
export function requireDocId(value: unknown, field: string): string {
  if (typeof value !== 'string' || value.trim() === '') {
    throw apiError('invalid-argument', `Campo ${field} é obrigatório.`);
  }
  const trimmed = value.trim();
  if (
    trimmed.length > 100 ||
    /[\/\\\s\x00-\x1f]/.test(trimmed) ||
    trimmed === '.' ||
    trimmed === '..'
  ) {
    throw apiError(
      'invalid-argument',
      `Campo ${field} contém caracteres inválidos.`,
    );
  }
  return trimmed;
}
