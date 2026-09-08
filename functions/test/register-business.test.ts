/**
 * Emulator tests for the registerBusiness callable: transactional creation
 * of the owner profile (users/{uid} + userPrivate/{uid}) and the business
 * (businesses/{id} + membership owner + projection + CNPJ claim).
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
import { getAuth } from 'firebase-admin/auth';
import type { CallableRequest, HttpsError } from 'firebase-functions/v2/https';

import { registerBusinessHandler } from '../src/businesses/register-business';
import type { RegisterBusinessArgs } from '../src/businesses/register-business';
import { cnpjClaimId } from '../src/businesses/cnpj-validation';
import { cpfClaimId } from '../src/profile/cpf-claim';

const PROJECT_ID = 'demo-meupet-agenda';
const CPF_SECRET = 'cpf-test-secret';
const CNPJ_SECRET = 'cnpj-test-secret';

const CPF_A = '123.456.789-09';
const CPF_A_DIGITS = '12345678909';
const CNPJ_A = '11.222.333/0001-81';
const CNPJ_A_DIGITS = '11222333000181';

const ADDRESS: RegisterBusinessArgs['address'] = {
  postalCode: '01310-100',
  street: 'Av. Paulista',
  number: '1000',
  complement: 'Loja 5',
  neighborhood: 'Bela Vista',
  city: 'Sao Paulo',
  state: 'sp',
  country: 'BR',
};

let env: ReturnType<typeof initializeTestEnvironment> extends Promise<infer T>
  ? T
  : never;
let adminApp: import('firebase-admin/app').App;
let adminDb: Firestore;
let ownsDefaultApp = false;

const uidA = 'business-owner-a';
const uidB = 'business-owner-b';

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

/** Cria/atualiza o usuario no Auth emulator (email e fonte do handler). */
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

