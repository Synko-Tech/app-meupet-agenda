/**
 * Rules harness for firestore.rules (Firestore emulator).
 *
 * Multi-tenant model: every domain collection lives under
 * `businesses/{businessId}/...`; roles come from the membership
 * `businesses/{businessId}/members/{uid}` (owner/admin/collaborator/client).
 * Internal backend collections are never client-visible.
 */
import { readFileSync } from 'node:fs';
import { describe, it, before, beforeEach, after } from 'node:test';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';

const PROJECT_ID = process.env.FIREBASE_TEST_PROJECT_ID ?? 'demo-meupet-agenda';
if (!PROJECT_ID.startsWith('demo-')) {
  throw new Error(
    `Suites de teste exigem um project id demo-* (use FIREBASE_TEST_PROJECT_ID). Recebido: ${PROJECT_ID}`,
  );
}
const RULES = readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8');

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { host: '127.0.0.1', port: 8080, rules: RULES },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv.cleanup();
});

async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(path).set(data);
  });
}

/** Seeds users/{uid} (global identity) + a business membership. */
async function withMembership(uid, businessId, role, { ativo = true, userAtivo = true } = {}) {
  await seed(`users/${uid}`, { role: 'client', ativo: userAtivo });
  await seed(`businesses/${businessId}/members/${uid}`, { role, ativo });
  return testEnv.authenticatedContext(uid);
}

/** Seeds users/{uid} with a global role (super admin only) and returns ctx. */
async function withGlobalRole(uid, role, ativo = true) {
  await seed(`users/${uid}`, { role, ativo });
  return testEnv.authenticatedContext(uid);
}

const BIZ_A = 'biz-a';
const BIZ_B = 'biz-b';
const OWNER_A = 'owner-a';
const OWNER_B = 'owner-b';
const ADMIN_A = 'admin-a';
const COLLAB_A = 'collab-a';
const CLIENT_A = 'alice';
const OTHER_CLIENT_A = 'bob';
const SUPER_ADMIN = 'erin';
const STRANGER = 'stranger';

describe('firestore.rules: financial data is private inside a business', () => {
  it('client cannot read another client\u2019s payment', async () => {
    const client = await withMembership(CLIENT_A, BIZ_A, 'client');
    await seed(`businesses/${BIZ_A}/payments/pay1`, {
      id_cliente: OTHER_CLIENT_A,
      status: 'PAGO',
    });

    await assertFails(
      client.firestore().doc(`businesses/${BIZ_A}/payments/pay1`).get(),
    );
  });

  it('client can read own payment', async () => {
    const client = await withMembership(CLIENT_A, BIZ_A, 'client');
    await seed(`businesses/${BIZ_A}/payments/pay1`, {
      id_cliente: CLIENT_A,
      status: 'PAGO',
    });

    await assertSucceeds(
      client.firestore().doc(`businesses/${BIZ_A}/payments/pay1`).get(),
    );
  });

  it('client cannot read another client\u2019s customerPackage', async () => {
    const client = await withMembership(CLIENT_A, BIZ_A, 'client');
    await seed(`businesses/${BIZ_A}/customerPackages/cp1`, {
      id_cliente: OTHER_CLIENT_A,
      status: 'ATIVO',
      credits: 5,
    });

    await assertFails(
      client.firestore().doc(`businesses/${BIZ_A}/customerPackages/cp1`).get(),
    );
  });

  it('client can read own customerPackage', async () => {
    const client = await withMembership(CLIENT_A, BIZ_A, 'client');
    await seed(`businesses/${BIZ_A}/customerPackages/cp1`, {
      id_cliente: CLIENT_A,
      status: 'ATIVO',
      credits: 5,
    });

    await assertSucceeds(
      client.firestore().doc(`businesses/${BIZ_A}/customerPackages/cp1`).get(),
    );
  });

  it('client cannot read another client\u2019s appointment', async () => {
    const client = await withMembership(CLIENT_A, BIZ_A, 'client');
    await seed(`businesses/${BIZ_A}/appointments/apt1`, {
      id_cliente: OTHER_CLIENT_A,
      id_colaborador: COLLAB_A,
      status: 'AGENDADO',
    });

    await assertFails(
      client.firestore().doc(`businesses/${BIZ_A}/appointments/apt1`).get(),
    );
  });

  it('client can read own appointment', async () => {
    const client = await withMembership(CLIENT_A, BIZ_A, 'client');
    await seed(`businesses/${BIZ_A}/appointments/apt1`, {
      id_cliente: CLIENT_A,
      id_colaborador: COLLAB_A,
      status: 'AGENDADO',
    });

    await assertSucceeds(
      client.firestore().doc(`businesses/${BIZ_A}/appointments/apt1`).get(),
    );
  });

  it('staff can read any payment of their business', async () => {
    const admin = await withMembership(ADMIN_A, BIZ_A, 'admin');
    await seed(`businesses/${BIZ_A}/payments/pay1`, {
      id_cliente: OTHER_CLIENT_A,
      status: 'PAGO',
    });

    await assertSucceeds(
      admin.firestore().doc(`businesses/${BIZ_A}/payments/pay1`).get(),
    );
  });
});

