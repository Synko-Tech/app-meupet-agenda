import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { onRequest } from 'firebase-functions/v2/https';
import type { Request } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';

import { logger } from 'firebase-functions';
import {
  isConnectionExpired,
  readMerchantConnection,
  writeMerchantConnection,
  publishMerchantSummary,
} from '../merchant-connection-store';
import { createMpOAuthClient } from './oauth-client';
import type { MpOAuthClient } from './oauth-client';
import {
  getMpClientId,
  getMpRedirectUri,
  hashState,
  MP_CLIENT_ID_ENV,
  MP_REDIRECT_URI_ENV,
} from './start-mp-connection';

const MP_CLIENT_SECRET_ENV = 'MERCADOPAGO_CLIENT_SECRET';

function getMpClientSecret(): string {
  return process.env[MP_CLIENT_SECRET_ENV] ?? '';
}

/** Minimal Express-like response surface (structural: express.Response satisfies it). */
export interface OAuthResponseLike {
  status(code: number): OAuthResponseLike;
  send(body?: unknown): OAuthResponseLike;
}

/**
 * OAuth callback (browser redirect from Mercado Pago after the seller
 * authorizes). Not an authenticated callable — the `state` binds the browser
 * session to uid + businessId.
 *
 * 1. Validates + consumes the single-use `state` (stored hashed).
 * 2. Exchanges the authorization code for access/refresh tokens.
 * 3. Stores the connection encrypted and publishes the safe summary.
 *
 * Renders a simple HTML page telling the seller to return to the app.
 */
export async function mpOauthCallbackHandler(
  request: Request,
  response: OAuthResponseLike,
  oauth: MpOAuthClient = createMpOAuthClient(),
): Promise<void> {
  const rawState = typeof request.query['state'] === 'string'
    ? request.query['state']
    : '';
  const code = typeof request.query['code'] === 'string'
    ? request.query['code']
    : '';

  if (rawState === '' || code === '') {
    response.status(400).send(htmlPage('Falha na conexão', 'Parâmetros OAuth ausentes.'));
    return;
  }

  const db = getFirestore();
  const stateDoc = db.doc(`oauthStates/${hashState(rawState)}`);

  try {
    // Consume the state exactly once, atomically.
    const binding = await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(stateDoc);
      if (!snap.exists) {
        return null;
      }
      const data = snap.data()!;
      const expiresAt = typeof data.expiresAt === 'number' ? data.expiresAt : 0;
      if (expiresAt < Date.now()) {
        return null; // expired: leave the doc for TTL cleanup, treat as missing
      }
      const uid = typeof data.uid === 'string' ? data.uid : '';
      const businessId = typeof data.businessId === 'string' ? data.businessId : '';
      if (uid === '' || businessId === '') {
        return null;
      }
      transaction.delete(stateDoc);
      return { uid, businessId };
    });

    if (binding === null) {
      response.status(400).send(htmlPage('Falha na conexão', 'Sessão expirada ou inválida. Tente novamente.'));
      return;
    }

    const clientId = getMpClientId();
    const clientSecret = getMpClientSecret();
    const redirectUri = getMpRedirectUri();
    if (clientId === '' || clientSecret === '' || redirectUri === '') {
      logger.error('OAuth Mercado Pago não configurado', {
        clientId: clientId === '' ? 'missing' : 'ok',
        secret: clientSecret === '' ? 'missing' : 'ok',
        redirect: redirectUri === '' ? 'missing' : 'ok',
      });
      response.status(500).send(htmlPage('Falha na conexão', 'Integração não configurada.'));
      return;
    }

    const tokens = await oauth.exchangeCode({
      clientId,
      clientSecret,
      code,
      redirectUri,
    });

    const now = Date.now();
    await writeMerchantConnection({
      businessId: binding.businessId,
      collectorId: tokens.userId,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      publicKey: tokens.publicKey,
      liveMode: tokens.liveMode,
      expiresAt: now + tokens.expiresIn * 1000,
      connectedAt: now,
      updatedAt: now,
    });
    await publishMerchantSummary(binding.businessId, {
      status: 'CONECTADO',
      collectorId: tokens.userId,
      liveMode: tokens.liveMode,
      connectedAt: now,
      expiresAt: now + tokens.expiresIn * 1000,
    });

    response.status(200).send(
      htmlPage(
        'Conta conectada',
        'Você já pode voltar ao app. Seus pagamentos agora serão recebidos nesta conta.',
      ),
    );
  } catch (error) {
    logger.error('Falha no callback OAuth Mercado Pago', error);
    response.status(500).send(
      htmlPage('Falha na conexão', 'Não foi possível conectar a conta. Tente novamente.'),
    );
  }
}

function htmlPage(title: string, message: string): string {
  return `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>
  body{font-family:system-ui,sans-serif;background:#f6f7fb;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
  .card{background:#fff;border-radius:16px;padding:32px;max-width:420px;text-align:center;box-shadow:0 10px 30px rgba(0,0,0,.08)}
  h1{font-size:22px;margin:0 0 10px} p{color:#555;margin:0}
</style></head><body><div class="card"><h1>${title}</h1><p>${message}</p></div></body></html>`;
}

/** Public HTTP endpoint (registered via functions/src/index.ts). */
const MP_CLIENT_SECRET = defineSecret(MP_CLIENT_SECRET_ENV);

/** Public HTTP endpoint (registered via functions/src/index.ts). */
export const mpOauthCallback = onRequest(
  { secrets: [MP_CLIENT_SECRET] },
  mpOauthCallbackHandler,
);

export { MP_CLIENT_SECRET_ENV, MP_CLIENT_ID_ENV, MP_REDIRECT_URI_ENV };
