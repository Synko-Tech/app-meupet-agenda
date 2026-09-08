/**
 * Zerar completamente os emuladores Firebase locais: Firestore, Auth e Storage.
 *
 * Uso (somente contra emuladores locais):
 *   node scripts/wipe-emulator.js
 *
 * Guardas: recusa executar se os hosts apontarem para algo que nao seja
 * loopback, e apaga TUDO das tres emulacoes do projeto informado.
 */
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { getStorage } = require('firebase-admin/storage');

const PROJECT_ID = process.env.FIREBASE_TEST_PROJECT_ID ?? 'meupet-agenda-app';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';
process.env.STORAGE_EMULATOR_HOST ??= 'http://127.0.0.1:9199';

const hosts = [
  process.env.FIRESTORE_EMULATOR_HOST,
  process.env.FIREBASE_AUTH_EMULATOR_HOST,
  process.env.STORAGE_EMULATOR_HOST,
].join(' ');

for (const host of [
  process.env.FIRESTORE_EMULATOR_HOST,
  process.env.FIREBASE_AUTH_EMULATOR_HOST,
  process.env.STORAGE_EMULATOR_HOST,
]) {
  if (!host.includes('127.0.0.1') && !host.includes('localhost')) {
    throw new Error(
      `Recusa zerar um ambiente que nao seja loopback: ${host}`,
    );
  }
}
console.log('Alvos (loopback obrigatorio):', hosts);

async function wipeFirestore(db) {
  const collections = await db.listCollections();
  for (const collection of collections) {
    const deleted = await db.recursiveDelete(collection);
    console.log(`firestore: apagada colecao ${collection.id}`);
  }
  console.log(`firestore: ${collections.length} colecoes apagadas`);
}

async function wipeAuth(auth) {
  let page;
  do {
    page = await auth.listUsers(1000);
    if (page.users.length === 0) break;
    const result = await auth.deleteUsers(page.users.map((u) => u.uid));
    console.log(
      `auth: ${result.successCount} apagados, ${result.failureCount} falhas`,
    );
  } while (page.pageToken);
}

async function wipeStorage(storage) {
  const bucket = storage.bucket('meupet-agenda-app.firebasestorage.app');
  const [files] = await bucket.getFiles();
  let count = 0;
  for (const file of files) {
    await file.delete();
    count++;
  }
  console.log(`storage: ${count} objetos apagados`);
}

async function main() {
  const app = initializeApp({ projectId: PROJECT_ID });
  const db = getFirestore(app);
  const auth = getAuth(app);
  const storage = getStorage(app);

  await wipeFirestore(db);
  await wipeAuth(auth);
  await wipeStorage(storage);

  await deleteApp(app);
  console.log('wipe complete');
}

main().catch((error) => {
  console.error('wipe failed:', error);
  process.exit(1);
});
