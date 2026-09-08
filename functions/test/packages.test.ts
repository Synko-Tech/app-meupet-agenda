/**
 * Emulator tests for the purchasePackage and activatePackage callables
 * (Task 12).
 *
 * Runs under `firebase emulators:exec --only firestore,storage,functions`.
 * The exported handlers are invoked in-process with a fake CallableRequest so
 * the tests genuinely exercise the real transaction logic against the
 * emulator Firestore (admin SDK bypasses rules; seeding goes through
 * @firebase/rules-unit-testing with rules disabled).
 */

// Point firebase-admin at the emulator (fallback if not already exported by
// emulators:exec).
process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';

import 'mocha';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import assert from 'node:assert/strict';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import type { HttpsError } from 'firebase-functions/v2/https';

import type {
  PurchasePackageArgs,
  PurchasePackageResult,
} from '../src/packages/purchase-package';
import { purchasePackageHandler } from '../src/packages/purchase-package';
import type {
  ActivatePackageArgs,
  ActivatePackageResult,
} from '../src/packages/activate-package';
import { activatePackageHandler } from '../src/packages/activate-package';

const PROJECT_ID = process.env.FIREBASE_TEST_PROJECT_ID ?? 'demo-meupet-agenda';
if (!PROJECT_ID.startsWith('demo-')) {
  throw new Error(
    `Suites de teste exigem um project id demo-* (use FIREBASE_TEST_PROJECT_ID). Recebido: ${PROJECT_ID}`,
  );
}
// Compiled to functions/lib-test/test/, so the repo root is three levels up.
const RULES = readFileSync(join(__dirname, '..', '..', '..', 'firestore.rules'), 'utf8');

const CLIENT = 'alice';
const BIZ = 'biz-1';

let testEnv: Awaited<ReturnType<typeof initializeTestEnvironment>>;
let adminApp: ReturnType<typeof initializeApp>;

// All hooks are scoped inside this describe: this file runs in the same mocha
// process as appointments.test.ts (whose root hooks are global), so scoping
// prevents cross-file beforeEach seeding collisions. A named app avoids
// clashing with the [DEFAULT] app created by appointments.test.ts.
describe('package purchase and activation flow', () => {
  before(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { host: '127.0.0.1', port: 8080, rules: RULES },
    });
    adminApp = initializeApp({ projectId: PROJECT_ID }, 'packages-test-app');
  });

  after(async () => {
    await testEnv.cleanup();
    await deleteApp(adminApp);
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
    await seedFixtures();
  });

async function seed(path: string, data: Record<string, unknown>): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(path).set(data);
  });
}

async function seedFixtures(): Promise<void> {
  await seed('users/alice', { nome: 'Alice Silva', role: 'client', ativo: true });
  await seed('users/bob', { nome: 'Bob Souza', role: 'client', ativo: true });
  await seed('users/admin1', { nome: 'Admin Um', role: 'super_admin', ativo: true });
  await seed('users/admin2', { nome: 'Admin Dois', role: 'super_admin', ativo: true });
  await seed('users/staff1', { nome: 'Atendente Um', role: 'admin', ativo: true });

  await seed(`businesses/${BIZ}`, {
    nome: 'Loja Teste',
    timezone: 'America/Sao_Paulo',
    status: 'ATIVO',
  });
  await seed(`businesses/${BIZ}/members/alice`, { role: 'client', ativo: true });
  await seed(`businesses/${BIZ}/members/bob`, { role: 'client', ativo: true });
  await seed(`businesses/${BIZ}/members/admin1`, { role: 'owner', ativo: true });
  await seed(`businesses/${BIZ}/members/admin2`, { role: 'admin', ativo: true });
  await seed(`businesses/${BIZ}/members/staff1`, { role: 'collaborator', ativo: true });

  await seed(`businesses/${BIZ}/packages/bp1`, {
    id_servico: 'svc60',
    serviceName: 'Banho',
    nome: 'Pacote Banho 5x',
    quantidade_creditos: 5,
    valor: 250,
    validade_dias: 30,
    ativo: true,
  });
  await seed(`businesses/${BIZ}/packages/bp2`, {
    id_servico: 'svc90',
    serviceName: 'Tosa',
    nome: 'Pacote Tosa 2x',
    quantidade_creditos: 2,
    valor: 160,
    validade_dias: 15,
    ativo: true,
  });
  await seed(`businesses/${BIZ}/packages/bpOff`, {
    id_servico: 'svc60',
    serviceName: 'Banho',
    nome: 'Pacote Inativo',
    quantidade_creditos: 3,
    valor: 120,
    validade_dias: 30,
    ativo: false,
  });
  await seed(`businesses/${BIZ}/packages/bpBroken`, {
    id_servico: 'svc60',
    serviceName: 'Banho',
    nome: 'Pacote Quebrado',
    quantidade_creditos: 0,
    valor: -5,
    validade_dias: 0,
    ativo: true,
  });
}

