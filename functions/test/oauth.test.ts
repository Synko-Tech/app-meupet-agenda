/**
 * Emulator tests for the Mercado Pago OAuth connection flow (start /
 * callback / refresh / disconnect) and the encrypted merchant connection
 * store.
 *
 * Runs under `firebase emulators:exec --only firestore,storage,functions`.
 * The OAuth client is injected as a fake; no Mercado Pago API is touched.
 */

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';

import 'mocha';
import assert from 'node:assert/strict';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { initializeApp, deleteApp, getApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import type { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

import { startMpConnectionHandler } from '../src/payments/oauth/start-mp-connection';
import type { StartMpConnectionArgs } from '../src/payments/oauth/start-mp-connection';
import { hashState } from '../src/payments/oauth/start-mp-connection';
import { mpOauthCallbackHandler } from '../src/payments/oauth/mp-oauth-callback';
import { refreshMpConnectionHandler } from '../src/payments/oauth/refresh-mp-connection';
import { disconnectMpConnectionHandler } from '../src/payments/oauth/disconnect-mp-connection';
import { readMerchantConnection } from '../src/payments/merchant-connection-store';
import type { MpOAuthClient, MpOAuthTokenResult } from '../src/payments/oauth/oauth-client';

const PROJECT_ID = 'demo-meupet-agenda';

let env: ReturnType<typeof initializeTestEnvironment> extends Promise<infer T>
  ? T
  : never;
let adminDb: Firestore;
let ownsDefaultApp = false;

const BIZ = 'biz-1';
const OWNER = 'owner-1';
const ADMIN = 'admin-1';

function ensureDefaultApp(): void {
  if (getApps().length === 0) {
    initializeApp({ projectId: PROJECT_ID });
    ownsDefaultApp = true;
  }
}

class FakeOAuthClient implements MpOAuthClient {
  exchangeCalls = 0;
  refreshCalls = 0;
  failExchange = false;

  async exchangeCode(): Promise<MpOAuthTokenResult> {
    this.exchangeCalls += 1;
    if (this.failExchange) {
      throw new Error('Mercado Pago rejeitou o código.');
    }
    return tokenResult();
  }

  async refreshToken(): Promise<MpOAuthTokenResult> {
    this.refreshCalls += 1;
    return tokenResult();
  }
}

function tokenResult(): MpOAuthTokenResult {
  return {
    accessToken: 'APP_USR-access-123',
    refreshToken: 'TG-refresh-456',
    publicKey: 'APP_USR-pub-789',
    userId: 'seller-42',
    liveMode: true,
    expiresIn: 15552000,
  };
}

function callableRequest<T>(data: T, uid: string): CallableRequest<T> {
  return { data, auth: { uid } } as unknown as CallableRequest<T>;
}

function fakeRequest(query: Record<string, unknown>): RequestLike {
  return { query, headers: {} } as RequestLike;
}

interface RequestLike {
  query: Record<string, unknown>;
  headers: Record<string, unknown>;
}

function fakeResponse(): ResponseLike {
  const response: ResponseLike = {
    statusCode: 0,
    body: '',
    status(code: number) {
      this.statusCode = code;
      return this;
    },
    send(body: unknown) {
      this.body = typeof body === 'string' ? body : '';
      return this;
    },
  };
  return response;
}

interface ResponseLike {
  statusCode: number;
  body: string;
  status(code: number): ResponseLike;
  send(body?: unknown): ResponseLike;
}

async function seedBase(): Promise<void> {
  await adminDb.doc(`users/${OWNER}`).set({
    nome: 'Dono',
    role: 'client',
    ativo: true,
  });
  await adminDb.doc(`users/${ADMIN}`).set({
    nome: 'Admin',
    role: 'client',
    ativo: true,
  });
  await adminDb.doc(`businesses/${BIZ}`).set({
    nome: 'Loja Teste',
    timezone: 'America/Sao_Paulo',
    status: 'ATIVO',
  });
  await adminDb.doc(`businesses/${BIZ}/members/${OWNER}`).set({
    role: 'owner',
    ativo: true,
  });
  await adminDb.doc(`businesses/${BIZ}/members/${ADMIN}`).set({
    role: 'admin',
    ativo: true,
  });
}

describe('Mercado Pago OAuth connection', () => {
  before(async function () {
    this.timeout(30_000);
    process.env.MERCADOPAGO_CLIENT_ID = 'app-123';
    process.env.MERCADOPAGO_CLIENT_SECRET = 'secret-123';
    process.env.MERCADOPAGO_REDIRECT_URI =
      'https://us-central1-demo-meupet-agenda.cloudfunctions.net/mpOauthCallback';
    process.env.MERCADOPAGO_TOKEN_ENC_KEY = 'test-master-key-0123456789abcdef';
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { host: '127.0.0.1', port: 8080, rules: '' },
    });
  });

  beforeEach(async () => {
    await env.clearFirestore();
    ensureDefaultApp();
    adminDb = getFirestore();
    await seedBase();
  });

  after(async () => {
    await env.cleanup();
    delete process.env.MERCADOPAGO_CLIENT_ID;
    delete process.env.MERCADOPAGO_CLIENT_SECRET;
    delete process.env.MERCADOPAGO_REDIRECT_URI;
    delete process.env.MERCADOPAGO_TOKEN_ENC_KEY;
  });

  describe('startMpConnection', () => {
    it('owner recebe a URL de autorização e o state é gravado hashed', async () => {
      const result = await startMpConnectionHandler(
        callableRequest<StartMpConnectionArgs>({ businessId: BIZ }, OWNER),
      );

      assert.ok(result.authorizationUrl.startsWith(
        'https://auth.mercadopago.com/authorization?',
      ));
      assert.ok(result.authorizationUrl.includes('client_id=app-123'));
      assert.ok(result.authorizationUrl.includes('response_type=code'));
      assert.ok(result.authorizationUrl.includes('platform_id=mp'));
      assert.ok(result.authorizationUrl.includes('redirect_uri='));

      const state = new URL(result.authorizationUrl).searchParams.get('state')!;
      assert.ok(state.length >= 32);

      // O state cru nunca vai pro Firestore: somente o hash.
      const docs = await adminDb.collection('oauthStates').get();
      assert.equal(docs.size, 1);
      assert.equal(docs.docs[0].id, hashState(state));
      const data = docs.docs[0].data();
      assert.equal(data.uid, OWNER);
      assert.equal(data.businessId, BIZ);
    });

    it('admin (não owner) é bloqueado', async () => {
      let error: HttpsError | undefined;
      try {
        await startMpConnectionHandler(
          callableRequest<StartMpConnectionArgs>({ businessId: BIZ }, ADMIN),
        );
      } catch (err) {
        error = err as HttpsError;
      }
      assert.ok(error);
      assert.equal(error.code, 'permission-denied');
    });

    it('falha quando a integração não está configurada', async () => {
      delete process.env.MERCADOPAGO_CLIENT_ID;
      let error: HttpsError | undefined;
      try {
        await startMpConnectionHandler(
          callableRequest<StartMpConnectionArgs>({ businessId: BIZ }, OWNER),
        );
      } catch (err) {
        error = err as HttpsError;
      }
      process.env.MERCADOPAGO_CLIENT_ID = 'app-123';
      assert.ok(error);
      assert.equal(error.code, 'unavailable');
    });
  });

  describe('mpOauthCallback', () => {
    it('troca o código, grava a conexão criptografada e publica o resumo', async () => {
      const started = await startMpConnectionHandler(
        callableRequest<StartMpConnectionArgs>({ businessId: BIZ }, OWNER),
      );
      const state = new URL(started.authorizationUrl).searchParams.get('state')!;

      const oauth = new FakeOAuthClient();
      const response = fakeResponse();
      await mpOauthCallbackHandler(
        fakeRequest({ state, code: 'code-xyz' }) as never,
        response,
        oauth,
      );

      assert.equal(response.statusCode, 200);
      assert.equal(oauth.exchangeCalls, 1);

      const connection = await readMerchantConnection(BIZ);
      assert.ok(connection);
      assert.equal(connection.collectorId, 'seller-42');
      assert.equal(connection.accessToken, 'APP_USR-access-123');
      assert.equal(connection.refreshToken, 'TG-refresh-456');
      assert.equal(connection.liveMode, true);
      assert.ok(connection.expiresAt > Date.now());

      // O documento NUNCA guarda o token em texto puro.
      const raw = (await adminDb.doc(`merchantConnections/${BIZ}`).get()).data()!;
      assert.ok(typeof raw.accessTokenEnc === 'string');
      assert.ok(!raw.accessTokenEnc.includes('APP_USR-access-123'));

      const business = (await adminDb.doc(`businesses/${BIZ}`).get()).data()!;
      assert.equal(business.merchantSummary.status, 'CONECTADO');
      assert.equal(business.merchantSummary.collectorId, 'seller-42');

      // O state foi consumido (single-use).
      const states = await adminDb.collection('oauthStates').get();
      assert.equal(states.size, 0);
    });

    it('state expirado ou inexistente é rejeitado', async () => {
      const oauth = new FakeOAuthClient();
      const response = fakeResponse();
      await mpOauthCallbackHandler(
        fakeRequest({ state: 'state-fantasma', code: 'code-x' }) as never,
        response,
        oauth,
      );

      assert.equal(response.statusCode, 400);
      assert.equal(oauth.exchangeCalls, 0);
    });

    it('parâmetros ausentes são rejeitados', async () => {
      const response = fakeResponse();
      await mpOauthCallbackHandler(
        fakeRequest({}) as never,
        response,
        new FakeOAuthClient(),
      );
      assert.equal(response.statusCode, 400);
    });
  });

  describe('refreshMpConnection', () => {
    it('renova o token quando expirado e rotaciona o refresh token', async () => {
      const started = await startMpConnectionHandler(
        callableRequest<StartMpConnectionArgs>({ businessId: BIZ }, OWNER),
      );
      const state = new URL(started.authorizationUrl).searchParams.get('state')!;
      const oauth = new FakeOAuthClient();
      await mpOauthCallbackHandler(
        fakeRequest({ state, code: 'code-xyz' }) as never,
        fakeResponse(),
        oauth,
      );

      // Expira a conexão.
      await adminDb.doc(`merchantConnections/${BIZ}`).update({ expiresAt: 1 });

      const result = await refreshMpConnectionHandler(
        callableRequest<RefreshArgs>({ businessId: BIZ }, OWNER),
        oauth,
      );
      assert.equal(result.refreshed, true);
      assert.equal(oauth.refreshCalls, 1);

      const refreshed = await readMerchantConnection(BIZ);
      assert.ok(refreshed);
      assert.equal(refreshed.refreshToken, 'TG-refresh-456');
      assert.ok(refreshed.expiresAt > Date.now());
    });

    it('não renova quando o token ainda é válido', async () => {
      const started = await startMpConnectionHandler(
        callableRequest<StartMpConnectionArgs>({ businessId: BIZ }, OWNER),
      );
      const state = new URL(started.authorizationUrl).searchParams.get('state')!;
      const oauth = new FakeOAuthClient();
      await mpOauthCallbackHandler(
        fakeRequest({ state, code: 'code-xyz' }) as never,
        fakeResponse(),
        oauth,
      );

      const result = await refreshMpConnectionHandler(
        callableRequest<RefreshArgs>({ businessId: BIZ }, OWNER),
        oauth,
      );
      assert.equal(result.refreshed, false);
      assert.equal(oauth.refreshCalls, 0);
    });

    it('sem conexão retorna not-found', async () => {
      let error: HttpsError | undefined;
      try {
        await refreshMpConnectionHandler(
          callableRequest<RefreshArgs>({ businessId: BIZ }, OWNER),
          new FakeOAuthClient(),
        );
      } catch (err) {
        error = err as HttpsError;
      }
      assert.ok(error);
      assert.equal(error.code, 'not-found');
    });
  });

  describe('disconnectMpConnection', () => {
    it('owner desconecta e o resumo volta a DESCONECTADO', async () => {
      const started = await startMpConnectionHandler(
        callableRequest<StartMpConnectionArgs>({ businessId: BIZ }, OWNER),
      );
      const state = new URL(started.authorizationUrl).searchParams.get('state')!;
      await mpOauthCallbackHandler(
        fakeRequest({ state, code: 'code-xyz' }) as never,
        fakeResponse(),
        new FakeOAuthClient(),
      );

      const result = await disconnectMpConnectionHandler(
        callableRequest<DisconnectArgs>({ businessId: BIZ }, OWNER),
      );
      assert.equal(result.disconnected, true);

      const connection = await readMerchantConnection(BIZ);
      assert.equal(connection, null);

      const business = (await adminDb.doc(`businesses/${BIZ}`).get()).data()!;
      assert.equal(business.merchantSummary.status, 'DESCONECTADO');
    });

    it('admin (não owner) é bloqueado', async () => {
      let error: HttpsError | undefined;
      try {
        await disconnectMpConnectionHandler(
          callableRequest<DisconnectArgs>({ businessId: BIZ }, ADMIN),
        );
      } catch (err) {
        error = err as HttpsError;
      }
      assert.ok(error);
      assert.equal(error.code, 'permission-denied');
    });
  });
});

interface RefreshArgs {
  businessId: string;
}

interface DisconnectArgs {
  businessId: string;
}
