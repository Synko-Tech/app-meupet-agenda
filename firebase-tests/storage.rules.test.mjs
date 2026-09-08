/**
 * Rules harness for storage.rules (Storage emulator).
 *
 * Multi-tenant model: establishment assets live under
 * `businesses/{businessId}/**` and access is decided by the Firestore
 * membership `businesses/{businessId}/members/{uid}`:
 *   - users/{userId}/**: read/write = the user themself (active profile).
 *   - businesses/{businessId}/**: read = staff; write = owner/admin.
 *   - writes (create/update): max 5MB, content-type image/jpeg|png|webp.
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
const BUCKET = `gs://${PROJECT_ID}.appspot.com`;
const RULES = readFileSync(new URL('../storage.rules', import.meta.url), 'utf8');

const FIVE_MB = 5 * 1024 * 1024;
const JPEG = { contentType: 'image/jpeg' };

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    storage: { host: '127.0.0.1', port: 9199, rules: RULES },
  });
});

beforeEach(async () => {
  await testEnv.clearStorage();
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv.cleanup();
});

async function seedFile(path, content = 'file content') {
  await testEnv.withSecurityRulesDisabled((ctx) =>
    ctx.storage(BUCKET).ref(path).putString(content),
  );
}

/** Seeds users/{uid} + membership and returns an authenticated context. */
async function withAuth(uid, businessId, role, { ativo = true, userAtivo = true } = {}) {
  await testEnv.withSecurityRulesDisabled((ctx) =>
    ctx.firestore().doc(`users/${uid}`).set({ role: 'client', ativo: userAtivo }),
  );
  if (businessId !== null) {
    await testEnv.withSecurityRulesDisabled((ctx) =>
      ctx
        .firestore()
        .doc(`businesses/${businessId}/members/${uid}`)
        .set({ role, ativo }),
    );
  }
  return testEnv.authenticatedContext(uid);
}

const BIZ_A = 'biz-a';
const BIZ_B = 'biz-b';
const CLIENT = 'alice';
const OTHER_CLIENT = 'bob';
const COLLABORATOR = 'carol';
const ADMIN = 'dave';
const OWNER = 'oscar';

describe('storage.rules: per-user paths', () => {
  it('user cannot read another user\u2019s file', async () => {
    const client = await withAuth(CLIENT, BIZ_A, 'client');
    await seedFile('users/bob/photo.jpg');

    await assertFails(
      client.storage(BUCKET).ref('users/bob/photo.jpg').getMetadata(),
    );
  });

  it('user cannot write to another user\u2019s path', async () => {
    const client = await withAuth(CLIENT, BIZ_A, 'client');

    await assertFails(
      client
        .storage(BUCKET)
        .ref('users/bob/photo.jpg')
        .putString('forged upload', undefined, JPEG),
    );
  });

  it('user can read own file', async () => {
    const client = await withAuth(CLIENT, BIZ_A, 'client');
    await seedFile('users/alice/photo.jpg');

    await assertSucceeds(
      client.storage(BUCKET).ref('users/alice/photo.jpg').getMetadata(),
    );
  });

  it('user can write own file', async () => {
    const client = await withAuth(CLIENT, BIZ_A, 'client');

    await assertSucceeds(
      client
        .storage(BUCKET)
        .ref('users/alice/photo.jpg')
        .putString('my photo', undefined, JPEG),
    );
  });

  it('user can delete own file', async () => {
    const client = await withAuth(CLIENT, BIZ_A, 'client');
    await seedFile('users/alice/photo.jpg');

    await assertSucceeds(
      client.storage(BUCKET).ref('users/alice/photo.jpg').delete(),
    );
  });

  it('staff cannot read another user\u2019s personal file (private paths)', async () => {
    const admin = await withAuth(ADMIN, BIZ_A, 'admin');
    await seedFile('users/bob/photo.jpg');

    await assertFails(
      admin.storage(BUCKET).ref('users/bob/photo.jpg').getMetadata(),
    );
  });

  it('oversized file upload to own path is rejected (5MB cap)', async () => {
    const client = await withAuth(CLIENT, BIZ_A, 'client');

    await assertFails(
      client
        .storage(BUCKET)
        .ref('users/alice/big.jpg')
        .putString('x'.repeat(FIVE_MB + 1), undefined, JPEG),
    );
  });

  it('upload of exactly 5MB to own path is rejected (strictly less than 5MB)', async () => {
    const client = await withAuth(CLIENT, BIZ_A, 'client');

    await assertFails(
      client
        .storage(BUCKET)
        .ref('users/alice/exact.jpg')
        .putString('x'.repeat(FIVE_MB), undefined, JPEG),
    );
  });

  it('upload just under 5MB to own path succeeds', async () => {
    const client = await withAuth(CLIENT, BIZ_A, 'client');

    await assertSucceeds(
      client
        .storage(BUCKET)
        .ref('users/alice/near-max.jpg')
        .putString('x'.repeat(FIVE_MB - 1), undefined, JPEG),
    );
  });

  it('PNG and WebP uploads to own path succeed', async () => {
    const client = await withAuth(CLIENT, BIZ_A, 'client');

    await assertSucceeds(
      client
        .storage(BUCKET)
        .ref('users/alice/photo.png')
        .putString('png', undefined, { contentType: 'image/png' }),
    );
    await assertSucceeds(
      client
        .storage(BUCKET)
        .ref('users/alice/photo.webp')
        .putString('webp', undefined, { contentType: 'image/webp' }),
    );
  });

  it('non-image content-type upload to own path is rejected', async () => {
    const client = await withAuth(CLIENT, BIZ_A, 'client');

    await assertFails(
      client
        .storage(BUCKET)
        .ref('users/alice/notes.txt')
        .putString('plain text', undefined, { contentType: 'text/plain' }),
    );
  });

  it('unknown paths outside users/ and businesses/ are denied', async () => {
    const client = await withAuth(CLIENT, BIZ_A, 'client');

    await assertFails(
      client
        .storage(BUCKET)
        .ref('outros/photo.jpg')
        .putString('forged', undefined, JPEG),
    );
  });
});