function purchaseCall(
  uid: string | null,
  args: Partial<PurchasePackageArgs>,
): Promise<PurchasePackageResult> {
  const request = {
    data: args as PurchasePackageArgs,
    auth: uid === null ? null : { uid },
  } as unknown as Parameters<typeof purchasePackageHandler>[0];
  return purchasePackageHandler(request);
}

function activateCall(
  uid: string | null,
  args: Partial<ActivatePackageArgs>,
): Promise<ActivatePackageResult> {
  const request = {
    data: args as ActivatePackageArgs,
    auth: uid === null ? null : { uid },
  } as unknown as Parameters<typeof activatePackageHandler>[0];
  return activatePackageHandler(request);
}

function db() {
  return getFirestore(adminApp);
}

async function docData(path: string): Promise<Record<string, unknown> | undefined> {
  const snap = await db().doc(path).get();
  return snap.data();
}

async function countDocs(collection: string): Promise<number> {
  const snap = await db().collection(collection).get();
  return snap.size;
}

async function expectError(promise: Promise<unknown>, code: string): Promise<void> {
  await assert.rejects(promise, (error: unknown) => {
    const httpsError = error as HttpsError;
    assert.equal(httpsError.code, code);
    return true;
  });
}

describe('purchasePackage', () => {
  const baseArgs = (overrides: Partial<PurchasePackageArgs> = {}): PurchasePackageArgs => ({
    businessId: BIZ,
    packageId: 'bp1',
    ...overrides,
  });

  it('creates a PENDENTE payment with server-authoritative data and NO customerPackage', async () => {
    const result = await purchaseCall(CLIENT, baseArgs());

    assert.equal(typeof result.paymentId, 'string');
    assert.ok(result.paymentId.length > 0);

    const payment = await docData(`businesses/${BIZ}/payments/${result.paymentId}`);
    assert.ok(payment);
    assert.equal(payment.id_cliente, CLIENT);
    assert.equal(payment.clientName, 'Alice Silva');
    assert.equal(payment.tipo, 'PACOTE');
    assert.equal(payment.id_pacote, 'bp1');
    assert.equal(payment.id_pacote_cliente, null);
    assert.equal(payment.valor, 250);
    assert.equal(payment.forma_pagamento, 'PIX');
    assert.equal(payment.status, 'PENDENTE');
    assert.ok(payment.createdAt instanceof Timestamp);
    // The paid date must NOT be stamped while the payment is still pending;
    // `paidAt` is written by activate/updatePaymentStatus when it becomes PAGO.
    assert.equal(payment.data_pagamento, undefined);
    assert.equal(payment.paidAt, undefined);
    assert.equal(payment.statusChangedBy, CLIENT);
    assert.ok(payment.statusChangedAt instanceof Timestamp);

    const history = payment.statusHistory as Array<Record<string, unknown>>;
    assert.equal(history.length, 1);
    assert.equal(history[0].status, 'PENDENTE');
    assert.equal(history[0].changedBy, CLIENT);
    assert.ok(history[0].changedAt instanceof Timestamp);

    assert.equal(await countDocs(`businesses/${BIZ}/customerPackages`), 0);
  });

  it('stores the client-provided method when valid', async () => {
    const result = await purchaseCall(CLIENT, baseArgs({ method: 'CARTAO' }));
    const payment = await docData(`businesses/${BIZ}/payments/${result.paymentId}`);
    assert.equal(payment?.forma_pagamento, 'CARTAO');

    const dinheiro = await purchaseCall(CLIENT, baseArgs({ method: 'dinheiro' }));
    const payment2 = await docData(`businesses/${BIZ}/payments/${dinheiro.paymentId}`);
    assert.equal(payment2?.forma_pagamento, 'DINHEIRO');
  });

  it('rejects a nonexistent business package', async () => {
    await expectError(purchaseCall(CLIENT, baseArgs({ packageId: 'ghost' })), 'not-found');
    assert.equal(await countDocs(`businesses/${BIZ}/payments`), 0);
  });

  it('rejects an inactive business package', async () => {
    await expectError(purchaseCall(CLIENT, baseArgs({ packageId: 'bpOff' })), 'failed-precondition');
    assert.equal(await countDocs(`businesses/${BIZ}/payments`), 0);
  });

  it('rejects a broken catalog package (invalid credits/price/validity)', async () => {
    await expectError(purchaseCall(CLIENT, baseArgs({ packageId: 'bpBroken' })), 'failed-precondition');
    assert.equal(await countDocs(`businesses/${BIZ}/payments`), 0);
  });

  it('rejects a method outside the allowlist', async () => {
    await expectError(purchaseCall(CLIENT, baseArgs({ method: 'CHEQUE' })), 'invalid-argument');
    assert.equal(await countDocs(`businesses/${BIZ}/payments`), 0);
  });

  it('rejects a missing packageId', async () => {
    await expectError(purchaseCall(CLIENT, { businessId: BIZ, packageId: '' }), 'invalid-argument');
  });

  it('allows staff (non-super admin) to purchase on behalf of a client', async () => {
    const result = await purchaseCall('staff1', baseArgs());
    const payment = await docData(`businesses/${BIZ}/payments/${result.paymentId}`);
    assert.equal(payment?.id_cliente, 'staff1');
    assert.equal(payment?.clientName, 'Atendente Um');
  });

  it('rejects unauthenticated calls', async () => {
    await expectError(purchaseCall(null, baseArgs()), 'unauthenticated');
  });

  it('idempotencyKey: same key twice returns the same paymentId with a single payment', async () => {
    const args = baseArgs({ idempotencyKey: 'purchase-alice-1' });
    const first = await purchaseCall(CLIENT, args);
    const second = await purchaseCall(CLIENT, args);

    assert.equal(second.paymentId, first.paymentId);
    assert.equal(await countDocs(`businesses/${BIZ}/payments`), 1);
    const idem = await docData('purchaseIdempotency/purchase-alice-1');
    assert.equal(idem?.paymentId, first.paymentId);
    assert.equal(idem?.uid, CLIENT);
  });

  it('rejects an idempotency key belonging to another user', async () => {
    await purchaseCall(CLIENT, baseArgs({ idempotencyKey: 'shared-purchase' }));
    await expectError(
      purchaseCall('bob', baseArgs({ idempotencyKey: 'shared-purchase' })),
      'permission-denied',
    );
  });
});

