/**
 * Emulator tests for the createBusiness callable and business authorization
 * (multi-tenant foundation).
 *
 * Runs under `firebase emulators:exec --only firestore,storage,functions`.
 * Handlers are invoked in-process with a fake CallableRequest so the real
 * transaction logic runs against the emulator Firestore.
 */

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';

import 'mocha';
import assert from 'node:assert/strict';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { initializeApp, deleteApp, getApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import type { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

import { createBusinessHandler } from '../src/businesses/create-business';
import type { CreateBusinessArgs } from '../src/businesses/create-business';
import {
  getBusinessMembership,
  requireBusinessMembership,
  BUSINESS_ROLE,
} from '../src/businesses/business-authorization';

const PROJECT_ID = 'demo-meupet-agenda';

let env: ReturnType<typeof initializeTestEnvironment> extends Promise<infer T>
  ? T
  : never;
let adminApp: import('firebase-admin/app').App;
let adminDb: Firestore;
let ownsDefaultApp = false;

const uidOwner = 'owner-1';

/** Garante um app firebase-admin default (handlers usam getFirestore()). */
async function ensureDefaultApp(): Promise<void> {
  if (getApps().length === 0) {
    adminApp = initializeApp({ projectId: PROJECT_ID });
    ownsDefaultApp = true;
  } else {
    adminApp = getApp();
  }
}

function callableRequest<T>(data: T, uid: string): CallableRequest<T> {
  return { data, auth: { uid } } as unknown as CallableRequest<T>;
}

async function seedUser(uid: string, overrides: Record<string, unknown> = {}): Promise<void> {
  await adminDb.doc(`users/${uid}`).set({
    nome: 'Nome ' + uid,
    role: 'client',
    ativo: true,
    ...overrides,
  });
}

describe('createBusiness', () => {
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

  it('cria businesses/{id} + membership owner + projecao na mesma transacao', async () => {
    await seedUser(uidOwner);

    const result = await createBusinessHandler(
      callableRequest<CreateBusinessArgs>(
        { name: 'Pet Shop Central', idempotencyKey: 'k-1' },
        uidOwner,
      ),
    );

    assert.ok(result.businessId.length > 0);

    const business = (await adminDb.doc(`businesses/${result.businessId}`).get()).data()!;
    assert.equal(business.nome, 'Pet Shop Central');
    assert.equal(business.status, 'ATIVO');
    assert.equal(business.ownerId, uidOwner);
    assert.equal(business.timezone, 'America/Sao_Paulo');

    const membership = (await adminDb.doc(
      `businesses/${result.businessId}/members/${uidOwner}`,
    ).get()).data()!;
    assert.equal(membership.role, BUSINESS_ROLE.OWNER);
    assert.equal(membership.ativo, true);

    const projection = (await adminDb.doc(
      `users/${uidOwner}/businessMemberships/${result.businessId}`,
    ).get()).data()!;
    assert.equal(projection.role, BUSINESS_ROLE.OWNER);
    assert.equal(projection.businessName, 'Pet Shop Central');
    assert.equal(projection.businessId, result.businessId);
  });

  it('replay de idempotencia retorna a mesma businessId', async () => {
    await seedUser(uidOwner);

    const first = await createBusinessHandler(
      callableRequest<CreateBusinessArgs>(
        { name: 'Pet Shop Central', idempotencyKey: 'k-replay' },
        uidOwner,
      ),
    );
    const second = await createBusinessHandler(
      callableRequest<CreateBusinessArgs>(
        { name: 'Pet Shop Central', idempotencyKey: 'k-replay' },
        uidOwner,
      ),
    );

    assert.equal(second.businessId, first.businessId);

    const businesses = await adminDb.collection('businesses').get();
    assert.equal(businesses.size, 1);
  });

  it('chave de idempotencia de outro usuario e rejeitada', async () => {
    await seedUser(uidOwner);
    await seedUser('owner-2');

    await createBusinessHandler(
      callableRequest<CreateBusinessArgs>(
        { name: 'Loja A', idempotencyKey: 'k-cross' },
        uidOwner,
      ),
    );

    let error: HttpsError | undefined;
    try {
      await createBusinessHandler(
        callableRequest<CreateBusinessArgs>(
          { name: 'Loja B', idempotencyKey: 'k-cross' },
          'owner-2',
        ),
      );
    } catch (err) {
      error = err as HttpsError;
    }

    assert.ok(error);
    assert.equal(error.code, 'permission-denied');
  });

  it('exige perfil ativo', async () => {
    await seedUser(uidOwner, { ativo: false });

    let error: HttpsError | undefined;
    try {
      await createBusinessHandler(
        callableRequest<CreateBusinessArgs>({ name: 'Loja' }, uidOwner),
      );
    } catch (err) {
      error = err as HttpsError;
    }

    assert.ok(error);
    assert.equal(error.code, 'failed-precondition');
  });

  it('rejeita timezone nao suportado', async () => {
    await seedUser(uidOwner);

    let error: HttpsError | undefined;
    try {
      await createBusinessHandler(
        callableRequest<CreateBusinessArgs>(
          { name: 'Loja', timezone: 'Mars/Olympus' },
          uidOwner,
        ),
      );
    } catch (err) {
      error = err as HttpsError;
    }

    assert.ok(error);
    assert.equal(error.code, 'invalid-argument');
  });
});

describe('business authorization', () => {
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

  it('retorna null sem membership', async () => {
    const membership = await getBusinessMembership(adminDb, uidOwner, 'b1');
    assert.equal(membership, null);
  });

  it('requireBusinessMembership aprova owner ativo', async () => {
    await adminDb.doc('businesses/b1/members/owner-1').set({
      role: BUSINESS_ROLE.OWNER,
      ativo: true,
    });

    const membership = await requireBusinessMembership(
      adminDb,
      'owner-1',
      'b1',
    );
    assert.equal(membership.role, BUSINESS_ROLE.OWNER);
  });

  it('requireBusinessMembership bloqueia sem membership', async () => {
    let error: HttpsError | undefined;
    try {
      await requireBusinessMembership(adminDb, 'owner-1', 'b1');
    } catch (err) {
      error = err as HttpsError;
    }
    assert.ok(error);
    assert.equal(error.code, 'permission-denied');
  });

  it('requireBusinessMembership bloqueia membership inativa', async () => {
    await adminDb.doc('businesses/b1/members/owner-1').set({
      role: BUSINESS_ROLE.OWNER,
      ativo: false,
    });

    let error: HttpsError | undefined;
    try {
      await requireBusinessMembership(adminDb, 'owner-1', 'b1');
    } catch (err) {
      error = err as HttpsError;
    }
    assert.ok(error);
    assert.equal(error.code, 'permission-denied');
  });

  it('requireBusinessMembership bloqueia papel fora da lista', async () => {
    await adminDb.doc('businesses/b1/members/owner-1').set({
      role: BUSINESS_ROLE.CLIENT,
      ativo: true,
    });

    let error: HttpsError | undefined;
    try {
      await requireBusinessMembership(
        adminDb,
        'owner-1',
        'b1',
        new Set([BUSINESS_ROLE.OWNER]),
      );
    } catch (err) {
      error = err as HttpsError;
    }
    assert.ok(error);
    assert.equal(error.code, 'permission-denied');
  });
});
