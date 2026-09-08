/**
 * Emulator tests for the Mercado Pago webhook (Task 16).
 *
 * Runs under `firebase emulators:exec --only firestore,storage,functions
 * --project demo-meupet-agenda 'npm test'`. The handler is invoked
 * in-process with a fake Request/Response and an injected FakeMpClient, so
 * no Mercado Pago API is touched.
 *
 * Compiled via tsconfig.test.json into lib-test/ (see functions/README).
 */

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
process.env.FUNCTIONS_EMULATOR ??= 'true';

import 'mocha';
import assert from 'node:assert/strict';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { initializeApp, deleteApp, getApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import type { Request } from 'firebase-functions/v2/https';

import { createHmac } from 'node:crypto';
import { mercadoPagoWebhookHandler } from '../src/payments/mp-webhook';
import type { MercadoPagoWebhookBody, WebhookResponseLike } from '../src/payments/mp-webhook';
import { mapMethodIdToForma } from '../src/payments/mp-webhook';
import type { MpClient, MpPaymentInfo } from '../src/payments/mercadopago-client';

const PROJECT_ID = 'demo-meupet-agenda';

let env: ReturnType<typeof initializeTestEnvironment> extends Promise<infer T>
  ? T
  : never;
let adminApp: import('firebase-admin/app').App;
let adminDb: Firestore;

const BIZ = 'biz-1';
const uidClient = 'client-1';

class FakeMpClient implements MpClient {
  getPaymentCalls = 0;
  constructor(private readonly payment: MpPaymentInfo | null) {}

  async getPayment(paymentId: string): Promise<MpPaymentInfo | null> {
    this.getPaymentCalls += 1;
    if (this.payment === null) {
      return null;
    }
    return { ...this.payment, id: paymentId };
  }

  async createPreference(): Promise<never> {
    throw new Error('createPreference não usado neste teste');
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

const seedPayment = async (status: string, overrides: Record<string, unknown> = {}) => {
  await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).set({
    id_cliente: uidClient,
    tipo: 'PACOTE',
    id_pacote: 'pkg-1',
    id_pacote_cliente: null,
    id_agendamento: null,
    valor: 49.9,
    forma_pagamento: 'MERCADO_PAGO',
    status,
    statusHistory: [{ status, changedBy: uidClient, changedAt: new Date() }],
    statusChangedAt: new Date(),
    statusChangedBy: uidClient,
    ...overrides,
  });
  await adminDb.doc('paymentRoutes/pay-1').set({
    businessId: BIZ,
    paymentId: 'pay-1',
  });
};

const webhookBody = (
  overrides: Partial<MercadoPagoWebhookBody> = {},
): MercadoPagoWebhookBody => ({
  type: 'payment',
  data: { id: 123456 },
  user_id: 'seller-42',
  ...overrides,
});

const mpInfo = (overrides: Partial<MpPaymentInfo> = {}): MpPaymentInfo => ({
  id: '123456',
  status: 'approved',
  paymentMethodId: 'pix',
  externalReference: 'pay-1',
  ...overrides,
});

function fakeRequest(body: unknown, headers: Record<string, string> = {}): Request {
  return { body, headers } as unknown as Request;
}

function fakeResponse(): WebhookResponseLike & { statusCode: number; sentBody: unknown } {
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

async function seedMerchantConnection(collectorId = 'seller-42'): Promise<void> {
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

async function seedApprovedScenario(): Promise<string> {
  await adminDb.doc(`users/${uidClient}`).set(seedUser(uidClient));
  await adminDb.doc(`businesses/${BIZ}/packages/pkg-1`).set(seedPackage());
  await seedPayment('PENDENTE');
  await seedMerchantConnection();
  return 'pay-1';
}

describe('mercadoPagoWebhook', () => {
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
      'mp-webhook-tests-' + Date.now(),
    );
    adminDb = getFirestore(adminApp);
  });

  afterEach(async () => {
    await deleteApp(adminApp);
  });

  after(async () => {
    await env.cleanup();
    delete process.env.MERCADOPAGO_TOKEN_ENC_KEY;
  });

  it('ignora tópico não-payment com 200 sem tocar no Firestore', async () => {
    const response = fakeResponse();
    const mp = new FakeMpClient(null);
    await mercadoPagoWebhookHandler(
      fakeRequest({ type: 'merchant_order', data: { id: 999 } }),
      response,
      mp,
    );
    assert.equal(response.statusCode, 200);
    assert.equal(mp.getPaymentCalls, 0);
    const payments = await adminDb.collection(`businesses/${BIZ}/payments`).get();
    assert.equal(payments.size, 0);
  });

  it('approved: ativa pacote, marca PAGO e grava dados do gateway', async () => {
    await seedApprovedScenario();
    const response = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest(webhookBody()),
      response,
      new FakeMpClient(mpInfo()),
    );

    assert.equal(response.statusCode, 200);
    const body = response.sentBody as { outcome: string };
    assert.equal(body.outcome, 'applied');

    const payment = (await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).get()).data()!;
    assert.equal(payment.status, 'PAGO');
    assert.equal(payment.statusChangedBy, 'mercadopago');
    assert.equal(payment.forma_pagamento, 'PIX');
    assert.equal(payment.gatewayPaymentId, '123456');
    assert.equal(payment.gatewayMethod, 'pix');
    assert.equal(payment.gatewayStatus, 'approved');
    assert.ok(payment.paidAt);

    const customer = (await adminDb.doc(`businesses/${BIZ}/customerPackages/${payment.id_pacote_cliente}`).get());
    assert.equal(customer.exists, true);
    const customerData = customer.data()!;
    assert.equal(customerData.id_cliente, uidClient);
    assert.equal(customerData.id_pacote, 'pkg-1');
    assert.equal(customerData.status, 'ATIVO');
  });

  it('replay em approved não duplica pacote nem history', async () => {
    await seedApprovedScenario();
    for (let i = 0; i < 2; i += 1) {
      const response = fakeResponse();
      await mercadoPagoWebhookHandler(
        fakeRequest(webhookBody()),
        response,
        new FakeMpClient(mpInfo()),
      );
      assert.equal(response.statusCode, 200);
    }

    const packages = await adminDb.collection(`businesses/${BIZ}/customerPackages`).get();
    assert.equal(packages.size, 1);

    const payment = (await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).get()).data()!;
    const pagoEntries = (payment.statusHistory as Array<{ status: string }>).filter(
      (entry) => entry.status === 'PAGO',
    );
    assert.equal(pagoEntries.length, 1);
  });

  it('v3 shape (topic + id) também é aceito', async () => {
    await seedApprovedScenario();
    const response = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest({ topic: 'payment', id: 123456 }),
      response,
      new FakeMpClient(mpInfo()),
    );
    assert.equal(response.statusCode, 200);
    const payment = (await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).get()).data()!;
    assert.equal(payment.status, 'PAGO');
    assert.equal(payment.gatewayPaymentId, '123456');
  });

  it('pending não muda status; só grava gateway', async () => {
    await seedApprovedScenario();
    const response = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest(webhookBody()),
      response,
      new FakeMpClient(mpInfo({ status: 'pending', paymentMethodId: undefined })),
    );

    assert.equal(response.statusCode, 200);
    const body = response.sentBody as { outcome: string };
    assert.equal(body.outcome, 'gateway');

    const payment = (await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).get()).data()!;
    assert.equal(payment.status, 'PENDENTE');
    assert.equal(payment.gatewayStatus, 'pending');
    const packages = await adminDb.collection(`businesses/${BIZ}/customerPackages`).get();
    assert.equal(packages.size, 0);
  });

  it('in_process marca EM_ANALISE e grava gateway', async () => {
    await seedApprovedScenario();
    const response = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest(webhookBody()),
      response,
      new FakeMpClient(mpInfo({ status: 'in_process', paymentMethodId: 'pix' })),
    );

    assert.equal(response.statusCode, 200);
    const body = response.sentBody as { outcome: string };
    assert.equal(body.outcome, 'applied');

    const payment = (await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).get()).data()!;
    assert.equal(payment.status, 'EM_ANALISE');
    assert.equal(payment.statusChangedBy, 'mercadopago');
    assert.equal(payment.gatewayStatus, 'in_process');
    assert.equal(payment.forma_pagamento, 'PIX');
    const packages = await adminDb.collection(`businesses/${BIZ}/customerPackages`).get();
    assert.equal(packages.size, 0);
  });

  it('authorized marca EM_ANALISE', async () => {
    await seedApprovedScenario();
    const response = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest(webhookBody()),
      response,
      new FakeMpClient(mpInfo({ status: 'authorized' })),
    );

    assert.equal(response.statusCode, 200);
    const body = response.sentBody as { outcome: string };
    assert.equal(body.outcome, 'applied');

    const payment = (await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).get()).data()!;
    assert.equal(payment.status, 'EM_ANALISE');
    assert.equal(payment.gatewayStatus, 'authorized');
  });

  it('EM_ANALISE -> approved: vira PAGO e ativa pacote', async () => {
    await seedApprovedScenario();
    await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).update({ status: 'EM_ANALISE' });
    const response = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest(webhookBody()),
      response,
      new FakeMpClient(mpInfo()),
    );

    assert.equal(response.statusCode, 200);
    const payment = (await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).get()).data()!;
    assert.equal(payment.status, 'PAGO');
    const packages = await adminDb.collection(`businesses/${BIZ}/customerPackages`).get();
    assert.equal(packages.size, 1);
  });

  it('EM_ANALISE -> cancelled: vira CANCELADO', async () => {
    await seedApprovedScenario();
    await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).update({ status: 'EM_ANALISE' });
    const response = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest(webhookBody()),
      response,
      new FakeMpClient(mpInfo({ status: 'cancelled' })),
    );

    assert.equal(response.statusCode, 200);
    const payment = (await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).get()).data()!;
    assert.equal(payment.status, 'CANCELADO');
    assert.ok(payment.canceledAt);
  });

  it('replay de in_process após EM_ANALISE: noop sem duplicar history', async () => {
    await seedApprovedScenario();
    await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).update({ status: 'EM_ANALISE' });
    const response = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest(webhookBody()),
      response,
      new FakeMpClient(mpInfo({ status: 'in_process' })),
    );

    assert.equal(response.statusCode, 200);
    const body = response.sentBody as { outcome: string };
    assert.equal(body.outcome, 'noop');
    const payment = (await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).get()).data()!;
    assert.equal(payment.status, 'EM_ANALISE');
  });

  it('rejected marca CANCELADO', async () => {
    await seedApprovedScenario();
    const response = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest(webhookBody()),
      response,
      new FakeMpClient(mpInfo({ status: 'rejected', paymentMethodId: 'credit_card' })),
    );

    assert.equal(response.statusCode, 200);
    const payment = (await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).get()).data()!;
    assert.equal(payment.status, 'CANCELADO');
    assert.equal(payment.statusChangedBy, 'mercadopago');
    assert.equal(payment.forma_pagamento, 'CARTAO');
    assert.ok(payment.canceledAt);
    const packages = await adminDb.collection(`businesses/${BIZ}/customerPackages`).get();
    assert.equal(packages.size, 0);
  });

  it('refunded após PAGO marca REEMBOLSADO', async () => {
    await seedPayment('PAGO', {
      id_pacote_cliente: 'cp-1',
      gatewayPaymentId: '123456',
      paidAt: new Date(),
    });
    const response = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest(webhookBody()),
      response,
      new FakeMpClient(mpInfo({ status: 'refunded' })),
    );

    assert.equal(response.statusCode, 200);
    const payment = (await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).get()).data()!;
    assert.equal(payment.status, 'REEMBOLSADO');
    assert.ok(payment.refundedAt);
  });

  it('refunded bloqueia o saldo restante do pacote vinculado', async () => {
    await seedPayment('PAGO', {
      id_pacote_cliente: 'cp-1',
      gatewayPaymentId: '123456',
      paidAt: new Date(),
    });
    await adminDb.doc(`businesses/${BIZ}/customerPackages/cp-1`).set({
      id_cliente: uidClient,
      id_pacote: 'pkg-1',
      creditos_totais: 5,
      creditos_usados: 2,
      status: 'ATIVO',
    });

    const response = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest(webhookBody()),
      response,
      new FakeMpClient(mpInfo({ status: 'refunded' })),
    );

    assert.equal(response.statusCode, 200);
    const customerPackage = (
      await adminDb.doc(`businesses/${BIZ}/customerPackages/cp-1`).get()
    ).data()!;
    assert.equal(customerPackage.status, 'REEMBOLSADO');
    // Historico de usos preservado para auditoria.
    assert.equal(customerPackage.creditos_usados, 2);
    assert.ok(customerPackage.refundedAt);
  });

  it('approved em pagamento já CANCELADO: ack 200 e state intocado', async () => {
    await seedPayment('CANCELADO');
    const response = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest(webhookBody()),
      response,
      new FakeMpClient(mpInfo()),
    );

    assert.equal(response.statusCode, 200);
    const payment = (await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).get()).data()!;
    assert.equal(payment.status, 'CANCELADO');
    const packages = await adminDb.collection(`businesses/${BIZ}/customerPackages`).get();
    assert.equal(packages.size, 0);
  });

  it('pagamento com external_reference desconhecida: ack 200 (missing)', async () => {
    const response = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest(webhookBody()),
      response,
      new FakeMpClient(mpInfo({ externalReference: 'pay-ghost' })),
    );

    assert.equal(response.statusCode, 200);
    const body = response.sentBody as { outcome: string };
    assert.equal(body.outcome, 'missing');
  });

  it('pagamento inexistente no Mercado Pago: ack 200 (noop)', async () => {
    await seedApprovedScenario();
    const response = fakeResponse();
    const mp = new FakeMpClient(null);
    await mercadoPagoWebhookHandler(fakeRequest(webhookBody()), response, mp);

    assert.equal(response.statusCode, 200);
    assert.equal(mp.getPaymentCalls, 1);
    const payment = (await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).get()).data()!;
    assert.equal(payment.status, 'PENDENTE');
  });

  describe('mercadoPagoWebhook — assinatura (x-signature)', () => {
    before(() => {
      process.env.MERCADOPAGO_WEBHOOK_SECRET = 'segredo-teste';
    });

    after(() => {
      delete process.env.MERCADOPAGO_WEBHOOK_SECRET;
    });

    beforeEach(async () => {
      await env.clearFirestore();
    });

  it('assinatura válida: processa normalmente (applied)', async () => {
    await seedApprovedScenario();
    const ts = '1724000000';
    const response = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest(
        webhookBody(),
        {
          'x-signature': signV2('segredo-teste', '123456', 'req-1', ts),
          'x-request-id': 'req-1',
        },
      ),
      response,
      new FakeMpClient(mpInfo()),
    );

    assert.equal(response.statusCode, 200);
    const payment = (await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).get()).data()!;
    assert.equal(payment.status, 'PAGO');
  });

  it('assinatura adulterada: 401 e nenhuma escrita', async () => {
    await seedApprovedScenario();
    const ts = '1724000000';
    const response = fakeResponse();
    const mp = new FakeMpClient(mpInfo());
    await mercadoPagoWebhookHandler(
      fakeRequest(
        webhookBody(),
        {
          'x-signature': `ts=${ts},v1=${'0'.repeat(64)}`,
          'x-request-id': 'req-1',
        },
      ),
      response,
      mp,
    );

    assert.equal(response.statusCode, 401);
    assert.equal(mp.getPaymentCalls, 0);
    const body = response.sentBody as { received: boolean };
    assert.equal(body.received, false);
    const payment = (await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).get()).data()!;
    assert.equal(payment.status, 'PENDENTE');
    const packages = await adminDb.collection(`businesses/${BIZ}/customerPackages`).get();
    assert.equal(packages.size, 0);
  });

  it('sem x-signature: 401', async () => {
    await seedApprovedScenario();
    const response = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest(webhookBody(), { 'x-request-id': 'req-1' }),
      response,
      new FakeMpClient(mpInfo()),
    );

    assert.equal(response.statusCode, 401);
  });

  it('sem secret configurado (dev): assinatura não é exigida', async () => {
    delete process.env.MERCADOPAGO_WEBHOOK_SECRET;
    await seedApprovedScenario();
    const response = fakeResponse();
    await mercadoPagoWebhookHandler(
      fakeRequest(webhookBody()),
      response,
      new FakeMpClient(mpInfo()),
    );

    assert.equal(response.statusCode, 200);
  });

  it('produção sem secret: falha fechada com 500 e nenhuma consulta', async () => {
    const wasEmulator = process.env.FUNCTIONS_EMULATOR;
    const wasSecret = process.env.MERCADOPAGO_WEBHOOK_SECRET;
    delete process.env.FUNCTIONS_EMULATOR;
    delete process.env.MERCADOPAGO_WEBHOOK_SECRET;
    try {
      await seedApprovedScenario();
      const response = fakeResponse();
      const mp = new FakeMpClient(mpInfo());
      await mercadoPagoWebhookHandler(
        fakeRequest(webhookBody()),
        response,
        mp,
      );

      assert.equal(response.statusCode, 500);
      assert.equal(mp.getPaymentCalls, 0);
      const payment = (await adminDb.doc(`businesses/${BIZ}/payments/pay-1`).get()).data()!;
      assert.equal(payment.status, 'PENDENTE');
    } finally {
      restoreEnv(wasEmulator, wasSecret);
    }
  });
});

