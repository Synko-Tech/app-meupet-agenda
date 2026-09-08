/**
 * Thin Mercado Pago OAuth wrapper (server-to-server).
 *
 * Only the authorization-code exchange and the refresh_token grant are
 * needed: Checkout Pro marketplace integrations obtain a per-seller
 * access_token via OAuth and use it to create preferences on the seller's
 * behalf. The redirect flow itself is a browser redirect — this module only
 * talks to https://api.mercadopago.com/oauth/token.
 */

export interface MpOAuthTokenResult {
  accessToken: string;
  refreshToken: string;
  publicKey: string;
  userId: string;
  liveMode: boolean;
  expiresIn: number;
}

export interface MpOAuthClient {
  exchangeCode(input: {
    clientId: string;
    clientSecret: string;
    code: string;
    redirectUri: string;
  }): Promise<MpOAuthTokenResult>;
  refreshToken(input: {
    clientId: string;
    clientSecret: string;
    refreshToken: string;
  }): Promise<MpOAuthTokenResult>;
}

const OAUTH_TOKEN_URL = 'https://api.mercadopago.com/oauth/token';

function parseTokenResponse(body: Record<string, unknown>): MpOAuthTokenResult {
  const accessToken = typeof body.access_token === 'string' ? body.access_token : '';
  const refreshToken = typeof body.refresh_token === 'string' ? body.refresh_token : '';
  const publicKey = typeof body.public_key === 'string' ? body.public_key : '';
  const userId = typeof body.user_id === 'string' ? body.user_id : '';
  const expiresIn = typeof body.expires_in === 'number' ? body.expires_in : 0;
  if (accessToken === '' || refreshToken === '' || userId === '') {
    throw new Error('Resposta OAuth do Mercado Pago incompleta.');
  }
  return {
    accessToken,
    refreshToken,
    publicKey,
    userId,
    liveMode: body.live_mode === true,
    expiresIn,
  };
}

/** Real OAuth client using the Node 22 global fetch. */
export function createMpOAuthClient(): MpOAuthClient {
  return {
    async exchangeCode(input) {
      const response = await fetch(OAUTH_TOKEN_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          grant_type: 'authorization_code',
          client_id: input.clientId,
          client_secret: input.clientSecret,
          code: input.code,
          redirect_uri: input.redirectUri,
        }),
      });
      if (!response.ok) {
        const detail = await response.text().catch(() => '');
        throw new Error(`Falha no OAuth (${response.status}): ${detail}`);
      }
      return parseTokenResponse((await response.json()) as Record<string, unknown>);
    },

    async refreshToken(input) {
      const response = await fetch(OAUTH_TOKEN_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          grant_type: 'refresh_token',
          client_id: input.clientId,
          client_secret: input.clientSecret,
          refresh_token: input.refreshToken,
        }),
      });
      if (!response.ok) {
        const detail = await response.text().catch(() => '');
        throw new Error(`Falha ao renovar token (${response.status}): ${detail}`);
      }
      return parseTokenResponse((await response.json()) as Record<string, unknown>);
    },
  };
}
