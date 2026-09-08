/**
 * Emulator tests for the completeOwnProfile callable (transactional
 * completion of private profile data: CPF + address).
 *
 * Runs under the local emulator suite. The handler is invoked in-process
 * with a fake CallableRequest so the real transaction logic runs against
 * the emulator Firestore; step 2 (email via Auth) uses the Auth emulator
 * through the Admin SDK.
 */

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';

import 'mocha';
import assert from 'node:assert/strict';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { initializeApp, deleteApp, getApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import type { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

import { completeOwnProfileHandler } from '../src/profile/complete-own-profile';
import type { CompleteOwnProfileArgs } from '../src/profile/complete-own-profile';
import { cpfClaimId } from '../src/profile/cpf-claim';

const PROJECT_ID = 'demo-meupet-agenda';
const TEST_SECRET = 'test-secret';

const CPF_A = '123.456.789-09';
const CPF_A_DIGITS = '12345678909';
const CPF_B = '987.654.321-00';
const CPF_B_DIGITS = '98765432100';

const ADDRESS_A: CompleteOwnProfileArgs['address'] = {
  postalCode: '01310-100',
  street: 'Av. Paulista',
  number: '1000',
  complement: 'Apto 42',
  neighborhood: 'Bela Vista',
  city: 'Sao Paulo',
  state: 'sp',
  country: 'BR',
};

const ADDRESS_B: CompleteOwnProfileArgs['address'] = {
  postalCode: '20040020',
  street: 'Rua da Assembleia',
  number: '10',
  neighborhood: 'Centro',
  city: 'Rio de Janeiro',
  state: 'RJ',
  country: 'BR',
};

let env: ReturnType<typeof initializeTestEnvironment> extends Promise<infer T>
  ? T
  : never;
let adminApp: import('firebase-admin/app').App;
let adminDb: Firestore;
let ownsDefaultApp = false;

const uidA = 'profile-owner-a';
const uidB = 'profile-owner-b';

function callableRequest<T>(
  data: T,
  uid: string | null,
): CallableRequest<T> {
  return { data, auth: uid === null ? null : { uid } } as unknown as CallableRequest<T>;
}

/** Garante um app firebase-admin default (handlers usam getFirestore()). */
async function ensureDefaultApp(): Promise<void> {
  if (getApps().length === 0) {
    adminApp = initializeApp({ projectId: PROJECT_ID });
    ownsDefaultApp = true;
  } else {
    adminApp = getApp();
  }
}

/** Cria/atualiza o usuario no Auth emulator (email e fonte do passo 2). */
async function seedAuthUser(uid: string, email: string): Promise<void> {
  const auth = getAuth(adminApp);
  try {
    await auth.updateUser(uid, { email, emailVerified: true });
  } catch {
    await auth.createUser({ uid, email, emailVerified: true });
  }
}

async function removeAuthUser(uid: string): Promise<void> {
  try {
    await getAuth(adminApp).deleteUser(uid);
  } catch {
    // ausente no emulador: ok
  }
}

function args(overrides: Partial<CompleteOwnProfileArgs> = {}): CompleteOwnProfileArgs {
  return {
    name: 'Fulano de Tal',
    phone: '(11) 91234-5678',
    cpf: CPF_A,
    address: ADDRESS_A,
    ...overrides,
  };
}

async function captureError(promise: Promise<unknown>): Promise<HttpsError> {
  try {
    await promise;
  } catch (err) {
    return err as HttpsError;
  }
  assert.fail('esperava erro');
}

describe('completeOwnProfile', () => {
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
    await seedAuthUser(uidA, 'a@exemplo.com');
    await seedAuthUser(uidB, 'b@exemplo.com');
  });

  afterEach(async () => {
    await removeAuthUser(uidA);
    await removeAuthUser(uidB);
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
      completeOwnProfileHandler(
        callableRequest<CompleteOwnProfileArgs>(args(), null),
        TEST_SECRET,
      ),
    );
    assert.equal(error.code, 'unauthenticated');
  });

  it('cria perfil novo: users, userPrivate e claim na mesma transacao', async () => {
    const result = await completeOwnProfileHandler(
      callableRequest<CompleteOwnProfileArgs>(args(), uidA),
      TEST_SECRET,
    );

    assert.equal(result.profileComplete, true);
    assert.equal(result.cpfMasked, '***.***.***-09');

    const user = (await adminDb.doc(`users/${uidA}`).get()).data()!;
    assert.equal(user.nome, 'Fulano de Tal');
    assert.equal(user.email, 'a@exemplo.com');
    assert.equal(user.telefone, '11912345678');
    assert.equal(user.role, 'client');
    assert.equal(user.tipo_usuario, 'client');
    assert.equal(user.ativo, true);
    assert.equal(user.profileComplete, true);
    assert.equal(user.schemaVersion, 2);
    assert.ok(user.createdAt);
    assert.ok(user.updatedAt);

    const privateProfile = (await adminDb.doc(`userPrivate/${uidA}`).get()).data()!;
    assert.equal(privateProfile.cpf, CPF_A_DIGITS);
    assert.equal(privateProfile.cpfLast2, '09');
    assert.equal(privateProfile.address.postalCode, '01310100');
    assert.equal(privateProfile.address.street, 'Av. Paulista');
    assert.equal(privateProfile.address.number, '1000');
    assert.equal(privateProfile.address.complement, 'Apto 42');
    assert.equal(privateProfile.address.neighborhood, 'Bela Vista');
    assert.equal(privateProfile.address.city, 'Sao Paulo');
    assert.equal(privateProfile.address.state, 'SP');
    assert.equal(privateProfile.address.country, 'BR');
    assert.ok(privateProfile.createdAt);
    assert.ok(privateProfile.updatedAt);

    const claim = (await adminDb.doc(`cpfClaims/${cpfClaimId(CPF_A_DIGITS, TEST_SECRET)}`).get()).data()!;
    assert.equal(claim.uid, uidA);
  });

  it('complementa perfil existente preservando role e status', async () => {
    await adminDb.doc(`users/${uidA}`).set({
      nome: 'Nome Antigo',
      email: 'antigo@exemplo.com',
      role: 'collaborator',
      tipo_usuario: 'collaborator',
      ativo: false,
      profileComplete: false,
      schemaVersion: 0,
    });

    const result = await completeOwnProfileHandler(
      callableRequest<CompleteOwnProfileArgs>(args(), uidA),
      TEST_SECRET,
    );
    assert.equal(result.cpfMasked, '***.***.***-09');

    const user = (await adminDb.doc(`users/${uidA}`).get()).data()!;
    assert.equal(user.nome, 'Fulano de Tal');
    assert.equal(user.email, 'a@exemplo.com');
    assert.equal(user.role, 'collaborator');
    assert.equal(user.tipo_usuario, 'collaborator');
    assert.equal(user.ativo, false);
    assert.equal(user.profileComplete, true);
    assert.equal(user.schemaVersion, 2);

    const privateProfile = (await adminDb.doc(`userPrivate/${uidA}`).get()).data()!;
    assert.equal(privateProfile.cpf, CPF_A_DIGITS);
  });

  it('rejeita CPF ja reivindicado por outro UID sem deixar lixo', async () => {
    await completeOwnProfileHandler(
      callableRequest<CompleteOwnProfileArgs>(args(), uidA),
      TEST_SECRET,
    );

    const error = await captureError(
      completeOwnProfileHandler(
        callableRequest<CompleteOwnProfileArgs>(
          args({ name: 'Outra Pessoa', phone: null }),
          uidB,
        ),
        TEST_SECRET,
      ),
    );
    assert.equal(error.code, 'already-exists');

    assert.equal((await adminDb.doc(`users/${uidB}`).get()).exists, false);
    assert.equal((await adminDb.doc(`userPrivate/${uidB}`).get()).exists, false);

    const claims = await adminDb.collection('cpfClaims').get();
    assert.equal(claims.size, 1);
    assert.equal(claims.docs[0].data().uid, uidA);
  });

  it('replay do mesmo UID e idempotente', async () => {
    const first = await completeOwnProfileHandler(
      callableRequest<CompleteOwnProfileArgs>(args(), uidA),
      TEST_SECRET,
    );
    const second = await completeOwnProfileHandler(
      callableRequest<CompleteOwnProfileArgs>(args(), uidA),
      TEST_SECRET,
    );

    assert.equal(second.cpfMasked, first.cpfMasked);
    assert.equal(second.profileComplete, true);

    const claims = await adminDb.collection('cpfClaims').get();
    assert.equal(claims.size, 1);

    const privateProfile = (await adminDb.doc(`userPrivate/${uidA}`).get()).data()!;
    assert.equal(privateProfile.cpf, CPF_A_DIGITS);
    assert.equal(privateProfile.address.postalCode, '01310100');
  });

  it('rejeita tentativa de alterar CPF depois de concluido', async () => {
    await completeOwnProfileHandler(
      callableRequest<CompleteOwnProfileArgs>(args(), uidA),
      TEST_SECRET,
    );

    const error = await captureError(
      completeOwnProfileHandler(
        callableRequest<CompleteOwnProfileArgs>(args({ cpf: CPF_B }), uidA),
        TEST_SECRET,
      ),
    );
    assert.equal(error.code, 'failed-precondition');

    const privateProfile = (await adminDb.doc(`userPrivate/${uidA}`).get()).data()!;
    assert.equal(privateProfile.cpf, CPF_A_DIGITS);
    assert.equal(privateProfile.cpfLast2, '09');

    const claims = await adminDb.collection('cpfClaims').get();
    assert.equal(claims.size, 1);
    assert.equal(claims.docs[0].data().uid, uidA);
  });

  it('rejeita CPF invalido', async () => {
    const error = await captureError(
      completeOwnProfileHandler(
        callableRequest<CompleteOwnProfileArgs>(
          args({ cpf: '123.456.789-00' }),
          uidA,
        ),
        TEST_SECRET,
      ),
    );
    assert.equal(error.code, 'invalid-argument');
  });
});