describe('firestore.rules: tenant isolation between businesses', () => {
  it('owner of business A cannot read business B payments', async () => {
    const ownerA = await withMembership(OWNER_A, BIZ_A, 'owner');
    await seed(`businesses/${BIZ_B}/payments/pay1`, {
      id_cliente: OWNER_B,
      status: 'PAGO',
    });

    await assertFails(
      ownerA.firestore().doc(`businesses/${BIZ_B}/payments/pay1`).get(),
    );
  });

  it('owner of business A cannot read business B members', async () => {
    const ownerA = await withMembership(OWNER_A, BIZ_A, 'owner');
    await seed(`businesses/${BIZ_B}/members/${OWNER_B}`, {
      role: 'owner',
      ativo: true,
    });

    await assertFails(
      ownerA.firestore().doc(`businesses/${BIZ_B}/members/${OWNER_B}`).get(),
    );
  });

  it('owner of business A cannot read business B catalog', async () => {
    const ownerA = await withMembership(OWNER_A, BIZ_A, 'owner');
    await seed(`businesses/${BIZ_B}/packages/pkg1`, { nome: 'P', ativo: true });

    await assertFails(
      ownerA.firestore().doc(`businesses/${BIZ_B}/packages/pkg1`).get(),
    );
  });

  it('user without membership cannot read business-scoped data', async () => {
    await seed(`users/${STRANGER}`, { role: 'client', ativo: true });
    const stranger = testEnv.authenticatedContext(STRANGER);
    await seed(`businesses/${BIZ_A}/payments/pay1`, {
      id_cliente: CLIENT_A,
      status: 'PAGO',
    });

    await assertFails(
      stranger.firestore().doc(`businesses/${BIZ_A}/payments/pay1`).get(),
    );
  });

  it('any signed-in user can read the public business document (discovery)', async () => {
    await seed(`users/${STRANGER}`, { role: 'client', ativo: true });
    const stranger = testEnv.authenticatedContext(STRANGER);
    await seed(`businesses/${BIZ_A}`, {
      nome: 'Pet Shop Central',
      status: 'ATIVO',
    });

    await assertSucceeds(
      stranger.firestore().doc(`businesses/${BIZ_A}`).get(),
    );
  });

  it('unauthenticated user cannot read the public business document', async () => {
    const anon = testEnv.unauthenticatedContext();
    await seed(`businesses/${BIZ_A}`, {
      nome: 'Pet Shop Central',
      status: 'ATIVO',
    });

    await assertFails(
      anon.firestore().doc(`businesses/${BIZ_A}`).get(),
    );
    await assertFails(anon.firestore().collection('businesses').get());
  });

  it('user with roles in both businesses gets each role per tenant', async () => {
    // OWNER_A is owner at biz-a and client at biz-b.
    await withMembership(OWNER_A, BIZ_A, 'owner');
    await withMembership(OWNER_A, BIZ_B, 'client');
    const ctx = testEnv.authenticatedContext(OWNER_A);
    await seed(`businesses/${BIZ_A}/payments/pay1`, { id_cliente: CLIENT_A });
    await seed(`businesses/${BIZ_B}/payments/pay2`, { id_cliente: CLIENT_A });

    // Staff permission at biz-a, but only client at biz-b.
    await assertSucceeds(
      ctx.firestore().doc(`businesses/${BIZ_A}/payments/pay1`).get(),
    );
    await assertFails(
      ctx.firestore().doc(`businesses/${BIZ_B}/payments/pay2`).get(),
    );
  });
});