function restoreEnv(emulator: string | undefined, secret: string | undefined): void {
  if (emulator === undefined) {
    delete process.env.FUNCTIONS_EMULATOR;
  } else {
    process.env.FUNCTIONS_EMULATOR = emulator;
  }
  if (secret === undefined) {
    delete process.env.MERCADOPAGO_WEBHOOK_SECRET;
  } else {
    process.env.MERCADOPAGO_WEBHOOK_SECRET = secret;
  }
}
});

function signV2(
  secret: string,
  id: string,
  requestId: string,
  timestamp: string,
): string {
  // Manifesto oficial: o secret é a chave HMAC, não parte do texto assinado.
  const hash = createHmac('sha256', secret)
    .update(`id:${id};request-id:${requestId};ts:${timestamp};`)
    .digest('hex');
  return `ts=${timestamp},v1=${hash}`;
}

describe('mapMethodIdToForma (métodos reais do Checkout Pro)', () => {
  it('marca de cartão vira CARTAO', () => {
    for (const brand of ['visa', 'master', 'amex', 'elo', 'hipercard', 'maestro']) {
      assert.equal(mapMethodIdToForma(brand), 'CARTAO', brand);
    }
  });

  it('pix e boleto mantêm os mapeamentos atuais', () => {
    assert.equal(mapMethodIdToForma('pix'), 'PIX');
    assert.equal(mapMethodIdToForma('bolbradesco'), 'BOLETO');
  });

  it('método desconhecido não muda forma_pagamento', () => {
    assert.equal(mapMethodIdToForma('weird_method'), undefined);
    assert.equal(mapMethodIdToForma(undefined), undefined);
  });
});