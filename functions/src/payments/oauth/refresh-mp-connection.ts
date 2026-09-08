import { getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import type { CallableRequest } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';

import { authUser, requireActiveProfile } from '../../auth/authorization';
import { requireBusinessMembership } from '../../businesses/business-authorization';
import { BUSINESS_ROLE } from '../../businesses/business-authorization';
import { apiError, wrap } from '../../shared/errors';
import { withTransaction } from '../../shared/firestore';
import { requireDocId, requireText } from '../../shared/validation';
import {
  isConnectionExpired,
  readMerchantConnection,
  writeMerchantConnectionInTransaction,
} from '../merchant-connection-store';
import { createMpOAuthClient } from './oauth-client';
import type { MpOAuthClient } from './oauth-client';
import { getMpClientId } from './start-mp-connection';
import { MP_CLIENT_SECRET_ENV } from './mp-oauth-callback';

export interface RefreshMpConnectionArgs {
  businessId: string;
}

export interface RefreshMpConnectionResult {
  refreshed: boolean;
}

/**
 * Refreshes the seller's access token using the stored refresh token.
 * OWNER only. Mercado Pago rotates the refresh token, so the new pair
 * (access + refresh) is persisted and the summary timestamps are updated.
 */
export async function refreshMpConnectionHandler(
  request: CallableRequest<RefreshMpConnectionArgs>,
  oauth: MpOAuthClient = createMpOAuthClient(),
): Promise<RefreshMpConnectionResult> {
  const { uid } = authUser(request);
  const db = getFirestore();

  const args = (request.data ?? {}) as Partial<RefreshMpConnectionArgs>;
  const businessId = requireDocId(args.businessId, 'businessId');

  await requireActiveProfile(db, uid);
  await requireBusinessMembership(db, uid, businessId, new Set([BUSINESS_ROLE.OWNER]));

  const connection = await readMerchantConnection(businessId);
  if (connection === null) {
    throw apiError('not-found', 'Conta Mercado Pago não conectada.');
  }
  if (!isConnectionExpired(connection)) {
    return { refreshed: false };
  }

  const clientId = getMpClientId();
  const clientSecret = process.env[MP_CLIENT_SECRET_ENV] ?? '';
  if (clientId === '' || clientSecret === '') {
    throw apiError('unavailable', 'Integração de pagamentos não configurada.');
  }

  try {
    const tokens = await oauth.refreshToken({
      clientId,
      clientSecret,
      refreshToken: connection.refreshToken,
    });
    const now = Date.now();
    // As duas escritas (tokens + summary) sao atomicas: se o refresh do token
    // grava mas o summary falha (ou vice-versa), a transacao desfaz tudo e o
    // summary nunca fica stale em relacao aos tokens.
    await withTransaction(db, async (transaction) => {
      writeMerchantConnectionInTransaction(transaction, {
        businessId,
        collectorId: connection.collectorId,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        publicKey: tokens.publicKey,
        liveMode: tokens.liveMode,
        expiresAt: now + tokens.expiresIn * 1000,
        connectedAt: connection.connectedAt,
        updatedAt: now,
      });
      transaction.update(db.doc(`businesses/${businessId}`), {
        merchantSummary: {
          status: 'CONECTADO',
          collectorId: connection.collectorId,
          liveMode: tokens.liveMode,
          connectedAt: connection.connectedAt,
          expiresAt: now + tokens.expiresIn * 1000,
        },
      });
    });
    return { refreshed: true };
  } catch (error) {
    throw apiError(
      'unavailable',
      'Não foi possível renovar a conexão. Reconecte a conta no perfil.',
    );
  }
}

/** Public callable (registered via functions/src/index.ts). */
const MP_CLIENT_SECRET = defineSecret('MERCADOPAGO_CLIENT_SECRET');

/** Public callable (registered via functions/src/index.ts). */
export const refreshMpConnection = onCall(
  { secrets: [MP_CLIENT_SECRET] },
  wrap(refreshMpConnectionHandler),
);