describe('firestore.rules: business ownership and membership management', () => {
  it('owner can read and update own business configuration', async () => {
    const owner = await withMembership(OWNER_A, BIZ_A, 'owner');
    await seed(`businesses/${BIZ_A}`, {
      nome: 'Pet Shop A',
      timezone: 'America/Sao_Paulo',
      status: 'ATIVO',
      ownerId: OWNER_A,
    });

    await assertSucceeds(
      owner.firestore().doc(`businesses/${BIZ_A}`).get(),
    );
    await assertSucceeds(
      owner
        .firestore()
        .doc(`businesses/${BIZ_A}`)
        .update({ nome: 'Novo Nome', updatedAt: new Date() }),
    );
  });

  it('admin cannot update the business configuration (owner-only)', async () => {
    const admin = await withMembership(ADMIN_A, BIZ_A, 'admin');
    await seed(`businesses/${BIZ_A}`, {
      nome: 'Pet Shop A',
      timezone: 'America/Sao_Paulo',
      status: 'ATIVO',
      ownerId: OWNER_A,
    });

    await assertFails(
      admin.firestore().doc(`businesses/${BIZ_A}`).update({ nome: 'X' }),
    );
  });

  it('owner can manage members', async () => {
    const owner = await withMembership(OWNER_A, BIZ_A, 'owner');

    await assertSucceeds(
      owner
        .firestore()
        .doc(`businesses/${BIZ_A}/members/${CLIENT_A}`)
        .set({ role: 'collaborator', ativo: true }),
    );
  });

  it('owner cannot demote self (no single-owner loss)', async () => {
    const owner = await withMembership(OWNER_A, BIZ_A, 'owner');

    await assertFails(
      owner
        .firestore()
        .doc(`businesses/${BIZ_A}/members/${OWNER_A}`)
        .set({ role: 'client', ativo: true }),
    );
  });

  it('admin cannot manage members', async () => {
    const admin = await withMembership(ADMIN_A, BIZ_A, 'admin');

    await assertFails(
      admin
        .firestore()
        .doc(`businesses/${BIZ_A}/members/${CLIENT_A}`)
        .set({ role: 'client', ativo: true }),
    );
  });

  it('collaborator cannot write catalog; admin can', async () => {
    const collaborator = await withMembership(COLLAB_A, BIZ_A, 'collaborator');
    const admin = await withMembership(ADMIN_A, BIZ_A, 'admin');

    await assertFails(
      collaborator
        .firestore()
        .doc(`businesses/${BIZ_A}/services/svc1`)
        .set({ nome: 'Banho' }),
    );
    await assertSucceeds(
      admin
        .firestore()
        .doc(`businesses/${BIZ_A}/services/svc1`)
        .set({ nome: 'Banho' }),
    );
  });
});