describe('storage.rules: business assets require membership', () => {
  it('admin can write business assets', async () => {
    const admin = await withAuth(ADMIN, BIZ_A, 'admin');

    await assertSucceeds(
      admin
        .storage(BUCKET)
        .ref(`businesses/${BIZ_A}/logo.png`)
        .putString('logo', undefined, JPEG),
    );
  });

  it('owner can write and delete business assets', async () => {
    const owner = await withAuth(OWNER, BIZ_A, 'owner');
    await seedFile(`businesses/${BIZ_A}/logo.png`);

    await assertSucceeds(
      owner
        .storage(BUCKET)
        .ref(`businesses/${BIZ_A}/banner.png`)
        .putString('banner', undefined, JPEG),
    );
    await assertSucceeds(
      owner.storage(BUCKET).ref(`businesses/${BIZ_A}/logo.png`).delete(),
    );
  });

  it('collaborator can read but not write business assets', async () => {
    const collaborator = await withAuth(COLLABORATOR, BIZ_A, 'collaborator');
    await seedFile(`businesses/${BIZ_A}/logo.png`);

    await assertSucceeds(
      collaborator
        .storage(BUCKET)
        .ref(`businesses/${BIZ_A}/logo.png`)
        .getMetadata(),
    );
    await assertFails(
      collaborator
        .storage(BUCKET)
        .ref(`businesses/${BIZ_A}/logo.png`)
        .putString('forged', undefined, JPEG),
    );
  });

  it('client cannot read or write business assets', async () => {
    const client = await withAuth(CLIENT, BIZ_A, 'client');
    await seedFile(`businesses/${BIZ_A}/logo.png`);

    await assertFails(
      client.storage(BUCKET).ref(`businesses/${BIZ_A}/logo.png`).getMetadata(),
    );
    await assertFails(
      client
        .storage(BUCKET)
        .ref(`businesses/${BIZ_A}/logo.png`)
        .putString('forged', undefined, JPEG),
    );
  });

  it('admin of business A cannot touch business B assets', async () => {
    const admin = await withAuth(ADMIN, BIZ_A, 'admin');
    await seedFile(`businesses/${BIZ_B}/logo.png`);

    await assertFails(
      admin.storage(BUCKET).ref(`businesses/${BIZ_B}/logo.png`).getMetadata(),
    );
    await assertFails(
      admin
        .storage(BUCKET)
        .ref(`businesses/${BIZ_B}/logo.png`)
        .putString('forged', undefined, JPEG),
    );
  });

  it('user without membership cannot touch business assets', async () => {
    const stranger = await withAuth('stranger', null, 'client');
    await seedFile(`businesses/${BIZ_A}/logo.png`);

    await assertFails(
      stranger
        .storage(BUCKET)
        .ref(`businesses/${BIZ_A}/logo.png`)
        .getMetadata(),
    );
  });
});

describe('storage.rules: inactive users lose access', () => {
  it('inactive user cannot read own file', async () => {
    const inactive = await withAuth(CLIENT, BIZ_A, 'client', { userAtivo: false });
    await seedFile('users/alice/photo.jpg');

    await assertFails(
      inactive.storage(BUCKET).ref('users/alice/photo.jpg').getMetadata(),
    );
  });

  it('inactive user cannot write own path', async () => {
    const inactive = await withAuth(CLIENT, BIZ_A, 'client', { userAtivo: false });

    await assertFails(
      inactive
        .storage(BUCKET)
        .ref('users/alice/photo.jpg')
        .putString('forged', undefined, JPEG),
    );
  });

  it('inactive member cannot write business assets', async () => {
    const inactive = await withAuth(ADMIN, BIZ_A, 'admin', { ativo: false });

    await assertFails(
      inactive
        .storage(BUCKET)
        .ref(`businesses/${BIZ_A}/logo.png`)
        .putString('logo', undefined, JPEG),
    );
  });
});