describe('activatePackage', () => {
  async function createPendingPayment(
    uid: string = CLIENT,
    overrides: Partial<PurchasePackageArgs> = {},
  ): Promise<string> {
    const result = await purchaseCall(uid, { businessId: BIZ, packageId: 'bp1', ...overrides });
    return result.paymentId;
  }

  it('denies a regular client', async () => {
    const paymentId = await createPendingPayment();
    await expectError(activateCall(CLIENT, { businessId: BIZ, paymentId }), 'permission-denied');

    const payment = await docData(`businesses/${BIZ}/payments/${paymentId}`);
    assert.equal(payment?.status, 'PENDENTE');
    assert.equal(await countDocs(`businesses/${BIZ}/customerPackages`), 0);
  });

  it('denies staff that is not super_admin', async () => {
    const paymentId = await createPendingPayment();
    await expectError(activateCall('staff1', { businessId: BIZ, paymentId }), 'permission-denied');
    assert.equal(await countDocs(`businesses/${BIZ}/customerPackages`), 0);
  });

  it('creates the customerPackage with catalog credits/validity and marks the payment PAGO', async () => {
    const paymentId = await createPendingPayment();

    const result = await activateCall('admin1', { businessId: BIZ, paymentId });

    const customerPackage = await docData(`businesses/${BIZ}/customerPackages/${result.customerPackageId}`);
    assert.ok(customerPackage);
    assert.equal(customerPackage.id_cliente, CLIENT);
    assert.equal(customerPackage.clientName, 'Alice Silva');
    assert.equal(customerPackage.id_pacote, 'bp1');
    assert.equal(customerPackage.id_servico, 'svc60');
    assert.equal(customerPackage.packageName, 'Pacote Banho 5x');
    assert.equal(customerPackage.serviceName, 'Banho');
    assert.equal(customerPackage.creditos_totais, 5);
    assert.equal(customerPackage.creditos_usados, 0);
    assert.equal(customerPackage.status, 'ATIVO');
    assert.ok(customerPackage.data_compra instanceof Timestamp);
    assert.ok(customerPackage.data_validade instanceof Timestamp);
    assert.ok(customerPackage.createdAt instanceof Timestamp);
    assert.ok(customerPackage.updatedAt instanceof Timestamp);

    const purchaseDate = (customerPackage.data_compra as Timestamp).toDate();
    const validUntil = (customerPackage.data_validade as Timestamp).toDate();
    assert.equal(validUntil.getTime() - purchaseDate.getTime(), 30 * 86_400_000);

    const payment = await docData(`businesses/${BIZ}/payments/${paymentId}`);
    assert.equal(payment?.status, 'PAGO');
    assert.equal(payment?.id_pacote_cliente, result.customerPackageId);
    assert.equal(payment?.statusChangedBy, 'admin1');
    assert.ok(payment?.statusChangedAt instanceof Timestamp);
    assert.ok(payment?.paidAt instanceof Timestamp);

    const history = payment?.statusHistory as Array<Record<string, unknown>>;
    assert.equal(history.length, 2);
    assert.equal(history[0].status, 'PENDENTE');
    assert.equal(history[1].status, 'PAGO');
    assert.equal(history[1].changedBy, 'admin1');
    assert.ok(history[1].changedAt instanceof Timestamp);

    assert.equal(await countDocs(`businesses/${BIZ}/customerPackages`), 1);
  });

  it('no-op on an already-activated PAGO payment: returns the same customerPackageId, no duplicate', async () => {
    const paymentId = await createPendingPayment();
    const first = await activateCall('admin1', { businessId: BIZ, paymentId });
    const second = await activateCall('admin1', { businessId: BIZ, paymentId });

    assert.equal(second.customerPackageId, first.customerPackageId);
    assert.equal(await countDocs(`businesses/${BIZ}/customerPackages`), 1);

    const payment = await docData(`businesses/${BIZ}/payments/${paymentId}`);
    const history = payment?.statusHistory as Array<Record<string, unknown>>;
    assert.equal(history.length, 2);
  });

  it('rejects a nonexistent payment', async () => {
    await expectError(activateCall('admin1', { businessId: BIZ, paymentId: 'ghost' }), 'not-found');
  });

  it('rejects a payment that cannot be activated (CANCELADO)', async () => {
    await seed(`businesses/${BIZ}/payments/payCanceled`, {
      id_cliente: CLIENT,
      clientName: 'Alice Silva',
      tipo: 'PACOTE',
      id_pacote: 'bp1',
      id_pacote_cliente: null,
      valor: 250,
      forma_pagamento: 'PIX',
      status: 'CANCELADO',
      createdAt: new Date('2026-08-01T10:00:00-03:00'),
    });

    await expectError(activateCall('admin1', { businessId: BIZ, paymentId: 'payCanceled' }), 'failed-precondition');
    assert.equal(await countDocs(`businesses/${BIZ}/customerPackages`), 0);
  });

  it('idempotencyKey: same key twice returns the same customerPackageId with a single package', async () => {
    const paymentId = await createPendingPayment();

    const first = await activateCall('admin1', { businessId: BIZ, paymentId, idempotencyKey: 'activate-alice-1' });
    const second = await activateCall('admin1', { businessId: BIZ, paymentId, idempotencyKey: 'activate-alice-1' });

    assert.equal(second.customerPackageId, first.customerPackageId);
    assert.equal(await countDocs(`businesses/${BIZ}/customerPackages`), 1);

    const idem = await docData('activateIdempotency/activate-alice-1');
    assert.equal(idem?.customerPackageId, first.customerPackageId);
    assert.equal(idem?.uid, 'admin1');
  });

  it('rejects an idempotency key belonging to another super admin', async () => {
    const paymentId = await createPendingPayment();
    await activateCall('admin1', { businessId: BIZ, paymentId, idempotencyKey: 'shared-activate' });
    await expectError(
      activateCall('admin2', { businessId: BIZ, paymentId, idempotencyKey: 'shared-activate' }),
      'permission-denied',
    );
  });

  it('rejects unauthenticated calls', async () => {
    await expectError(activateCall(null, { businessId: BIZ, paymentId: 'pay1' }), 'unauthenticated');
  });

  it('rejects a missing paymentId', async () => {
    await expectError(activateCall('admin1', { businessId: BIZ, paymentId: '' }), 'invalid-argument');
  });
});
});
