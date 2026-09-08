/**
 * Emulator tests for the createMercadoPagoCheckout callable (Task 16).
 *
 * Runs under `firebase emulators:exec --only firestore,storage,functions
 * --project demo-meupet-agenda 'npm test'`. The handler is invoked
 * in-process with a fake CallableRequest and an injected FakeMpClient, so
 * no Mercado Pago API is touched.
 *
 * Compiled via tsconfig.test.json into lib-test/ (see functions/README).
 */

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';

import 'mocha';
import assert from 'node:assert/strict';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { initializeApp, deleteApp, getApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import type { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

import { createMercadoPagoCheckoutHandler } from '../src/payments/create-mp-checkout';
import type { CreateMercadoPagoCheckoutArgs } from '../src/payments/create-mp-checkout';
import type { MpClient, MpPreferenceInput } from '../src/payments/mercadopago-client';

const PROJECT_ID = 'demo-meupet-agenda';

let env: ReturnType<typeof initializeTestEnvironment> extends Promise<infer T>
  ? T
  : never;
let adminApp: import('firebase-admin/app').App;
let adminDb: Firestore;

const BIZ = 'biz-1';
const uidClient = 'client-1';
const uidClient2 = 'client-2';

class FakeMpClient implements MpClient {
  preferenceCalls = 0;
  lastInput?: MpPreferenceInput;
  createError?: Error;

  async createPreference(input: MpPreferenceInput): Promise<{ id: string; initPoint: string }> {
    this.preferenceCalls += 1;
    this.lastInput = input;
    if (this.createError !== undefined) {
      throw this.createError;
    }
    return {
      id: 'pref-1',
      initPoint: 'https://mercadopago.com.br/checkout/pref-1',
    };
  }

  async getPayment(): Promise<never> {
    throw new Error('getPayment não usado neste teste');
  }
}

const seedUser = (uid: string, overrides: Record<string, unknown> = {}) => ({
  uid,
  nome: 'Nome ' + uid,
  role: 'client',
  ativo: true,
  ...overrides,
});

const seedPackage = (overrides: Record<string, unknown> = {}) => ({
  nome: 'Pacote Teste',
  ativo: true,
  valor: 49.9,
  quantidade_creditos: 10,
  modalidade: 'sessao',
  validade_dias: 30,
  ...overrides,
});

function callableRequest<T>(data: T, uid: string): CallableRequest<T> {
  return { data, auth: { uid } } as unknown as CallableRequest<T>;
}

const seedBusiness = () => ({
  nome: 'Loja Teste',
  timezone: 'America/Sao_Paulo',
  status: 'ATIVO',
});

const seedMembership = (uid: string, overrides: Record<string, unknown> = {}) => ({
  businessId: BIZ,
  role: 'client',
  ativo: true,
  ...overrides,
});

async function seedMerchantConnection(collectorId = 'seller-42'): Promise<void> {
  // Criptografa o token do seller com a chave de teste (mesma do env).
  const { encryptSecret } = await import('../src/security/token-encryption');
  await adminDb.doc(`merchantConnections/${BIZ}`).set({
    collectorId,
    accessTokenEnc: `enc:v1:${encryptSecret('APP_USR-seller-token')}`,
    refreshTokenEnc: `enc:v1:${encryptSecret('TG-seller-refresh')}`,
    publicKey: 'APP_USR-pub',
    liveMode: true,
    expiresAt: Date.now() + 60_000 * 60 * 24 * 180,
    connectedAt: Date.now(),
    updatedAt: Date.now(),
  });
}

async function seedBase(uid: string = uidClient): Promise<void> {
  await adminDb.doc(`businesses/${BIZ}`).set(seedBusiness());
  await adminDb.doc(`users/${uid}`).set(seedUser(uid));
  await adminDb.doc(`businesses/${BIZ}/members/${uid}`).set(seedMembership(uid));
  await adminDb.doc(`businesses/${BIZ}/packages/pkg-1`).set(seedPackage());
  await seedMerchantConnection();
}

async function setup(): Promise<FakeMpClient> {
  await seedBase();
  return new FakeMpClient();
}

describe('createMercadoPagoCheckout', () => {
  let ownsDefaultApp = false;

  /** Garante um app firebase-admin default (handlers usam getFirestore()). */
  function ensureDefaultApp(): void {
    if (getApps().length === 0) {
      initializeApp({ projectId: PROJECT_ID });
      ownsDefaultApp = true;
    }
  }

  before(async function () {
    this.timeout(30_000);
    process.env.MERCADOPAGO_WEBHOOK_URL =
      'https://us-central1-demo-meupet-agenda.cloudfunctions.net/mercadoPagoWebhook';
    process.env.MERCADOPAGO_TOKEN_ENC_KEY = 'test-master-key-0123456789abcdef';
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { host: '127.0.0.1', port: 8080, rules: '' },
    });
  });

  beforeEach(async () => {
    await env.clearFirestore();
    ensureDefaultApp();
    adminApp = initializeApp(
      { projectId: PROJECT_ID },
      'mp-checkout-tests-' + Date.now(),
    );
    adminDb = getFirestore(adminApp);
  });

  afterEach(async () => {
    await deleteApp(adminApp);
  });

  after(async () => {
    await env.cleanup();
    delete process.env.MERCADOPAGO_WEBHOOK_URL;
    delete process.env.MERCADOPAGO_TOKEN_ENC_KEY;
  });

  it('cria pagamento PENDENTE e preferência e grava ids do gateway', async () => {
    const mp = await setup();
    const result = await createMercadoPagoCheckoutHandler(
      callableRequest<CreateMercadoPagoCheckoutArgs>(
        { businessId: BIZ, packageId: 'pkg-1', idempotencyKey: 'k-1' },
        uidClient,
      ),
      mp,
    );

    assert.equal(mp.preferenceCalls, 1);
    assert.equal(mp.lastInput?.externalReference, result.paymentId);
    assert.equal(mp.lastInput?.unitPrice, 49.9);
    assert.equal(mp.lastInput?.title, 'Pacote Teste');
    assert.equal(mp.lastInput?.payerName, 'Nome client-1');
    assert.ok(mp.lastInput?.notificationUrl.includes('mercadoPagoWebhook'));
    assert.equal(result.preferenceId, 'pref-1');
    assert.equal(result.initPoint, 'https://mercadopago.com.br/checkout/pref-1');

    const payment = (await adminDb.doc(`businesses/${BIZ}/payments/${result.paymentId}`).get()).data()!;
    assert.equal(payment.status, 'PENDENTE');
    assert.equal(payment.forma_pagamento, 'MERCADO_PAGO');
    assert.equal(payment.gatewayStatus, 'CREATED');
    assert.equal(payment.gatewayPreferenceId, 'pref-1');
    assert.equal(payment.gatewayInitPoint, result.initPoint);
    assert.equal(payment.id_cliente, uidClient);
    assert.equal(payment.valor, 49.9);

    const route = (await adminDb.doc(`paymentRoutes/${result.paymentId}`).get()).data()!;
    assert.equal(route.businessId, BIZ);
    assert.equal(route.paymentId, result.paymentId);

    const idem = (await adminDb.doc('mpCheckoutIdempotency/k-1').get()).data()!;
    assert.equal(idem.paymentId, result.paymentId);
    assert.equal(idem.preferenceId, 'pref-1');
    assert.equal(idem.status, 'CREATED');
  });

  it('replay da mesma idempotencyKey retorna o checkout salvo (1 preference call)', async () => {
    const mp = await setup();
    const first = await createMercadoPagoCheckoutHandler(
      callableRequest<CreateMercadoPagoCheckoutArgs>(
        { businessId: BIZ, packageId: 'pkg-1', idempotencyKey: 'k-1' },
        uidClient,
      ),
      mp,
    );
    const second = await createMercadoPagoCheckoutHandler(
      callableRequest<CreateMercadoPagoCheckoutArgs>(
        { businessId: BIZ, packageId: 'pkg-1', idempotencyKey: 'k-1' },
        uidClient,
      ),
      mp,
    );

    assert.equal(mp.preferenceCalls, 1);
    assert.deepEqual(second, first);
    const payments = await adminDb.collection(`businesses/${BIZ}/payments`).get();
    assert.equal(payments.size, 1);
  });

  it('replay incompleto (preferência perdida) recria a preferência no mesmo pagamento', async () => {
    await seedBase();
    const idemKey = 'k-incomplete';
    const paymentId = 'pay-inc-1';
    await adminDb.doc(`mpCheckoutIdempotency/${idemKey}`).set({
      uid: uidClient,
      paymentId,
      status: 'CREATING',
      createdAt: new Date(),
    });
    await adminDb.doc(`businesses/${BIZ}/payments/${paymentId}`).set({
      id_cliente: uidClient,
      tipo: 'PACOTE',
      id_pacote: 'pkg-1',
      id_pacote_cliente: null,
      id_agendamento: null,
      valor: 49.9,
      forma_pagamento: 'MERCADO_PAGO',
      status: 'PENDENTE',
      statusHistory: [],
      statusChangedAt: new Date(),
      statusChangedBy: uidClient,
      gatewayStatus: 'CREATING',
      createdAt: new Date(),
    });

    const mp = new FakeMpClient();
    const result = await createMercadoPagoCheckoutHandler(
      callableRequest<CreateMercadoPagoCheckoutArgs>(
        { businessId: BIZ, packageId: 'pkg-1', idempotencyKey: idemKey },
        uidClient,
      ),
      mp,
    );

    assert.equal(result.paymentId, paymentId);
    assert.equal(mp.preferenceCalls, 1);
    const payment = (await adminDb.doc(`businesses/${BIZ}/payments/${paymentId}`).get()).data()!;
    assert.equal(payment.gatewayPreferenceId, 'pref-1');
    const idem = (await adminDb.doc(`mpCheckoutIdempotency/${idemKey}`).get()).data()!;
    assert.equal(idem.preferenceId, 'pref-1');
    assert.equal(idem.status, 'CREATED');
    const payments = await adminDb.collection(`businesses/${BIZ}/payments`).get();
    assert.equal(payments.size, 1);
  });

  it('falha na preferência cancela o pagamento (gatewayStatus ERROR) e lança unavailable', async () => {
    const mp = await setup();
    mp.createError = new Error('timeout');

    await assert.rejects(
      createMercadoPagoCheckoutHandler(
        callableRequest<CreateMercadoPagoCheckoutArgs>(
          { businessId: BIZ, packageId: 'pkg-1', idempotencyKey: 'k-1' },
          uidClient,
        ),
        mp,
      ),
      (err: unknown) => (err as HttpsError).code === 'unavailable',
    );

    const payments = await adminDb.collection(`businesses/${BIZ}/payments`).get();
    assert.equal(payments.size, 1);
    const payment = payments.docs[0].data();
    assert.equal(payment.status, 'CANCELADO');
    assert.equal(payment.gatewayStatus, 'ERROR');
    assert.ok(payment.canceledAt);
  });

  it('rejeita pacote inexistente (not-found)', async () => {
    await adminDb.doc(`businesses/${BIZ}`).set(seedBusiness());
    await adminDb.doc(`users/${uidClient}`).set(seedUser(uidClient));
    await adminDb.doc(`businesses/${BIZ}/members/${uidClient}`).set(seedMembership(uidClient));
    await seedMerchantConnection();
    await assert.rejects(
      createMercadoPagoCheckoutHandler(
        callableRequest<CreateMercadoPagoCheckoutArgs>(
          { businessId: BIZ, packageId: 'nao-existe' },
          uidClient,
        ),
        new FakeMpClient(),
      ),
      (err: unknown) => (err as HttpsError).code === 'not-found',
    );
  });

  it('rejeita pacote inativo (failed-precondition)', async () => {
    await adminDb.doc(`businesses/${BIZ}`).set(seedBusiness());
    await adminDb.doc(`users/${uidClient}`).set(seedUser(uidClient));
    await adminDb.doc(`businesses/${BIZ}/members/${uidClient}`).set(seedMembership(uidClient));
    await seedMerchantConnection();
    await adminDb.doc(`businesses/${BIZ}/packages/pkg-1`).set(seedPackage({ ativo: false }));
    await assert.rejects(
      createMercadoPagoCheckoutHandler(
        callableRequest<CreateMercadoPagoCheckoutArgs>(
          { businessId: BIZ, packageId: 'pkg-1' },
          uidClient,
        ),
        new FakeMpClient(),
      ),
      (err: unknown) => (err as HttpsError).code === 'failed-precondition',
    );
  });

  it('rejeita usuário inativo (failed-precondition)', async () => {
    await adminDb.doc(`users/${uidClient}`).set(seedUser(uidClient, { ativo: false }));
    await adminDb.doc(`businesses/${BIZ}/packages/pkg-1`).set(seedPackage());
    await assert.rejects(
      createMercadoPagoCheckoutHandler(
        callableRequest<CreateMercadoPagoCheckoutArgs>(
          { businessId: BIZ, packageId: 'pkg-1' },
          uidClient,
        ),
        new FakeMpClient(),
      ),
      (err: unknown) => (err as HttpsError).code === 'failed-precondition',
    );
  });

  it('rejeita idempotencyKey usada por outro usuário (permission-denied)', async () => {
    await seedBase();
    await createMercadoPagoCheckoutHandler(
      callableRequest<CreateMercadoPagoCheckoutArgs>(
        { businessId: BIZ, packageId: 'pkg-1', idempotencyKey: 'k-1' },
        uidClient,
      ),
      new FakeMpClient(),
    );

    await adminDb.doc(`users/${uidClient2}`).set(seedUser(uidClient2));
    await adminDb.doc(`businesses/${BIZ}/members/${uidClient2}`).set(seedMembership(uidClient2));
    await assert.rejects(
      createMercadoPagoCheckoutHandler(
        callableRequest<CreateMercadoPagoCheckoutArgs>(
          { businessId: BIZ, packageId: 'pkg-1', idempotencyKey: 'k-1' },
          uidClient2,
        ),
        new FakeMpClient(),
      ),
      (err: unknown) => (err as HttpsError).code === 'permission-denied',
    );
  });

  it('chamadas concorrentes com a mesma key: 1 pagamento, mesmo resultado', async () => {
    const mp = await setup();
    const request = callableRequest<CreateMercadoPagoCheckoutArgs>(
      { businessId: BIZ, packageId: 'pkg-1', idempotencyKey: 'k-race' },
      uidClient,
    );

    const [first, second] = await Promise.all([
      createMercadoPagoCheckoutHandler(request, mp),
      createMercadoPagoCheckoutHandler(request, mp),
    ]);

    assert.deepEqual(second, first);
    assert.ok(mp.preferenceCalls >= 1);
    const payments = await adminDb.collection(`businesses/${BIZ}/payments`).get();
    assert.equal(payments.size, 1);
    const idem = (await adminDb.doc('mpCheckoutIdempotency/k-race').get()).data()!;
    assert.equal(idem.paymentId, first.paymentId);
    assert.equal(idem.status, 'CREATED');
    assert.ok(idem.preferenceId);
  });

  it('retry após falha na preferência recria a preferência no mesmo pagamento', async () => {
    const mp = await setup();
    mp.createError = new Error('timeout gateway');

    await assert.rejects(
      createMercadoPagoCheckoutHandler(
        callableRequest<CreateMercadoPagoCheckoutArgs>(
          { businessId: BIZ, packageId: 'pkg-1', idempotencyKey: 'k-retry' },
          uidClient,
        ),
        mp,
      ),
      (err: unknown) => (err as HttpsError).code === 'unavailable',
    );

    mp.createError = undefined;
    const retry = await createMercadoPagoCheckoutHandler(
      callableRequest<CreateMercadoPagoCheckoutArgs>(
        { businessId: BIZ, packageId: 'pkg-1', idempotencyKey: 'k-retry' },
        uidClient,
      ),
      mp,
    );

    assert.equal(retry.preferenceId, 'pref-1');
    const idem = (await adminDb.doc('mpCheckoutIdempotency/k-retry').get()).data()!;
    assert.equal(idem.status, 'CREATED');
    assert.equal(idem.preferenceId, 'pref-1');

    const payments = await adminDb.collection(`businesses/${BIZ}/payments`).get();
    assert.equal(payments.size, 1);
    const payment = payments.docs[0].data();
    assert.equal(payments.docs[0].id, retry.paymentId);
    assert.equal(payment.gatewayPreferenceId, 'pref-1');
    // Contrato atual: o pagamento da tentativa falha fica CANCELADO
    // (gatewayStatus ERROR). Reabrir PENDENTE num retry é melhoria futura.
    assert.equal(payment.status, 'CANCELADO');
  });
});