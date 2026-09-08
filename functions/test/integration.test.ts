/**
 * End-to-end integration flows across the emulated backend (Task 18).
 *
 * Chains the real handlers for auth/profile gating, appointments, packages
 * and payments against the Firestore emulator in one process:
 *
 *   flow 1: register -> deactivated -> denied (rules level + callable level)
 *   flow 2: double booking rejected via callable (one winner per slot)
 *   flow 3: cancel twice -> single credit refund
 *   flow 4: purchase -> PENDENTE -> super_admin activate -> book -> debit
 *
 * Runs under `firebase emulators:exec --only firestore,storage,functions`.
 * The exported handlers are invoked in-process with a fake CallableRequest so
 * the flows genuinely exercise the real transaction logic against the
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
import { initializeTestEnvironment, assertFails } from '@firebase/rules-unit-testing';
import { initializeApp, deleteApp, getApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import type { HttpsError } from 'firebase-functions/v2/https';

import type { CreateAppointmentArgs, CreateAppointmentResult } from '../src/appointments/create-appointment';
import { createAppointmentHandler } from '../src/appointments/create-appointment';
import type { CancelAppointmentArgs, CancelAppointmentResult } from '../src/appointments/cancel-appointment';
import { cancelAppointmentHandler } from '../src/appointments/cancel-appointment';
import type { PurchasePackageArgs, PurchasePackageResult } from '../src/packages/purchase-package';
import { purchasePackageHandler } from '../src/packages/purchase-package';
import type { ActivatePackageArgs, ActivatePackageResult } from '../src/packages/activate-package';
import { activatePackageHandler } from '../src/packages/activate-package';

const PROJECT_ID = process.env.FIREBASE_TEST_PROJECT_ID ?? 'demo-meupet-agenda';
if (!PROJECT_ID.startsWith('demo-')) {
  throw new Error(
    `Suites de teste exigem um project id demo-* (use FIREBASE_TEST_PROJECT_ID). Recebido: ${PROJECT_ID}`,
  );
}
// Compiled to functions/lib-test/test/, so the repo root is three levels up.
const RULES = readFileSync(join(__dirname, '..', '..', '..', 'firestore.rules'), 'utf8');

// America/Sao_Paulo = UTC-3 (sem DST desde 2019). Datas de agendamento sao
// calculadas como a PROXIMA sexta-feira, sempre no futuro (nunca expiram).
const SP_OFFSET_MS = 3 * 60 * 60 * 1000;

function saoPauloIso(weekday: number, hour: number, minute = 0, offsetDays = 0): string {
  const now = new Date(Date.now() + SP_OFFSET_MS);
  let delta = (weekday - now.getUTCDay() + 7) % 7;
  if (delta === 0) {
    delta = 7;
  }
  const instant = Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate() + delta + offsetDays,
    hour + 3,
    minute,
  );
  return new Date(instant).toISOString();
}

const FRIDAY_09 = saoPauloIso(5, 9);
const FRIDAY_10 = saoPauloIso(5, 10);

const CLIENT = 'alice';
const OTHER_CLIENT = 'bob';
const SUPER_ADMIN = 'admin1';
const INACTIVE_CLIENT = 'mallory';
const BIZ = 'biz-1';

let testEnv: Awaited<ReturnType<typeof initializeTestEnvironment>>;
let adminApp: ReturnType<typeof initializeApp>;

// All hooks are scoped inside this describe: this file runs in the same mocha
// process as appointments.test.ts (whose root hooks are global), so scoping
// prevents cross-file beforeEach seeding collisions. A named app avoids
// clashing with the [DEFAULT] app created by appointments.test.ts.
describe('end-to-end integration flows', () => {
  let ownsDefaultApp = false;

  /** Garante um app firebase-admin default (handlers usam getFirestore()). */
  function ensureDefaultApp(): void {
    if (getApps().length === 0) {
      initializeApp({ projectId: PROJECT_ID });
      ownsDefaultApp = true;
    }
  }

  before(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { host: '127.0.0.1', port: 8080, rules: RULES },
    });
    ensureDefaultApp();
    adminApp = initializeApp({ projectId: PROJECT_ID }, 'integration-test-app');
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
    // mallory is seeded inactive: her profile starts deactivated, matching a
    // user who never got activated / was deactivated at registration time.
    await seed('users/mallory', { nome: 'Mallory', role: 'client', ativo: false });

    await seed(`businesses/${BIZ}`, {
      nome: 'Loja Teste',
      timezone: 'America/Sao_Paulo',
      status: 'ATIVO',
    });
    await seed(`businesses/${BIZ}/members/alice`, { role: 'client', ativo: true });
    await seed(`businesses/${BIZ}/members/bob`, { role: 'client', ativo: true });
    await seed(`businesses/${BIZ}/members/admin1`, { role: 'owner', ativo: true });

    await seed(`businesses/${BIZ}/services/svc60`, {
      nome: 'Banho',
      descricao: 'Banho completo',
      duracao_minutos: 60,
      valor: 60,
      ativo: true,
    });

    await seed(`businesses/${BIZ}/packages/bp1`, {
      id_servico: 'svc60',
      serviceName: 'Banho',
      nome: 'Pacote Banho 5x',
      quantidade_creditos: 5,
      valor: 250,
      validade_dias: 30,
      ativo: true,
    });
  }

  function call(
    uid: string | null,
    args: Partial<CreateAppointmentArgs>,
  ): Promise<CreateAppointmentResult> {
    const request = {
      data: args as CreateAppointmentArgs,
      auth: uid === null ? null : { uid },
    } as unknown as Parameters<typeof createAppointmentHandler>[0];
    return createAppointmentHandler(request);
  }

  function cancelCall(
    uid: string | null,
    args: Partial<CancelAppointmentArgs>,
  ): Promise<CancelAppointmentResult> {
    const request = {
      data: args as CancelAppointmentArgs,
      auth: uid === null ? null : { uid },
    } as unknown as Parameters<typeof cancelAppointmentHandler>[0];
    return cancelAppointmentHandler(request);
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

  /** Booking args valid against the seeded fixtures (svc60, Friday 09:00). */
  function bookingArgs(overrides: Partial<CreateAppointmentArgs> = {}): CreateAppointmentArgs {
    return {
      businessId: BIZ,
      serviceId: 'svc60',
      startAt: FRIDAY_09,
      ...overrides,
    };
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

  /** Buys bp1 (5 credits, svc60) and activates it as super_admin. */
  async function buyAndActivatePackage(): Promise<{ paymentId: string; customerPackageId: string }> {
    const { paymentId } = await purchaseCall(CLIENT, { businessId: BIZ, packageId: 'bp1' });
    const { customerPackageId } = await activateCall(SUPER_ADMIN, { businessId: BIZ, paymentId });
    return { paymentId, customerPackageId };
  }

  describe('flow 1: register -> deactivated -> denied', () => {
    it('rules: an authed context that was active is denied once ativo flips to false', async () => {
      await seed(`businesses/${BIZ}/payments/pay1`, { businessId: BIZ, id_cliente: CLIENT, status: 'PAGO' });

      // While ativo=true the client reads their own payment fine.
      await testEnv
        .authenticatedContext(CLIENT)
        .firestore()
        .doc(`businesses/${BIZ}/payments/pay1`)
        .get();

      // A super admin deactivates the profile (backend write bypasses rules).
      await seed('users/alice', { nome: 'Alice Silva', role: 'client', ativo: false });

      // The same identity is now locked out at the rules level.
      const inactiveCtx = testEnv.authenticatedContext(CLIENT);
      await assertFails(inactiveCtx.firestore().doc(`businesses/${BIZ}/payments/pay1`).get());
    });

    it('callable: createAppointment as an inactive user -> failed-precondition', async () => {
      await expectError(
        call(INACTIVE_CLIENT, {
          businessId: BIZ,
          serviceId: 'svc60',
          startAt: FRIDAY_09,
        }),
        'failed-precondition',
      );
      // Nothing was written: no appointment, no slot locks.
      assert.equal(await countDocs(`businesses/${BIZ}/appointments`), 0);
      assert.equal(await countDocs(`businesses/${BIZ}/appointmentSlots`), 0);
    });
  });

  describe('flow 2: double booking rejected via callable', () => {
    it('two concurrent bookings for the same slot: exactly one wins, loser gets already-exists', async () => {
      const args: CreateAppointmentArgs = {
        businessId: BIZ,
        serviceId: 'svc60',
        startAt: FRIDAY_09,
      };
      const results = await Promise.allSettled([call(CLIENT, args), call(OTHER_CLIENT, args)]);

      const fulfilled = results.filter((r) => r.status === 'fulfilled');
      const rejected = results.filter((r) => r.status === 'rejected');
      assert.equal(fulfilled.length, 1);
      assert.equal(rejected.length, 1);
      const failure = rejected[0] as PromiseRejectedResult;
      assert.equal((failure.reason as HttpsError).code, 'already-exists');

      // One appointment exists and the winner is its owner.
      const appointmentSnap = await db().collection(`businesses/${BIZ}/appointments`).get();
      assert.equal(appointmentSnap.size, 1);
      const winner = appointmentSnap.docs[0].data();
      assert.ok(
        winner.id_cliente === CLIENT || winner.id_cliente === OTHER_CLIENT,
        'the appointment must belong to the fulfilled caller',
      );

      // Both 30-minute slots are locked under the single winner.
      assert.equal(await countDocs(`businesses/${BIZ}/appointmentSlots`), 2);
    });
  });

  describe('flow 3: cancel twice -> single refund', () => {
    it('book with a real activated package, cancel twice: exactly one credit refunded', async () => {
      const { customerPackageId } = await buyAndActivatePackage();

      const { appointmentId } = await call(CLIENT, bookingArgs({ customerPackageId }));
      let packageDoc = await docData(`businesses/${BIZ}/customerPackages/${customerPackageId}`);
      assert.equal(packageDoc?.creditos_usados, 1);
      assert.equal(packageDoc?.status, 'ATIVO');

      const first = await cancelCall(CLIENT, { businessId: BIZ, appointmentId });
      assert.deepEqual(first, { appointmentId, canceled: true });

      const second = await cancelCall(CLIENT, { businessId: BIZ, appointmentId });
      assert.deepEqual(second, { appointmentId, canceled: false });

      // Credits decremented exactly once: 1 -> 0, never negative.
      packageDoc = await docData(`businesses/${BIZ}/customerPackages/${customerPackageId}`);
      assert.equal(packageDoc?.creditos_usados, 0);
      assert.equal(packageDoc?.status, 'ATIVO');

      // Exactly one usage record exists and it is flagged estornado once.
      const usageSnap = await db().collection(`businesses/${BIZ}/packageUsage`).get();
      assert.equal(usageSnap.size, 1);
      assert.equal(usageSnap.docs[0].data().estornado, true);
      assert.equal(usageSnap.docs[0].data().id_agendamento, appointmentId);

      // Slot locks released once.
      assert.equal(await countDocs(`businesses/${BIZ}/appointmentSlots`), 0);
    });
  });

  describe('flow 4: purchase -> PENDENTE -> activate -> book -> debit', () => {
    it('full happy path: purchasePackage, activatePackage, createAppointment with customerPackageId', async () => {
      // 1. Client purchases: only a PENDENTE payment exists, no customerPackage.
      const { paymentId } = await purchaseCall(CLIENT, { businessId: BIZ, packageId: 'bp1' });

      const payment = await docData(`businesses/${BIZ}/payments/${paymentId}`);
      assert.ok(payment);
      assert.equal(payment.id_cliente, CLIENT);
      assert.equal(payment.status, 'PENDENTE');
      assert.equal(payment.id_pacote, 'bp1');
      assert.equal(payment.id_pacote_cliente, null);
      assert.equal(payment.valor, 250);
      assert.equal(await countDocs(`businesses/${BIZ}/customerPackages`), 0);

      // 2. Super admin activates: customerPackage ATIVO with catalog credits,
      //    payment back-filled to PAGO.
      const { customerPackageId } = await activateCall(SUPER_ADMIN, { businessId: BIZ, paymentId });

      const customerPackage = await docData(`businesses/${BIZ}/customerPackages/${customerPackageId}`);
      assert.ok(customerPackage);
      assert.equal(customerPackage.id_cliente, CLIENT);
      assert.equal(customerPackage.id_pacote, 'bp1');
      assert.equal(customerPackage.id_servico, 'svc60');
      assert.equal(customerPackage.serviceName, 'Banho');
      assert.equal(customerPackage.creditos_totais, 5);
      assert.equal(customerPackage.creditos_usados, 0);
      assert.equal(customerPackage.status, 'ATIVO');

      const paidPayment = await docData(`businesses/${BIZ}/payments/${paymentId}`);
      assert.equal(paidPayment?.status, 'PAGO');
      assert.equal(paidPayment?.id_pacote_cliente, customerPackageId);

      // 3. Client books with the package: appointment created, one credit debited.
      const { appointmentId } = await call(CLIENT, bookingArgs({ customerPackageId }));

      const appointment = await docData(`businesses/${BIZ}/appointments/${appointmentId}`);
      assert.ok(appointment);
      assert.equal(appointment.id_cliente, CLIENT);
      assert.equal(appointment.id_servico, 'svc60');
      assert.equal(appointment.id_pacote_cliente, customerPackageId);
      assert.equal(appointment.status, 'AGENDADO');

      const usedPackage = await docData(`businesses/${BIZ}/customerPackages/${customerPackageId}`);
      assert.equal(usedPackage?.creditos_usados, 1);
      assert.equal(usedPackage?.status, 'ATIVO');

      // 4. Usage record written for the debit.
      const usageSnap = await db().collection(`businesses/${BIZ}/packageUsage`).get();
      assert.equal(usageSnap.size, 1);
      const usage = usageSnap.docs[0].data();
      assert.equal(usage.id_cliente, CLIENT);
      assert.equal(usage.id_pacote_cliente, customerPackageId);
      assert.equal(usage.id_agendamento, appointmentId);
      assert.equal(usage.serviceName, 'Banho');

      // 5. And the package is still usable: a second booking debits again.
      const second = await call(CLIENT, bookingArgs({
        customerPackageId,
        startAt: FRIDAY_10,
      }));
      assert.ok(second.appointmentId);
      const twiceUsed = await docData(`businesses/${BIZ}/customerPackages/${customerPackageId}`);
      assert.equal(twiceUsed?.creditos_usados, 2);
      assert.equal(await countDocs(`businesses/${BIZ}/packageUsage`), 2);
    });
  });
});