function args(
  overrides: Partial<RegisterBusinessArgs> = {},
): RegisterBusinessArgs {
  return {
    name: 'Fulano de Tal',
    phone: '(11) 91234-5678',
    cpf: CPF_A,
    cnpj: CNPJ_A,
    businessName: 'Pet Shop Central',
    businessLegalName: 'Central Pet Comercio LTDA',
    businessPhone: '(11) 4002-8922',
    businessDescription: 'Banho, tosa e racoes.',
    address: ADDRESS,
    idempotencyKey: 'k-register-biz-1',
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

describe('registerBusiness', () => {
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
      registerBusinessHandler(
        callableRequest<RegisterBusinessArgs>(args(), null),
        CPF_SECRET,
        CNPJ_SECRET,
      ),
    );
    assert.equal(error.code, 'unauthenticated');
  });

  it('cria usuario, loja, membership e projecao na mesma transacao', async () => {
    const result = await registerBusinessHandler(
      callableRequest<RegisterBusinessArgs>(args(), uidA),
      CPF_SECRET,
      CNPJ_SECRET,
    );

    assert.ok(result.businessId.length > 0);
    assert.equal(result.cnpjMasked, '**.***.***/****-81');

    const user = (await adminDb.doc(`users/${uidA}`).get()).data()!;
    assert.equal(user.nome, 'Fulano de Tal');
    assert.equal(user.email, 'a@exemplo.com');
    assert.equal(user.telefone, '11912345678');
    assert.equal(user.role, 'admin');
    assert.equal(user.tipo_usuario, 'admin');
    assert.equal(user.ativo, true);
    assert.equal(user.profileComplete, true);
    assert.equal(user.schemaVersion, 2);

    const privateProfile = (
      await adminDb.doc(`userPrivate/${uidA}`).get()
    ).data()!;
    assert.equal(privateProfile.cpf, CPF_A_DIGITS);
    assert.equal(privateProfile.cpfLast2, '09');
    assert.equal(privateProfile.address.postalCode, '01310100');

    const business = (
      await adminDb.doc(`businesses/${result.businessId}`).get()
    ).data()!;
    assert.equal(business.nome, 'Pet Shop Central');
    assert.equal(business.razaoSocial, 'Central Pet Comercio LTDA');
    assert.equal(business.cnpj, CNPJ_A_DIGITS);
    assert.equal(business.cnpjLast2, '81');
    assert.equal(business.telefone, '1140028922');
    assert.equal(business.descricao, 'Banho, tosa e racoes.');
    assert.equal(business.endereco.postalCode, '01310100');
    assert.equal(business.timezone, 'America/Sao_Paulo');
    assert.equal(business.status, 'ATIVO');
    assert.equal(business.ownerId, uidA);

    const membership = (
      await adminDb.doc(
        `businesses/${result.businessId}/members/${uidA}`,
      ).get()
    ).data()!;
    assert.equal(membership.role, 'owner');
    assert.equal(membership.ativo, true);

    const projection = (
      await adminDb.doc(
        `users/${uidA}/businessMemberships/${result.businessId}`,
      ).get()
    ).data()!;
    assert.equal(projection.role, 'owner');
    assert.equal(projection.businessName, 'Pet Shop Central');
    assert.equal(projection.businessId, result.businessId);

    const cpfClaim = (
      await adminDb.doc(`cpfClaims/${cpfClaimId(CPF_A_DIGITS, CPF_SECRET)}`).get()
    ).data()!;
    assert.equal(cpfClaim.uid, uidA);

    const cnpjClaim = (
      await adminDb.doc(`cnpjClaims/${cnpjClaimId(CNPJ_A_DIGITS, CNPJ_SECRET)}`).get()
    ).data()!;
    assert.equal(cnpjClaim.uid, uidA);
    assert.equal(cnpjClaim.businessId, result.businessId);
  });

  it('rejeita CNPJ ja cadastrado por outra loja', async () => {
    await registerBusinessHandler(
      callableRequest<RegisterBusinessArgs>(args(), uidA),
      CPF_SECRET,
      CNPJ_SECRET,
    );

    const error = await captureError(
      registerBusinessHandler(
        callableRequest<RegisterBusinessArgs>(
          args({
            cpf: '987.654.321-00',
            idempotencyKey: 'k-register-biz-2',
          }),
          uidB,
        ),
        CPF_SECRET,
        CNPJ_SECRET,
      ),
    );
    assert.equal(error.code, 'already-exists');

    // Nenhum lixo deixado para o segundo dono.
    assert.equal((await adminDb.doc(`users/${uidB}`).get()).exists, false);
    assert.equal((await adminDb.doc(`userPrivate/${uidB}`).get()).exists, false);
    const businesses = await adminDb.collection('businesses').get();
    assert.equal(businesses.size, 1);
  });

  it('rejeita CPF ja reivindicado por outro UID', async () => {
    await registerBusinessHandler(
      callableRequest<RegisterBusinessArgs>(args(), uidA),
      CPF_SECRET,
      CNPJ_SECRET,
    );

    const error = await captureError(
      registerBusinessHandler(
        callableRequest<RegisterBusinessArgs>(
          args({
            cnpj: '12.345.678/0001-95',
            idempotencyKey: 'k-register-biz-3',
          }),
          uidB,
        ),
        CPF_SECRET,
        CNPJ_SECRET,
      ),
    );
    assert.equal(error.code, 'already-exists');

    assert.equal((await adminDb.doc(`users/${uidB}`).get()).exists, false);
  });

  it('replay de idempotencia retorna a mesma businessId', async () => {
    const first = await registerBusinessHandler(
      callableRequest<RegisterBusinessArgs>(args(), uidA),
      CPF_SECRET,
      CNPJ_SECRET,
    );
    const second = await registerBusinessHandler(
      callableRequest<RegisterBusinessArgs>(args(), uidA),
      CPF_SECRET,
      CNPJ_SECRET,
    );

    assert.equal(second.businessId, first.businessId);

    const businesses = await adminDb.collection('businesses').get();
    assert.equal(businesses.size, 1);

    const cnpjClaims = await adminDb.collection('cnpjClaims').get();
    assert.equal(cnpjClaims.size, 1);
  });

  it('chave de idempotencia de outro usuario e rejeitada', async () => {
    await registerBusinessHandler(
      callableRequest<RegisterBusinessArgs>(args(), uidA),
      CPF_SECRET,
      CNPJ_SECRET,
    );

    const error = await captureError(
      registerBusinessHandler(
        callableRequest<RegisterBusinessArgs>(
          args({
            cpf: '987.654.321-00',
            cnpj: '12.345.678/0001-95',
          }),
          uidB,
        ),
        CPF_SECRET,
        CNPJ_SECRET,
      ),
    );
    assert.equal(error.code, 'permission-denied');
  });

  it('rejeita CNPJ invalido', async () => {
    const error = await captureError(
      registerBusinessHandler(
        callableRequest<RegisterBusinessArgs>(
          args({ cnpj: '11.222.333/0001-82' }),
          uidA,
        ),
        CPF_SECRET,
        CNPJ_SECRET,
      ),
    );
    assert.equal(error.code, 'invalid-argument');
  });

  it('rejeita CPF invalido', async () => {
    const error = await captureError(
      registerBusinessHandler(
        callableRequest<RegisterBusinessArgs>(
          args({ cpf: '123.456.789-00' }),
          uidA,
        ),
        CPF_SECRET,
        CNPJ_SECRET,
      ),
    );
    assert.equal(error.code, 'invalid-argument');
  });

  it('rejeita nome fantasia ausente', async () => {
    const error = await captureError(
      registerBusinessHandler(
        callableRequest<RegisterBusinessArgs>(
          args({ businessName: '  ' }),
          uidA,
        ),
        CPF_SECRET,
        CNPJ_SECRET,
      ),
    );
    assert.equal(error.code, 'invalid-argument');
  });

  it('aceita campos opcionais ausentes', async () => {
    const result = await registerBusinessHandler(
      callableRequest<RegisterBusinessArgs>(
        args({
          phone: null,
          businessLegalName: null,
          businessPhone: null,
          businessDescription: null,
          idempotencyKey: 'k-register-biz-opt',
        }),
        uidA,
      ),
      CPF_SECRET,
      CNPJ_SECRET,
    );

    const user = (await adminDb.doc(`users/${uidA}`).get()).data()!;
    assert.ok(!('telefone' in user));

    const business = (
      await adminDb.doc(`businesses/${result.businessId}`).get()
    ).data()!;
    assert.ok(!('razaoSocial' in business));
    assert.ok(!('telefone' in business));
    assert.ok(!('descricao' in business));
  });
});