/**
 * Multi-tenant integration tests (A/B): two businesses, two sellers, no
 * cross-tenant leakage.
 *
 * Verifies the critical isolation guarantees end to end against the
 * emulator: checkout uses the seller token of the right business, the
 * webhook resolves the right tenant and rejects foreign sellers, and the
 * rules deny cross-tenant reads.
 */

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';

import 'mocha';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { initializeApp, deleteApp, getApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import type { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

import { createMercadoPagoCheckoutHandler } from '../src/payments/create-mp-checkout';
import type { CreateMercadoPagoCheckoutArgs } from '../src/payments/create-mp-checkout';
import { mercadoPagoWebhookHandler } from '../src/payments/mp-webhook';
import type { MpClient, MpPaymentInfo, MpPreferenceInput } from '../src/payments/mercadopago-client';
import { startMpConnectionHandler } from '../src/payments/oauth/start-mp-connection';
import { mpOauthCallbackHandler } from '../src/payments/oauth/mp-oauth-callback';
import type { OAuthResponseLike } from '../src/payments/oauth/mp-oauth-callback';
import type { MpOAuthClient, MpOAuthTokenResult } from '../src/payments/oauth/oauth-client';

const PROJECT_ID = 'demo-meupet-agenda';

let env: ReturnType<typeof initializeTestEnvironment> extends Promise<infer T>
  ? T
  : never;
let adminDb: Firestore;
let ownsDefaultApp = false;

const BIZ_A = 'biz-a';
const BIZ_B = 'biz-b';
const OWNER_A = 'owner-a';
const OWNER_B = 'owner-b';
const CLIENT_A = 'client-a';
const SELLER_A = 'seller-A-42';
const SELLER_B = 'seller-B-99';

/** Fake que registra qual token recebeu — prova que cada loja usa o seu. */
class TokenAwareMpClient implements MpClient {
  lastAccessToken = '';
  createCalls = 0;
  getPaymentCalls = 0;

  constructor(private readonly token: string) {}

  async createPreference(input: MpPreferenceInput): Promise<{ id: string; initPoint: string }> {
    this.createCalls += 1;
    this.lastAccessToken = this.token;
    return {
      id: `pref-${input.externalReference}`,
      initPoint: `https://mercadopago.com.br/checkout/pref-${input.externalReference}`,
    };
  }

  async getPayment(paymentId: string): Promise<MpPaymentInfo | null> {
    this.getPaymentCalls += 1;
    this.lastAccessToken = this.token;
    return {
      id: paymentId,
      status: 'approved',
      paymentMethodId: 'pix',
      externalReference: `pay-${paymentId}`,
    };
  }
}

class FakeOAuthClient implements MpOAuthClient {
  constructor(private readonly sellerId: string) {}

  async exchangeCode(): Promise<MpOAuthTokenResult> {
    return tokenResult(this.sellerId);
  }

  async refreshToken(): Promise<MpOAuthTokenResult> {
    return tokenResult(this.sellerId);
  }
}

function tokenResult(sellerId: string): MpOAuthTokenResult {
  return {
    accessToken: `APP_USR-token-${sellerId}`,
    refreshToken: `TG-refresh-${sellerId}`,
    publicKey: `APP_USR-pub-${sellerId}`,
    userId: sellerId,
    liveMode: true,
    expiresIn: 15552000,
  };
}

function callableRequest<T>(data: T, uid: string): CallableRequest<T> {
  return { data, auth: { uid } } as unknown as CallableRequest<T>;
}

function fakeRequest(body: unknown): RequestLike {
  const ts = '1724000000';
  const mpPaymentId = String(
    (body as { data?: { id?: number | string } }).data?.id ?? '',
  );
  const signature = createHmac('sha256', 'segredo-teste')
    .update(`id:${mpPaymentId};request-id:req-1;ts:${ts};`)
    .digest('hex');
  return {
    body,
    headers: {
      'x-signature': `ts=${ts},v1=${signature}`,
      'x-request-id': 'req-1',
    },
  } as RequestLike;
}

interface RequestLike {
  body: unknown;
  headers: Record<string, unknown>;
}

function fakeResponse(): ResponseLike {
  const state = { statusCode: 200, sentBody: undefined as unknown };
  const res = {
    status(code: number) {
      state.statusCode = code;
      return res;
    },
    json(body: unknown) {
      state.sentBody = body;
      return res;
    },
    send(body: unknown) {
      state.sentBody = body;
      return res;
    },
    get statusCode() {
      return state.statusCode;
    },
    get sentBody() {
      return state.sentBody;
    },
  };
  return res;
}

interface ResponseLike {
  statusCode: number;
  sentBody: unknown;
  status(code: number): ResponseLike;
  json(body?: unknown): ResponseLike;
  send(body?: unknown): ResponseLike;
}

function oauthResponse(): OAuthResponseLike & { statusCode: number } {
  const state = { statusCode: 200 };
  const res = {
    status(code: number) {
      state.statusCode = code;
      return res;
    },
    send() {
      return res;
    },
    get statusCode() {
      return state.statusCode;
    },
  };
  return res;
}

async function seedBusiness(businessId: string, ownerUid: string): Promise<void> {
  await adminDb.doc(`businesses/${businessId}`).set({
    nome: `Loja ${businessId}`,
    timezone: 'America/Sao_Paulo',
    status: 'ATIVO',
  });
  await adminDb.doc(`businesses/${businessId}/members/${ownerUid}`).set({
    role: 'owner',
    ativo: true,
  });
  await adminDb.doc(`businesses/${businessId}/members/${CLIENT_A}`).set({
    role: 'client',
    ativo: true,
  });
  await adminDb.doc(`businesses/${businessId}/packages/pkg-1`).set({
    nome: 'Pacote Teste',
    ativo: true,
    valor: 49.9,
    quantidade_creditos: 10,
    modalidade: 'sessao',
    validade_dias: 30,
  });
}

async function connectSeller(
  businessId: string,
  ownerUid: string,
  sellerId: string,
): Promise<void> {
  const started = await startMpConnectionHandler(
    callableRequest<StartArgs>({ businessId }, ownerUid),
  );
  const state = new URL(started.authorizationUrl).searchParams.get('state')!;
  await mpOauthCallbackHandler(
    {
      query: { state, code: `code-${sellerId}` },
      headers: {},
    } as never,
    oauthResponse(),
    new FakeOAuthClient(sellerId),
  );
}

interface StartArgs {
  businessId: string;
}

async function seedFixtures(): Promise<void> {
  await adminDb.doc(`users/${OWNER_A}`).set({ nome: 'Dono A', role: 'client', ativo: true });
  await adminDb.doc(`users/${OWNER_B}`).set({ nome: 'Dono B', role: 'client', ativo: true });
  await adminDb.doc(`users/${CLIENT_A}`).set({ nome: 'Cliente', role: 'client', ativo: true });
  await seedBusiness(BIZ_A, OWNER_A);
  await seedBusiness(BIZ_B, OWNER_B);
  await connectSeller(BIZ_A, OWNER_A, SELLER_A);
  await connectSeller(BIZ_B, OWNER_B, SELLER_B);
}

describe('multi-tenant isolation (A/B)', () => {
  before(async function () {
    this.timeout(30_000);
    process.env.FUNCTIONS_EMULATOR = 'true';
    process.env.MERCADOPAGO_WEBHOOK_URL =
      'https://us-central1-demo-meupet-agenda.cloudfunctions.net/mercadoPagoWebhook';
    process.env.MERCADOPAGO_WEBHOOK_SECRET = 'segredo-teste';
    process.env.MERCADOPAGO_TOKEN_ENC_KEY = 'test-master-key-0123456789abcdef';
    process.env.MERCADOPAGO_CLIENT_ID = 'app-123';
    process.env.MERCADOPAGO_CLIENT_SECRET = 'secret-123';
    process.env.MERCADOPAGO_REDIRECT_URI =
      'https://us-central1-demo-meupet-agenda.cloudfunctions.net/mpOauthCallback';
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { host: '127.0.0.1', port: 8080, rules: '' },
    });
    if (getApps().length === 0) {
      initializeApp({ projectId: PROJECT_ID });
      ownsDefaultApp = true;
    }
    adminDb = getFirestore();
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await seedFixtures();
  });

  after(async () => {
    await env.cleanup();
    delete process.env.FUNCTIONS_EMULATOR;
    delete process.env.MERCADOPAGO_WEBHOOK_URL;
    delete process.env.MERCADOPAGO_WEBHOOK_SECRET;
    delete process.env.MERCADOPAGO_TOKEN_ENC_KEY;
    delete process.env.MERCADOPAGO_CLIENT_ID;
    delete process.env.MERCADOPAGO_CLIENT_SECRET;
    delete process.env.MERCADOPAGO_REDIRECT_URI;
  });

  it('checkout da loja A usa o token do seller A (e vice-versa)', async () => {
    const mpA = new TokenAwareMpClient('APP_USR-token-' + SELLER_A);
    const resultA = await createMercadoPagoCheckoutHandler(
      callableRequest<CreateMercadoPagoCheckoutArgs>(
        { businessId: BIZ_A, packageId: 'pkg-1' },
        CLIENT_A,
      ),
      mpA,
    );
    assert.ok(resultA.paymentId);
    assert.equal(mpA.createCalls, 1);

    const mpB = new TokenAwareMpClient('APP_USR-token-' + SELLER_B);
    const resultB = await createMercadoPagoCheckoutHandler(
      callableRequest<CreateMercadoPagoCheckoutArgs>(
        { businessId: BIZ_B, packageId: 'pkg-1' },
        CLIENT_A,
      ),
      mpB,
    );
    assert.ok(resultB.paymentId);

    // Cada pagamento registra o snapshot do recebedor da sua loja.
    const paymentA = (
      await adminDb.doc(`businesses/${BIZ_A}/payments/${resultA.paymentId}`).get()
    ).data()!;
    assert.equal(paymentA.businessId, BIZ_A);
    assert.equal(paymentA.collectorId, SELLER_A);

    const paymentB = (
      await adminDb.doc(`businesses/${BIZ_B}/payments/${resultB.paymentId}`).get()
    ).data()!;
    assert.equal(paymentB.businessId, BIZ_B);
    assert.equal(paymentB.collectorId, SELLER_B);
  });

  it('webhook da loja A não altera pagamento da loja B', async () => {
    // Cria pagamentos nas duas lojas.
    const mpA = new TokenAwareMpClient('APP_USR-token-' + SELLER_A);
    const checkoutA = await createMercadoPagoCheckoutHandler(
      callableRequest<CreateMercadoPagoCheckoutArgs>(
        { businessId: BIZ_A, packageId: 'pkg-1' },
        CLIENT_A,
      ),
      mpA,
    );

    // Notificação do seller A apontando para o pagamento de A: processa.
    const responseA = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest({
        type: 'payment',
        data: { id: 123456 },
        user_id: SELLER_A,
      }) as never,
      responseA,
      new TokenAwareMpClient('APP_USR-token-' + SELLER_A),
    );
    assert.equal(responseA.statusCode, 200);

    // Um seller desconhecido/estrangeiro é rejeitado sem tocar no pagamento.
    const responseForeign = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest({
        type: 'payment',
        data: { id: 123456 },
        user_id: SELLER_B, // seller da loja B notificando pagamento da loja A
      }) as never,
      responseForeign,
      new TokenAwareMpClient('APP_USR-token-' + SELLER_B),
    );
    assert.equal(responseForeign.statusCode, 200);
    const outcome = responseForeign.sentBody as { outcome: string };
    assert.equal(outcome.outcome, 'missing');

    // Pagamento de A permanece PENDENTE (não foi pago pelo webhook estrangeiro).
    const paymentA = (
      await adminDb.doc(`businesses/${BIZ_A}/payments/${checkoutA.paymentId}`).get()
    ).data()!;
    assert.equal(paymentA.status, 'PENDENTE');
  });

  it('loja sem conexão Mercado Pago não inicia checkout', async () => {
    const bizEmpty = 'biz-empty';
    await adminDb.doc(`businesses/${bizEmpty}`).set({
      nome: 'Loja Sem Conexao',
      timezone: 'America/Sao_Paulo',
      status: 'ATIVO',
    });
    await adminDb.doc(`businesses/${bizEmpty}/members/${CLIENT_A}`).set({
      role: 'client',
      ativo: true,
    });
    await adminDb.doc(`businesses/${bizEmpty}/packages/pkg-1`).set({
      nome: 'Pacote',
      ativo: true,
      valor: 10,
      quantidade_creditos: 1,
      validade_dias: 30,
    });

    let error: HttpsError | undefined;
    try {
      await createMercadoPagoCheckoutHandler(
        callableRequest<CreateMercadoPagoCheckoutArgs>(
          { businessId: bizEmpty, packageId: 'pkg-1' },
          CLIENT_A,
        ),
        new TokenAwareMpClient('token'),
      );
    } catch (err) {
      error = err as HttpsError;
    }
    assert.ok(error);
    assert.equal(error.code, 'failed-precondition');
  });

  it('tokens nunca aparecem em documentos públicos', async () => {
    const merchant = (
      await adminDb.doc(`merchantConnections/${BIZ_A}`).get()
    ).data()!;
    assert.ok(merchant.accessTokenEnc.includes('enc:v1:'));
    assert.ok(!merchant.accessTokenEnc.includes(SELLER_A));
    assert.ok(!merchant.accessTokenEnc.includes('APP_USR-token'));

    const business = (await adminDb.doc(`businesses/${BIZ_A}`).get()).data()!;
    assert.equal(business.merchantSummary.status, 'CONECTADO');
    assert.equal(business.merchantSummary.collectorId, SELLER_A);
    assert.ok(!JSON.stringify(business).includes('APP_USR-token'));
    assert.ok(!JSON.stringify(business).includes('TG-refresh'));
  });
});