describe('firestore.rules: financial backend collections are never client-visible', () => {
  it('owner cannot read or write merchantConnections (tokens private)', async () => {
    const owner = await withMembership(OWNER_A, BIZ_A, 'owner');

    await assertFails(
      owner.firestore().doc(`merchantConnections/${BIZ_A}`).get(),
    );
    await assertFails(
      owner
        .firestore()
        .doc(`merchantConnections/${BIZ_A}`)
        .set({ accessToken: 'x' }),
    );
  });

  it('super admin cannot read internal backend collections', async () => {
    const superAdmin = await withGlobalRole(SUPER_ADMIN, 'super_admin');

    for (const collection of [
      'merchantConnections',
      'oauthStates',
      'paymentRoutes',
      'businessIdempotency',
      'mpCheckoutIdempotency',
    ]) {
      await assertFails(
        superAdmin.firestore().doc(`${collection}/any`).get(),
      );
      await assertFails(
        superAdmin.firestore().doc(`${collection}/any`).set({ uid: SUPER_ADMIN }),
      );
    }
  });

  it('client can never write payments directly', async () => {
    const client = await withMembership(CLIENT_A, BIZ_A, 'client');

    await assertFails(
      client
        .firestore()
        .doc(`businesses/${BIZ_A}/payments/pay1`)
        .set({ id_cliente: CLIENT_A, valor: 100 }),
    );
  });

  it('owner cannot write payments directly (backend-only)', async () => {
    const owner = await withMembership(OWNER_A, BIZ_A, 'owner');

    await assertFails(
      owner
        .firestore()
        .doc(`businesses/${BIZ_A}/payments/pay1`)
        .set({ id_cliente: CLIENT_A, valor: 100 }),
    );
  });
});

describe('firestore.rules: query authorization (rules are not filters)', () => {
  it('client can query own payments but not all payments', async () => {
    const client = await withMembership(CLIENT_A, BIZ_A, 'client');
    await seed(`businesses/${BIZ_A}/payments/pay1`, {
      id_cliente: CLIENT_A,
      status: 'PAGO',
    });

    await assertSucceeds(
      client
        .firestore()
        .collection(`businesses/${BIZ_A}/payments`)
        .where('id_cliente', '==', CLIENT_A)
        .get(),
    );
    await assertFails(
      client.firestore().collection(`businesses/${BIZ_A}/payments`).get(),
    );
  });

  it('staff can query all payments of their business', async () => {
    const admin = await withMembership(ADMIN_A, BIZ_A, 'admin');
    await seed(`businesses/${BIZ_A}/payments/pay1`, {
      id_cliente: CLIENT_A,
      status: 'PAGO',
    });

    await assertSucceeds(
      admin.firestore().collection(`businesses/${BIZ_A}/payments`).get(),
    );
  });

  it('owner cannot query payments of another business', async () => {
    const ownerA = await withMembership(OWNER_A, BIZ_A, 'owner');
    await seed(`businesses/${BIZ_B}/payments/pay1`, {
      id_cliente: OWNER_B,
      status: 'PAGO',
    });

    await assertFails(
      ownerA.firestore().collection(`businesses/${BIZ_B}/payments`).get(),
    );
  });

  it('client cannot list members of the business', async () => {
    const client = await withMembership(CLIENT_A, BIZ_A, 'client');

    await assertFails(
      client.firestore().collection(`businesses/${BIZ_A}/members`).get(),
    );
  });
});

