/**
 * Emulator tests for the joinBusiness callable: client joins an active pet
 * shop (membership role `client` + projection `businessMemberships`).
 *
 * Runs under `firebase emulators:exec --only firestore,auth,storage,functions`.
 */

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';

import 'mocha';
import assert from 'node:assert/strict';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { initializeApp, deleteApp, getApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import type { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

import { joinBusinessHandler } from '../src/businesses/join-business';
import type { JoinBusinessArgs } from '../src/businesses/join-business';

const PROJECT_ID = 'demo-meupet-agenda';

let env: ReturnType<typeof initializeTestEnvironment> extends Promise<infer T>
  ? T
  : never;
let adminApp: import('firebase-admin/app').App;
let adminDb: Firestore;
let ownsDefaultApp = false;

const uidClient = 'join-client';
const uidStaff = 'join-owner';

/** Garante um app firebase-admin default (handlers usam getFirestore()). */
async function ensureDefaultApp(): Promise<void> {
  if (getApps().length === 0) {
    adminApp = initializeApp({ projectId: PROJECT_ID });
    ownsDefaultApp = true;
  } else {
    adminApp = getApp();
  }
}

function callableRequest<T>(
  data: T,
  uid: string | null,
): CallableRequest<T> {
  return { data, auth: uid === null ? null : { uid } } as unknown as CallableRequest<T>;
}

async function seedUser(uid: string, overrides: Record<string, unknown> = {}): Promise<void> {
  await adminDb.doc(`users/${uid}`).set({
    nome: 'Nome ' + uid,
    role: 'client',
    ativo: true,
    profileComplete: true,
    ...overrides,
  });
}

async function seedBusiness(
  businessId: string,
  overrides: Record<string, unknown> = {},
): Promise<void> {
  await adminDb.doc(`businesses/${businessId}`).set({
    nome: 'Pet Shop ' + businessId,
    timezone: 'America/Sao_Paulo',
    status: 'ATIVO',
    ownerId: 'owner-' + businessId,
    ...overrides,
  });
}

async function captureError(promise: Promise<unknown>): Promise<HttpsError> {
  try {
    await promise;
  } catch (err) {
    return err as HttpsError;
  }
  assert.fail('esperava erro');
}

function args(overrides: Partial<JoinBusinessArgs> = {}): JoinBusinessArgs {
  return {
    businessId: 'biz1',
    idempotencyKey: 'k-join-1',
    ...overrides,
  };
}

describe('joinBusiness', () => {
  before(async function () {
    this.timeout(30_000);
    env = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { host: '127.0.0.1', port: 8080, rules: '' },
    });
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await ensureDefaultApp();
    adminDb = getFirestore(adminApp);
    await seedUser(uidClient);
    await seedUser(uidStaff);
  });

  afterEach(async () => {
    if (ownsDefaultApp) {
      await deleteApp(adminApp);
      ownsDefaultApp = false;
    }
  });

  after(async () => {
    await env.cleanup();
  });

  it('rejeita chamada nao autenticada', async () => {
    const error = await captureError(
      joinBusinessHandler(
        callableRequest<JoinBusinessArgs>(args(), null),
      ),
    );
    assert.equal(error.code, 'unauthenticated');
  });

  it('cria membership client + projecao na mesma transacao', async () => {
    await seedBusiness('biz1');

    const result = await joinBusinessHandler(
      callableRequest<JoinBusinessArgs>(args(), uidClient),
    );
    assert.equal(result.businessId, 'biz1');

    const member = (
      await adminDb.doc('businesses/biz1/members/join-client').get()
    ).data()!;
    assert.equal(member.role, 'client');
    assert.equal(member.ativo, true);

    const projection = (
      await adminDb.doc('users/join-client/businessMemberships/biz1').get()
    ).data()!;
    assert.equal(projection.role, 'client');
    assert.equal(projection.ativo, true);
    assert.equal(projection.businessName, 'Pet Shop biz1');
    assert.equal(projection.businessId, 'biz1');
  });

  it('rejeita loja inexistente', async () => {
    const error = await captureError(
      joinBusinessHandler(
        callableRequest<JoinBusinessArgs>(args(), uidClient),
      ),
    );
    assert.equal(error.code, 'not-found');
  });

  it('rejeita loja inativa', async () => {
    await seedBusiness('biz1', { status: 'INATIVO' });

    const error = await captureError(
      joinBusinessHandler(
        callableRequest<JoinBusinessArgs>(args(), uidClient),
      ),
    );
    assert.equal(error.code, 'failed-precondition');
  });

  it('replay e idempotente e nunca rebaixa staff', async () => {
    await seedBusiness('biz1');
    await adminDb.doc('businesses/biz1/members/join-owner').set({
      role: 'owner',
      ativo: true,
    });

    // Replay do mesmo client.
    await joinBusinessHandler(
      callableRequest<JoinBusinessArgs>(args(), uidClient),
    );
    const second = await joinBusinessHandler(
      callableRequest<JoinBusinessArgs>(args(), uidClient),
    );
    assert.equal(second.businessId, 'biz1');

    // Um membro por usuario (client + owner seedado), sem duplicatas.
    const members = await adminDb.collection('businesses/biz1/members').get();
    assert.equal(members.size, 2);
    assert.equal(members.docs[0].id, uidClient);
    assert.equal(members.docs[0].data().role, 'client');

    // Staff (owner) chamando join nao e rebaixado.
    const staffResult = await joinBusinessHandler(
      callableRequest<JoinBusinessArgs>(
        args({ idempotencyKey: 'k-join-staff' }),
        uidStaff,
      ),
    );
    assert.equal(staffResult.businessId, 'biz1');

    const staffMember = (
      await adminDb.doc('businesses/biz1/members/join-owner').get()
    ).data()!;
    assert.equal(staffMember.role, 'owner');
  });

  it('chave de idempotencia de outro usuario e rejeitada', async () => {
    await seedBusiness('biz1');

    await joinBusinessHandler(
      callableRequest<JoinBusinessArgs>(args(), uidClient),
    );

    const error = await captureError(
      joinBusinessHandler(
        callableRequest<JoinBusinessArgs>(
          args({ idempotencyKey: 'k-join-1' }),
          uidStaff,
        ),
      ),
    );
    assert.equal(error.code, 'permission-denied');
  });

  it('exige perfil ativo', async () => {
    await seedBusiness('biz1');
    await adminDb.doc(`users/${uidClient}`).set({
      nome: 'Inativo',
      role: 'client',
      ativo: false,
    });

    const error = await captureError(
      joinBusinessHandler(
        callableRequest<JoinBusinessArgs>(args(), uidClient),
      ),
    );
    assert.equal(error.code, 'failed-precondition');
  });

  it('rejeita businessId invalido', async () => {
    const error = await captureError(
      joinBusinessHandler(
        callableRequest<JoinBusinessArgs>(
          args({ businessId: 'bad/id' }),
          uidClient,
        ),
      ),
    );
    assert.equal(error.code, 'invalid-argument');
  });
});