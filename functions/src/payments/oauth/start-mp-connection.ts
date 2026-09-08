import { randomBytes, createHash } from 'node:crypto';

import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import type { CallableRequest } from 'firebase-functions/v2/https';

import { authUser, requireActiveProfile } from '../../auth/authorization';
import { requireBusinessMembership } from '../../businesses/business-authorization';
import { BUSINESS_ROLE } from '../../businesses/business-authorization';
import { apiError, wrap } from '../../shared/errors';
import { requireDocId, requireText } from '../../shared/validation';

export interface StartMpConnectionArgs {
  businessId: string;
}

export interface StartMpConnectionResult {
  /** Mercado Pago authorization URL to open in the browser. */
  authorizationUrl: string;
}

export const MP_CLIENT_ID_ENV = 'MERCADOPAGO_CLIENT_ID';
export const MP_REDIRECT_URI_ENV = 'MERCADOPAGO_REDIRECT_URI';

const STATE_TTL_MS = 15 * 60 * 1000; // 15 minutes
const AUTHORIZATION_URL = 'https://auth.mercadopago.com/authorization';

export function getMpClientId(): string {
  return process.env[MP_CLIENT_ID_ENV] ?? '';
}

export function getMpRedirectUri(): string {
  return process.env[MP_REDIRECT_URI_ENV] ?? '';
}

/** Hashes the OAuth `state` so the raw value never touches Firestore. */
export function hashState(state: string): string {
  return createHash('sha256').update(state).digest('hex');
}

/** Builds the official authorization URL (OAuth flow for Checkout Pro). */
export function buildAuthorizationUrl(state: string, redirectUri: string): string {
  const params = new URLSearchParams({
    client_id: getMpClientId(),
    response_type: 'code',
    platform_id: 'mp',
    state,
    redirect_uri: redirectUri,
  });
  return `${AUTHORIZATION_URL}?${params.toString()}`;
}

/**
 * Starts the Mercado Pago OAuth connection for a business. OWNER only.
 *
 * Creates a short-lived, single-use `state` (stored hashed in oauthStates,
 * which the client SDK can never read) bound to uid + businessId, and
 * returns the official authorization URL. The seller authorizes in the
 * browser; the callback exchanges the code and stores the encrypted tokens.
 */
export async function startMpConnectionHandler(
  request: CallableRequest<StartMpConnectionArgs>,
): Promise<StartMpConnectionResult> {
  const { uid } = authUser(request);
  const db = getFirestore();

  const args = (request.data ?? {}) as Partial<StartMpConnectionArgs>;
  const businessId = requireDocId(args.businessId, 'businessId');

  await requireActiveProfile(db, uid);
  await requireBusinessMembership(db, uid, businessId, new Set([BUSINESS_ROLE.OWNER]));

  const clientId = getMpClientId();
  const redirectUri = getMpRedirectUri();
  if (clientId === '' || redirectUri === '') {
    throw apiError(
      'unavailable',
      'Integração de pagamentos não configurada. Contate o suporte.',
    );
  }

  const state = randomBytes(32).toString('hex');
  const expiresAt = Date.now() + STATE_TTL_MS;
  await db.doc(`oauthStates/${hashState(state)}`).set({
    uid,
    businessId,
    expiresAt,
    createdAt: FieldValue.serverTimestamp(),
  });

  return { authorizationUrl: buildAuthorizationUrl(state, redirectUri) };
}

/** Public callable (registered via functions/src/index.ts). */
export const startMpConnection = onCall(wrap(startMpConnectionHandler));
