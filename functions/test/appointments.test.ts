/**
 * Emulator tests for the createAppointment callable (Task 10).
 *
 * Runs under `firebase emulators:exec --only firestore,storage,functions`.
 * The exported handler is invoked in-process with a fake CallableRequest so
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

import type { CreateAppointmentArgs, CreateAppointmentResult } from '../src/appointments/create-appointment';
import { createAppointmentHandler } from '../src/appointments/create-appointment';
import type { CancelAppointmentArgs, CancelAppointmentResult } from '../src/appointments/cancel-appointment';
import { cancelAppointmentHandler } from '../src/appointments/cancel-appointment';
import { dayKey, slotDocId } from '../src/appointments/slot-keys';

const PROJECT_ID = process.env.FIREBASE_TEST_PROJECT_ID ?? 'demo-meupet-agenda';
if (!PROJECT_ID.startsWith('demo-')) {
  throw new Error(
    `Suites de teste exigem um project id demo-* (use FIREBASE_TEST_PROJECT_ID). Recebido: ${PROJECT_ID}`,
  );
}
// Compiled to functions/lib-test/test/, so the repo root is three levels up.
const RULES = readFileSync(join(__dirname, '..', '..', '..', 'firestore.rules'), 'utf8');

// America/Sao_Paulo = UTC-3 (sem DST desde 2019): para um relogio de parede
// W em SP, o instante UTC e W + 3h. Datas fixas expiram; aqui toda data de
// agendamento e calculada como a PROXIMA ocorrencia do dia da semana,
// sempre no futuro.
const SP_OFFSET_MS = 3 * 60 * 60 * 1000;

/**
 * Proxima ocorrencia de `weekday` (0=domingo .. 6=sabado) as `hour:minute`
 * em Sao Paulo, com `offsetDays` dias extras. Retorna ISO 8601 com -03:00.
 */