describe('firestore.rules: global identity', () => {
  it('user can read own profile and membership projection only', async () => {
    const client = await withMembership(CLIENT_A, BIZ_A, 'client');
    await seed(`users/${OTHER_CLIENT_A}`, { role: 'client', ativo: true });

    await assertSucceeds(
      client.firestore().doc(`users/${CLIENT_A}`).get(),
    );
    await assertFails(
      client.firestore().doc(`users/${OTHER_CLIENT_A}`).get(),
    );
    await assertSucceeds(
      client.firestore().doc(`users/${CLIENT_A}/businessMemberships/${BIZ_A}`).get(),
    );
  });

  it('client cannot list all users', async () => {
    const client = await withMembership(CLIENT_A, BIZ_A, 'client');

    await assertFails(client.firestore().collection('users').get());
  });

  it('super admin can list users', async () => {
    const superAdmin = await withGlobalRole(SUPER_ADMIN, 'super_admin');

    await assertSucceeds(superAdmin.firestore().collection('users').get());
  });

  it('user can edit own profile fields but never role', async () => {
    const client = await withMembership(CLIENT_A, BIZ_A, 'client');

    await assertSucceeds(
      client
        .firestore()
        .doc(`users/${CLIENT_A}`)
        .update({ nome: 'Alice Nova', updatedAt: new Date() }),
    );
    await assertFails(
      client
        .firestore()
        .doc(`users/${CLIENT_A}`)
        .update({ role: 'admin' }),
    );
  });

  it('temporary legacy registration: client can self-create own profile', async () => {
    const ctx = testEnv.authenticatedContext(CLIENT_A);
    const now = new Date();

    await assertSucceeds(
      ctx.firestore().doc(`users/${CLIENT_A}`).set({
        nome: 'Alice',
        email: 'alice@example.com',
        telefone: '11999999999',
        role: 'client',
        tipo_usuario: 'client',
        ativo: true,
        createdAt: now,
        updatedAt: now,
      }),
    );
  });
});

describe('firestore.rules: private CPF and address data (userPrivate)', () => {
  it('owner can read own userPrivate document', async () => {
    const client = await withMembership(CLIENT_A, BIZ_A, 'client');
    await seed(`userPrivate/${CLIENT_A}`, {
      cpfCanonical: '12345678909',
      address: { postalCode: '01310-100' },
    });

    await assertSucceeds(
      client.firestore().doc(`userPrivate/${CLIENT_A}`).get(),
    );
  });

  it('super admin can read a specific userPrivate document', async () => {
    const superAdmin = await withGlobalRole(SUPER_ADMIN, 'super_admin');
    await seed(`userPrivate/${CLIENT_A}`, {
      cpfCanonical: '12345678909',
      address: { postalCode: '01310-100' },
    });

    await assertSucceeds(
      superAdmin.firestore().doc(`userPrivate/${CLIENT_A}`).get(),
    );
  });

  it('regular admin and collaborator cannot read userPrivate', async () => {
    const admin = await withMembership(ADMIN_A, BIZ_A, 'admin');
    const collaborator = await withMembership(COLLAB_A, BIZ_A, 'collaborator');
    await seed(`userPrivate/${CLIENT_A}`, {
      cpfCanonical: '12345678909',
    });

    await assertFails(
      admin.firestore().doc(`userPrivate/${CLIENT_A}`).get(),
    );
    await assertFails(
      collaborator.firestore().doc(`userPrivate/${CLIENT_A}`).get(),
    );
  });

  it('stranger cannot read another user\u2019s userPrivate document', async () => {
    await seed(`users/${STRANGER}`, { role: 'client', ativo: true });
    const stranger = testEnv.authenticatedContext(STRANGER);
    await seed(`userPrivate/${CLIENT_A}`, {
      cpfCanonical: '12345678909',
    });

    await assertFails(
      stranger.firestore().doc(`userPrivate/${CLIENT_A}`).get(),
    );
  });

  it('unauthenticated user cannot read userPrivate', async () => {
    const anon = testEnv.unauthenticatedContext();
    await seed(`userPrivate/${CLIENT_A}`, {
      cpfCanonical: '12345678909',
    });

    await assertFails(
      anon.firestore().doc(`userPrivate/${CLIENT_A}`).get(),
    );
  });

  it('listing userPrivate is blocked for everyone (owner and super admin)', async () => {
    const client = await withMembership(CLIENT_A, BIZ_A, 'client');
    const superAdmin = await withGlobalRole(SUPER_ADMIN, 'super_admin');
    await seed(`userPrivate/${CLIENT_A}`, {
      cpfCanonical: '12345678909',
    });

    await assertFails(
      client.firestore().collection('userPrivate').get(),
    );
    await assertFails(
      superAdmin.firestore().collection('userPrivate').get(),
    );
  });

  it('no one can create, update or delete userPrivate (backend-only writes)', async () => {
    const client = await withMembership(CLIENT_A, BIZ_A, 'client');
    const superAdmin = await withGlobalRole(SUPER_ADMIN, 'super_admin');
    await seed(`userPrivate/${CLIENT_A}`, {
      cpfCanonical: '12345678909',
    });

    await assertFails(
      client.firestore().doc(`userPrivate/${CLIENT_A}`).set({
        cpfCanonical: '12345678909',
      }),
    );
    await assertFails(
      client
        .firestore()
        .doc(`userPrivate/${CLIENT_A}`)
        .update({ address: { postalCode: '01000-000' } }),
    );
    await assertFails(
      client.firestore().doc(`userPrivate/${CLIENT_A}`).delete(),
    );
    await assertFails(
      superAdmin.firestore().doc(`userPrivate/${CLIENT_A}`).set({
        cpfCanonical: '12345678909',
      }),
    );
  });
});

