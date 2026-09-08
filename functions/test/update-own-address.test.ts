/**
 * Emulator tests for the updateOwnAddress callable (address-only update of
 * the caller's private profile).
 *
 * Runs under the local emulator suite. The handler is invoked in-process
 * with a fake CallableRequest so the real transaction logic runs against
 * the emulator Firestore. No Auth emulator dependency: this callable only
 * validates the profile document.
 */

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';

import 'mocha';
import assert from 'node:assert/strict';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { initializeApp, deleteApp, getApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import type { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

import { updateOwnAddressHandler } from '../src/profile/update-own-address';
import type { UpdateOwnAddressArgs } from '../src/profile/update-own-address';

const PROJECT_ID = 'demo-meupet-agenda';

const CPF_A_DIGITS = '12345678909';

const ADDRESS_A: UpdateOwnAddressArgs['address'] = {
  postalCode: '01310100',
  street: 'Av. Paulista',
  number: '1000',
  complement: 'Apto 42',
  neighborhood: 'Bela Vista',
  city: 'Sao Paulo',
  state: 'SP',
  country: 'BR',
};

const ADDRESS_B: UpdateOwnAddressArgs['address'] = {
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

const uidA = 'address-owner-a';

function callableRequest<T>(
  data: T,
  uid: string | null,
): CallableRequest<T> {
  return {
    data,
    auth: uid === null ? null : { uid },
  } as unknown as CallableRequest<T>;
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

/** Cria o perfil publico + privado de um usuario ativo e completo. */
async function seedCompleteProfile(uid: string): Promise<void> {
  await adminDb.doc(`users/${uid}`).set({
    nome: 'Fulano de Tal',
    email: 'fulano@exemplo.com',
    role: 'client',
    tipo_usuario: 'client',
    ativo: true,
    profileComplete: true,
    schemaVersion: 2,
    updatedAt: new Date(),
  });
  await adminDb.doc(`userPrivate/${uid}`).set({
    cpf: CPF_A_DIGITS,
    cpfLast2: '09',
    address: ADDRESS_A,
    updatedAt: new Date(),
  });
}

function args(
  overrides: Partial<UpdateOwnAddressArgs> = {},
): UpdateOwnAddressArgs {
  return { address: ADDRESS_B, ...overrides };
}

async function captureError(promise: Promise<unknown>): Promise<HttpsError> {
  try {
    await promise;
  } catch (err) {
    return err as HttpsError;
  }
  assert.fail('esperava erro');
}

describe('updateOwnAddress', () => {
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
    await seedCompleteProfile(uidA);
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
      updateOwnAddressHandler(callableRequest<UpdateOwnAddressArgs>(args(), null)),
    );
    assert.equal(error.code, 'unauthenticated');
  });

  it('atualiza apenas o endereco do perfil privado', async () => {
    const before = await adminDb.doc(`users/${uidA}`).get();

    const result = await updateOwnAddressHandler(
      callableRequest<UpdateOwnAddressArgs>(args(), uidA),
    );
    assert.equal(result.updated, true);

    const privateProfile = (
      await adminDb.doc(`userPrivate/${uidA}`).get()
    ).data()!;
    assert.equal(privateProfile.cpf, CPF_A_DIGITS);
    assert.equal(privateProfile.cpfLast2, '09');
    assert.equal(privateProfile.address.postalCode, '20040020');
    assert.equal(privateProfile.address.street, 'Rua da Assembleia');
    assert.equal(privateProfile.address.number, '10');
    assert.equal(privateProfile.address.neighborhood, 'Centro');
    assert.equal(privateProfile.address.city, 'Rio de Janeiro');
    assert.equal(privateProfile.address.state, 'RJ');
    assert.equal(privateProfile.address.country, 'BR');
    assert.ok(privateProfile.updatedAt);

    const after = await adminDb.doc(`users/${uidA}`).get();
    assert.deepEqual(after.data(), before.data());
  });

  it('rejeita endereco invalido sem tocar no perfil', async () => {
    const error = await captureError(
      updateOwnAddressHandler(
        callableRequest<UpdateOwnAddressArgs>(
          {
            address: {
              postalCode: '20040020',
              street: 'Rua da Assembleia',
              number: '10',
              neighborhood: 'Centro',
              city: 'Rio de Janeiro',
              state: 'RJ',
              country: 'US',
            },
          } as unknown as UpdateOwnAddressArgs,
          uidA,
        ),
      ),
    );
    assert.equal(error.code, 'invalid-argument');

    const privateProfile = (
      await adminDb.doc(`userPrivate/${uidA}`).get()
    ).data()!;
    assert.equal(privateProfile.address.postalCode, '01310100');
    assert.equal(privateProfile.address.street, 'Av. Paulista');
  });

  it('rejeita payload vazio', async () => {
    const error = await captureError(
      updateOwnAddressHandler(
        callableRequest<UpdateOwnAddressArgs>(
          null as unknown as UpdateOwnAddressArgs,
          uidA,
        ),
      ),
    );
    assert.equal(error.code, 'invalid-argument');
  });

  it('rejeita perfil publico inativo', async () => {
    await adminDb.doc(`users/${uidA}`).update({ ativo: false });

    const error = await captureError(
      updateOwnAddressHandler(
        callableRequest<UpdateOwnAddressArgs>(args(), uidA),
      ),
    );
    assert.equal(error.code, 'failed-precondition');
  });

  it('rejeita usuario sem documento privado', async () => {
    await adminDb.doc(`userPrivate/${uidA}`).delete();

    const error = await captureError(
      updateOwnAddressHandler(
        callableRequest<UpdateOwnAddressArgs>(args(), uidA),
      ),
    );
    assert.equal(error.code, 'failed-precondition');
  });

  it('rejeita usuario sem perfil publico', async () => {
    await adminDb.doc(`users/${uidA}`).delete();

    const error = await captureError(
      updateOwnAddressHandler(
        callableRequest<UpdateOwnAddressArgs>(args(), uidA),
      ),
    );
    assert.equal(error.code, 'permission-denied');
  });
});