function saoPauloIso(weekday: number, hour: number, minute = 0, offsetDays = 0): string {
  const now = new Date(Date.now() + SP_OFFSET_MS); // relogio de parede em SP
  let delta = (weekday - now.getUTCDay() + 7) % 7;
  if (delta === 0) {
    delta = 7; // sempre a proxima semana, nunca hoje
  }
  // Instante UTC cuja parede em SP e (hour:minute) do dia alvo.
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
const FRIDAY_09_30 = saoPauloIso(5, 9, 30);
const FRIDAY_09_15 = saoPauloIso(5, 9, 15);
const FRIDAY_10 = saoPauloIso(5, 10);
const FRIDAY_11 = saoPauloIso(5, 11);
const FRIDAY_15 = saoPauloIso(5, 15);
const FRIDAY_16 = saoPauloIso(5, 16);
const FRIDAY_16_15 = saoPauloIso(5, 16, 15);
const FRIDAY_16_30 = saoPauloIso(5, 16, 30);
const FRIDAY_17 = saoPauloIso(5, 17);
const FRIDAY_17_30 = saoPauloIso(5, 17, 30);
const SATURDAY_11 = saoPauloIso(6, 11);
const SUNDAY_09 = saoPauloIso(0, 9);
const PAST_MORNING = '2020-01-01T09:00:00-03:00';

const CLIENT = 'alice';
const BIZ = 'biz-1';

let testEnv: Awaited<ReturnType<typeof initializeTestEnvironment>>;
let adminApp: ReturnType<typeof initializeApp>;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { host: '127.0.0.1', port: 8080, rules: RULES },
  });
  adminApp = initializeApp({ projectId: PROJECT_ID });
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

  await seed(`businesses/${BIZ}`, {
    nome: 'Loja Teste',
    timezone: 'America/Sao_Paulo',
    status: 'ATIVO',
  });
  await seed(`businesses/${BIZ}/members/alice`, { role: 'client', ativo: true });
  await seed(`businesses/${BIZ}/members/bob`, { role: 'client', ativo: true });
  await seed(`businesses/${BIZ}/members/admin1`, { role: 'admin', ativo: true });

  await seed(`businesses/${BIZ}/services/svc60`, {
    nome: 'Banho',
    descricao: 'Banho completo',
    duracao_minutos: 60,
    valor: 60,
    ativo: true,
  });
  await seed(`businesses/${BIZ}/services/svc90`, {
    nome: 'Tosa',
    descricao: 'Tosa higiênica',
    duracao_minutos: 90,
    valor: 80,
    ativo: true,
  });
  await seed(`businesses/${BIZ}/services/svc30`, {
    nome: 'Consulta',
    descricao: 'Consulta rápida',
    duracao_minutos: 30,
    valor: 40,
    ativo: true,
  });
  await seed(`businesses/${BIZ}/services/svc45`, {
    nome: 'Avaliacao',
    descricao: 'Avaliacao completa',
    duracao_minutos: 45,
    valor: 50,
    ativo: true,
  });
  // Servicos fora do grupo 'banho'/'tosa' nao sao restritos pelo horario
  // especial (fechamento util as 18:00).
  await seed(`businesses/${BIZ}/services/svc60normal`, {
    nome: 'Consulta estendida',
    descricao: 'Consulta com check-up completo',
    duracao_minutos: 60,
    valor: 90,
    ativo: true,
  });
  await seed(`businesses/${BIZ}/services/svc90normal`, {
    nome: 'Pacote avaliacao completa',
    descricao: 'Avaliacao detalhada',
    duracao_minutos: 90,
    valor: 120,
    ativo: true,
  });
  await seed(`businesses/${BIZ}/services/svcOff`, {
    nome: 'Corte',
    descricao: '',
    duracao_minutos: 30,
    valor: 30,
    ativo: false,
  });

  const validUntil = new Date('2027-01-01T00:00:00Z');
  await seed(`businesses/${BIZ}/customerPackages/cp1`, {
    id_cliente: CLIENT,
    id_pacote: 'pkg1',
    id_servico: 'svc60',
    creditos_totais: 1,
    creditos_usados: 0,
    data_validade: validUntil,
    status: 'ATIVO',
  });
  await seed(`businesses/${BIZ}/customerPackages/cp2`, {
    id_cliente: CLIENT,
    id_pacote: 'pkg2',
    id_servico: 'svc60',
    creditos_totais: 2,
    creditos_usados: 0,
    data_validade: validUntil,
    status: 'ATIVO',
  });
  await seed(`businesses/${BIZ}/customerPackages/cpExhausted`, {
    id_cliente: CLIENT,
    id_pacote: 'pkg3',
    id_servico: 'svc60',
    creditos_totais: 1,
    creditos_usados: 1,
    data_validade: validUntil,
    status: 'ATIVO',
  });
  await seed(`businesses/${BIZ}/customerPackages/cpBob`, {
    id_cliente: 'bob',
    id_pacote: 'pkg4',
    id_servico: 'svc60',
    creditos_totais: 2,
    creditos_usados: 0,
    data_validade: validUntil,
    status: 'ATIVO',
  });
  // Vencido mas ainda marcado ATIVO: nunca pode ser consumido.
  await seed(`businesses/${BIZ}/customerPackages/cpExpired`, {
    id_cliente: CLIENT,
    id_pacote: 'pkg5',
    id_servico: 'svc60',
    creditos_totais: 2,
    creditos_usados: 0,
    data_validade: new Date('2020-01-01T00:00:00Z'),
    status: 'ATIVO',
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

function iso(date: Date): string {
  return date.toISOString();
}

describe('createAppointment', () => {
  const baseArgs = (overrides: Partial<CreateAppointmentArgs> = {}): CreateAppointmentArgs => ({
    businessId: BIZ,
    serviceId: 'svc60',
    startAt: FRIDAY_09,
    ...overrides,
  });

  it('creates an appointment and locks every covered slot', async () => {
    const result = await call(CLIENT, baseArgs());

    assert.equal(typeof result.appointmentId, 'string');
    assert.ok(result.appointmentId.length > 0);

    const appointment = await docData(`businesses/${BIZ}/appointments/${result.appointmentId}`);
    assert.ok(appointment);
    assert.equal(appointment.id_cliente, CLIENT);
    assert.equal(appointment.clientName, 'Alice Silva');
    assert.equal(appointment.id_servico, 'svc60');
    assert.equal(appointment.serviceName, 'Banho');
    assert.equal(appointment.id_pacote_cliente, null);
    assert.equal(appointment.dayKey, dayKey(new Date(FRIDAY_09)));
    assert.equal(appointment.timeKey, '09:00');
    assert.equal(appointment.status, 'AGENDADO');
    assert.equal(
      iso((appointment.data_hora_inicio as Timestamp).toDate()),
      iso(new Date(FRIDAY_09)),
    );
    assert.equal(
      iso((appointment.data_hora_fim as Timestamp).toDate()),
      iso(new Date(FRIDAY_10)),
    );

    for (const time of ['09:00', '09:30']) {
      const slot = await docData(
        `businesses/${BIZ}/appointmentSlots/${slotDocId(BIZ, dayKey(new Date(FRIDAY_09)), time)}`,
      );
      assert.ok(slot, `slot ${time} should be locked`);
      assert.equal(slot.appointmentId, result.appointmentId);
    }
    assert.equal(await countDocs(`businesses/${BIZ}/appointments`), 1);
  });

  it('exactly one of two concurrent creates for the same slot wins', async () => {
    const args = baseArgs();
    const results = await Promise.allSettled([call(CLIENT, args), call(CLIENT, args)]);

    const fulfilled = results.filter((r) => r.status === 'fulfilled');
    const rejected = results.filter((r) => r.status === 'rejected');
    assert.equal(fulfilled.length, 1);
    assert.equal(rejected.length, 1);
    const failure = rejected[0] as PromiseRejectedResult;
    assert.equal((failure.reason as HttpsError).code, 'already-exists');
    assert.equal(await countDocs(`businesses/${BIZ}/appointments`), 1);
    assert.equal(await countDocs(`businesses/${BIZ}/appointmentSlots`), 2);
  });

  it('rejects a booking that overlaps an existing reservation', async () => {
    await call(CLIENT, baseArgs({ startAt: FRIDAY_09 })); // locks 09:00 + 09:30
    await expectError(call(CLIENT, baseArgs({ startAt: FRIDAY_09_30 })), 'already-exists');
  });

  it('90-minute service locks three slots and conflicts with a 09:30 start', async () => {
    const result = await call(CLIENT, baseArgs({ serviceId: 'svc90' }));
    const friday = dayKey(new Date(FRIDAY_09));
    for (const time of ['09:00', '09:30', '10:00']) {
      const slot = await docData(
        `businesses/${BIZ}/appointmentSlots/${slotDocId(BIZ, friday, time)}`,
      );
      assert.ok(slot, `slot ${time} should be locked`);
      assert.equal(slot.appointmentId, result.appointmentId);
    }
    await expectError(call(CLIENT, baseArgs({ startAt: FRIDAY_09_30 })), 'already-exists');
  });

  it('decrements package credit once and finalizes a full package', async () => {
    const result = await call(CLIENT, baseArgs({ customerPackageId: 'cp1' }));

    const packageDoc = await docData(`businesses/${BIZ}/customerPackages/cp1`);
    assert.ok(packageDoc);
    assert.equal(packageDoc.creditos_usados, 1);
    assert.equal(packageDoc.status, 'FINALIZADO');

    assert.equal(await countDocs(`businesses/${BIZ}/packageUsage`), 1);
    const usageSnap = await db().collection(`businesses/${BIZ}/packageUsage`).get();
    const usageDoc = usageSnap.docs[0].data();
    assert.equal(usageDoc.id_cliente, CLIENT);
    assert.equal(usageDoc.clientName, 'Alice Silva');
    assert.equal(usageDoc.id_pacote_cliente, 'cp1');
    assert.equal(usageDoc.id_agendamento, result.appointmentId);
    assert.equal(usageDoc.serviceName, 'Banho');
  });

  it('keeps package ATIVO with remaining credits', async () => {
    await call(CLIENT, baseArgs({ customerPackageId: 'cp2' }));
    const packageDoc = await docData(`businesses/${BIZ}/customerPackages/cp2`);
    assert.equal(packageDoc?.creditos_usados, 1);
    assert.equal(packageDoc?.status, 'ATIVO');
  });

  it('rejects a package that does not belong to the caller', async () => {
    await expectError(call(CLIENT, baseArgs({ customerPackageId: 'cpBob' })), 'permission-denied');
  });

  it('rejects a package with no credits left', async () => {
    await expectError(call(CLIENT, baseArgs({ customerPackageId: 'cpExhausted' })), 'failed-precondition');
  });

  it('returns the same appointment for repeated idempotency keys', async () => {
    const args = baseArgs({ idempotencyKey: 'booking-alice-1' });
    const first = await call(CLIENT, args);
    const second = await call(CLIENT, args);

    assert.equal(second.appointmentId, first.appointmentId);
    assert.equal(await countDocs(`businesses/${BIZ}/appointments`), 1);
    assert.equal(await countDocs(`businesses/${BIZ}/appointmentSlots`), 2);
    const idem = await docData('appointmentIdempotency/booking-alice-1');
    assert.equal(idem?.appointmentId, first.appointmentId);
    assert.equal(idem?.uid, CLIENT);
  });

  it('rejects unauthenticated calls', async () => {
    await expectError(call(null, baseArgs()), 'unauthenticated');
  });

  it('rejects when the service is inactive', async () => {
    await expectError(call(CLIENT, baseArgs({ serviceId: 'svcOff' })), 'failed-precondition');
  });

  it('rejects bookings on Sunday', async () => {
    await expectError(call(CLIENT, baseArgs({ startAt: SUNDAY_09 })), 'failed-precondition');
  });

  it('rejects bath/grooming outside restricted hours (Saturday 11:00)', async () => {
    await expectError(call(CLIENT, baseArgs({ startAt: SATURDAY_11 })), 'failed-precondition');
  });

  it('allows non-restricted services on Saturday morning', async () => {
    const result = await call(CLIENT, baseArgs({ startAt: SATURDAY_11, serviceId: 'svc30' }));
    assert.ok(result.appointmentId);
  });

  it('rejects bath/grooming that ends past the 16:00 restricted close', async () => {
    await expectError(call(CLIENT, baseArgs({ startAt: FRIDAY_16 })), 'failed-precondition');
  });

  it('allows bath/grooming ending exactly at the 16:00 restricted close', async () => {
    const result = await call(CLIENT, baseArgs({ startAt: FRIDAY_15 }));
    assert.ok(result.appointmentId);
  });

  it('allows a non-restricted service ending exactly at 18:00', async () => {
    const result = await call(CLIENT, baseArgs({ serviceId: 'svc60normal', startAt: FRIDAY_17 }));
    assert.ok(result.appointmentId);
  });

  it('rejects a non-restricted service ending past 18:00', async () => {
    await expectError(
      call(CLIENT, baseArgs({ serviceId: 'svc60normal', startAt: FRIDAY_17_30 })),
      'failed-precondition',
    );
  });

  it('rejects a Saturday service ending past 12:00', async () => {
    await expectError(
      call(CLIENT, baseArgs({ serviceId: 'svc90normal', startAt: SATURDAY_11 })),
      'failed-precondition',
    );
  });

  it('rejects bath/grooming at weekday 16:15', async () => {
    await expectError(call(CLIENT, baseArgs({ startAt: FRIDAY_16_15 })), 'invalid-argument');
  });

  it('rejects bath/grooming at weekday 16:30 (past restricted close)', async () => {
    await expectError(call(CLIENT, baseArgs({ startAt: FRIDAY_16_30 })), 'failed-precondition');
  });

  it('rejects a service duration outside the 30-minute grid', async () => {
    await expectError(call(CLIENT, baseArgs({ serviceId: 'svc45' })), 'invalid-argument');
  });

  it('rejects a start time outside the 30-minute grid', async () => {
    await expectError(call(CLIENT, baseArgs({ startAt: FRIDAY_09_15 })), 'invalid-argument');
  });

  it('rejects a naive ISO startAt without timezone offset (T10)', async () => {
    await expectError(
      call(CLIENT, baseArgs({ startAt: '2026-08-14T09:00:00' })),
      'invalid-argument',
    );
  });

  it('rejects a booking in the past', async () => {
    await expectError(call(CLIENT, baseArgs({ startAt: PAST_MORNING })), 'invalid-argument');
  });

  it('rejects an expired customer package even when still marked ATIVO', async () => {
    await expectError(
      call(CLIENT, baseArgs({ customerPackageId: 'cpExpired' })),
      'failed-precondition',
    );
    // Nada foi gravado: nenhum uso de pacote, nenhum agendamento.
    assert.equal(await countDocs(`businesses/${BIZ}/packageUsage`), 0);
    assert.equal(await countDocs(`businesses/${BIZ}/appointments`), 0);
  });
});

describe('cancelAppointment', () => {
  const baseArgs = (overrides: Partial<CreateAppointmentArgs> = {}): CreateAppointmentArgs => ({
    businessId: BIZ,
    serviceId: 'svc60',
    startAt: FRIDAY_09,
    ...overrides,
  });

  async function createAppointment(
    overrides: Partial<CreateAppointmentArgs> = {},
  ): Promise<string> {
    const result = await call(CLIENT, baseArgs(overrides));
    return result.appointmentId;
  }

  it('cancels: status CANCELADO, cancel metadata set, slot locks released', async () => {
    const appointmentId = await createAppointment();
    assert.equal(await countDocs(`businesses/${BIZ}/appointmentSlots`), 2);

    const result = await cancelCall(CLIENT, { businessId: BIZ, appointmentId });

    assert.deepEqual(result, { appointmentId, canceled: true });
    const appointment = await docData(`businesses/${BIZ}/appointments/${appointmentId}`);
    assert.ok(appointment);
    assert.equal(appointment.status, 'CANCELADO');
    assert.equal(appointment.canceledBy, CLIENT);
    assert.ok(appointment.canceledAt instanceof Timestamp);
    assert.ok(appointment.updatedAt instanceof Timestamp);
    assert.equal(await countDocs(`businesses/${BIZ}/appointmentSlots`), 0);
  });

  it('cancel twice: second call is a no-op and credits are refunded once', async () => {
    const appointmentId = await createAppointment({ customerPackageId: 'cp2' });
    assert.equal((await docData(`businesses/${BIZ}/customerPackages/cp2`))?.creditos_usados, 1);

    const first = await cancelCall(CLIENT, { businessId: BIZ, appointmentId });
    assert.deepEqual(first, { appointmentId, canceled: true });

    const second = await cancelCall(CLIENT, { businessId: BIZ, appointmentId });
    assert.deepEqual(second, { appointmentId, canceled: false });

    const packageDoc = await docData(`businesses/${BIZ}/customerPackages/cp2`);
    assert.equal(packageDoc?.creditos_usados, 0);
    assert.equal(packageDoc?.status, 'ATIVO');
  });

  it('refund restores a FINALIZADO package to ATIVO', async () => {
    const appointmentId = await createAppointment({ customerPackageId: 'cp1' });
    assert.equal((await docData(`businesses/${BIZ}/customerPackages/cp1`))?.status, 'FINALIZADO');

    await cancelCall(CLIENT, { businessId: BIZ, appointmentId });

    const packageDoc = await docData(`businesses/${BIZ}/customerPackages/cp1`);
    assert.equal(packageDoc?.creditos_usados, 0);
    assert.equal(packageDoc?.status, 'ATIVO');
  });

  it('marks the matching packageUsage record estornado exactly once', async () => {
    const appointmentId = await createAppointment({ customerPackageId: 'cp2' });

    await cancelCall(CLIENT, { businessId: BIZ, appointmentId });
    await cancelCall(CLIENT, { businessId: BIZ, appointmentId });

    const usageSnap = await db().collection(`businesses/${BIZ}/packageUsage`).get();
    assert.equal(usageSnap.size, 1);
    const usageDoc = usageSnap.docs[0].data();
    assert.equal(usageDoc.id_agendamento, appointmentId);
    assert.equal(usageDoc.estornado, true);
    assert.equal(usageDoc.updatedAt instanceof Timestamp, true);
  });

  it('expired package: credits decremented but status not resurrected', async () => {
    const appointmentId = await createAppointment({ customerPackageId: 'cp2' });
    await seed(`businesses/${BIZ}/customerPackages/cp2`, {
      id_cliente: CLIENT,
      id_pacote: 'pkg2',
      id_servico: 'svc60',
      creditos_totais: 2,
      creditos_usados: 1,
      data_validade: new Date('2027-01-01T00:00:00Z'),
      status: 'VENCIDO',
    });

    const result = await cancelCall(CLIENT, { businessId: BIZ, appointmentId });
    assert.equal(result.canceled, true);

    const packageDoc = await docData(`businesses/${BIZ}/customerPackages/cp2`);
    assert.equal(packageDoc?.creditos_usados, 0);
    assert.equal(packageDoc?.status, 'VENCIDO');
  });

  it('canceled package: credits decremented but status not resurrected', async () => {
    const appointmentId = await createAppointment({ customerPackageId: 'cp2' });
    await seed(`businesses/${BIZ}/customerPackages/cp2`, {
      id_cliente: CLIENT,
      id_pacote: 'pkg2',
      id_servico: 'svc60',
      creditos_totais: 2,
      creditos_usados: 1,
      data_validade: new Date('2027-01-01T00:00:00Z'),
      status: 'CANCELADO',
    });

    const result = await cancelCall(CLIENT, { businessId: BIZ, appointmentId });
    assert.equal(result.canceled, true);

    const packageDoc = await docData(`businesses/${BIZ}/customerPackages/cp2`);
    assert.equal(packageDoc?.creditos_usados, 0);
    assert.equal(packageDoc?.status, 'CANCELADO');
  });

  it('rejects an unrelated client', async () => {
    const appointmentId = await createAppointment();
    await expectError(cancelCall('bob', { businessId: BIZ, appointmentId }), 'permission-denied');

    const appointment = await docData(`businesses/${BIZ}/appointments/${appointmentId}`);
    assert.equal(appointment?.status, 'AGENDADO');
    assert.equal(await countDocs(`businesses/${BIZ}/appointmentSlots`), 2);
  });

  it('allows staff to cancel on behalf of the client', async () => {
    const appointmentId = await createAppointment();
    const result = await cancelCall('admin1', { businessId: BIZ, appointmentId });

    assert.deepEqual(result, { appointmentId, canceled: true });
    const appointment = await docData(`businesses/${BIZ}/appointments/${appointmentId}`);
    assert.equal(appointment?.status, 'CANCELADO');
    assert.equal(appointment?.canceledBy, 'admin1');
    assert.equal(await countDocs(`businesses/${BIZ}/appointmentSlots`), 0);
  });

  it('idempotencyKey: same key twice returns the same stored result', async () => {
    const appointmentId = await createAppointment({ customerPackageId: 'cp2' });

    const first = await cancelCall(CLIENT, {
      businessId: BIZ,
      appointmentId,
      idempotencyKey: 'cancel-alice-1',
    });
    const second = await cancelCall(CLIENT, {
      businessId: BIZ,
      appointmentId,
      idempotencyKey: 'cancel-alice-1',
    });

    assert.deepEqual(first, { appointmentId, canceled: true });
    assert.deepEqual(second, first);
    assert.equal((await docData(`businesses/${BIZ}/customerPackages/cp2`))?.creditos_usados, 0);
    assert.equal(await countDocs(`businesses/${BIZ}/appointments`), 1);

    const idem = await docData('cancelAppointmentIdempotency/cancel-alice-1');
    assert.equal(idem?.uid, CLIENT);
    assert.equal(idem?.appointmentId, appointmentId);
    assert.equal(idem?.canceled, true);
  });

  it('idempotencyKey on an already-canceled appointment returns the no-op', async () => {
    const appointmentId = await createAppointment();
    await cancelCall(CLIENT, { businessId: BIZ, appointmentId });

    const result = await cancelCall(CLIENT, {
      businessId: BIZ,
      appointmentId,
      idempotencyKey: 'cancel-alice-already',
    });
    assert.deepEqual(result, { appointmentId, canceled: false });
    const idem = await docData('cancelAppointmentIdempotency/cancel-alice-already');
    assert.equal(idem?.canceled, false);
  });

  it('rejects an idempotency key belonging to another user', async () => {
    const appointmentId = await createAppointment();
    await cancelCall(CLIENT, { businessId: BIZ, appointmentId, idempotencyKey: 'shared-key' });
    await expectError(
      cancelCall('bob', { businessId: BIZ, appointmentId, idempotencyKey: 'shared-key' }),
      'permission-denied',
    );
  });

  it('rejects unauthenticated calls', async () => {
    const appointmentId = await createAppointment();
    await expectError(cancelCall(null, { businessId: BIZ, appointmentId }), 'unauthenticated');
  });

  it('rejects a missing appointment', async () => {
    await expectError(
      cancelCall(CLIENT, { businessId: BIZ, appointmentId: 'ghost' }),
      'not-found',
    );
  });

  it('rejects canceling a CONCLUIDO appointment (no refund for completed work)', async () => {
    const appointmentId = await createAppointment({ customerPackageId: 'cp2' });
    assert.equal((await docData(`businesses/${BIZ}/customerPackages/cp2`))?.creditos_usados, 1);
    await db().doc(`businesses/${BIZ}/appointments/${appointmentId}`).update({ status: 'CONCLUIDO' });

    await expectError(cancelCall(CLIENT, { businessId: BIZ, appointmentId }), 'failed-precondition');

    // Estado intacto: sem estorno, sem liberacao de slots.
    const appointment = await docData(`businesses/${BIZ}/appointments/${appointmentId}`);
    assert.equal(appointment?.status, 'CONCLUIDO');
    assert.equal((await docData(`businesses/${BIZ}/customerPackages/cp2`))?.creditos_usados, 1);
    assert.equal(await countDocs(`businesses/${BIZ}/appointmentSlots`), 2);
  });

  it('allows canceling a CONFIRMADO appointment with a single refund', async () => {
    const appointmentId = await createAppointment({ customerPackageId: 'cp2' });
    await db().doc(`businesses/${BIZ}/appointments/${appointmentId}`).update({ status: 'CONFIRMADO' });

    const result = await cancelCall(CLIENT, { businessId: BIZ, appointmentId });
    assert.deepEqual(result, { appointmentId, canceled: true });

    const appointment = await docData(`businesses/${BIZ}/appointments/${appointmentId}`);
    assert.equal(appointment?.status, 'CANCELADO');
    assert.equal((await docData(`businesses/${BIZ}/customerPackages/cp2`))?.creditos_usados, 0);
    assert.equal(await countDocs(`businesses/${BIZ}/appointmentSlots`), 0);
  });
});