describe('firestore.rules: cpfClaims is never client-visible', () => {
  it('all access to cpfClaims is blocked for every role', async () => {
    const client = await withMembership(CLIENT_A, BIZ_A, 'client');
    const superAdmin = await withGlobalRole(SUPER_ADMIN, 'super_admin');
    await seed(`cpfClaims/claim-abc`, { uid: CLIENT_A });

    for (const ctx of [client, superAdmin]) {
      await assertFails(
        ctx.firestore().doc('cpfClaims/claim-abc').get(),
      );
      await assertFails(
        ctx.firestore().collection('cpfClaims').get(),
      );
      await assertFails(
        ctx.firestore().doc('cpfClaims/claim-abc').set({ uid: CLIENT_A }),
      );
      await assertFails(
        ctx.firestore().doc('cpfClaims/claim-abc').delete(),
      );
    }
  });
});

describe('firestore.rules: administrative user updates are field-scoped', () => {
  const now = new Date();

  it('super admin can change role/tipo_usuario/ativo/updatedAt', async () => {
    const superAdmin = await withGlobalRole(SUPER_ADMIN, 'super_admin');
    await seed(`users/${CLIENT_A}`, { role: 'client', ativo: true });

    await assertSucceeds(
      superAdmin
        .firestore()
        .doc(`users/${CLIENT_A}`)
        .update({
          role: 'admin',
          tipo_usuario: 'admin',
          ativo: true,
          updatedAt: now,
        }),
    );
  });

  it('super admin cannot change arbitrary fields in users', async () => {
    const superAdmin = await withGlobalRole(SUPER_ADMIN, 'super_admin');
    await seed(`users/${CLIENT_A}`, {
      role: 'client',
      ativo: true,
      nome: 'Alice',
    });

    await assertFails(
      superAdmin
        .firestore()
        .doc(`users/${CLIENT_A}`)
        .update({ nome: 'Alice Hackeada' }),
    );
    await assertFails(
      superAdmin
        .firestore()
        .doc(`users/${CLIENT_A}`)
        .update({ cpfCanonical: '12345678909' }),
    );
    await assertFails(
      superAdmin
        .firestore()
        .doc(`users/${CLIENT_A}`)
        .update({ address: { postalCode: '01000-000' } }),
    );
  });

  it('business admin cannot update users at all', async () => {
    const admin = await withMembership(ADMIN_A, BIZ_A, 'admin');
    await seed(`users/${CLIENT_A}`, { role: 'client', ativo: true });

    await assertFails(
      admin
        .firestore()
        .doc(`users/${CLIENT_A}`)
        .update({ ativo: false, updatedAt: now }),
    );
  });
});
