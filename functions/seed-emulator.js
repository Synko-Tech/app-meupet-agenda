/**
 * Seed script for the local emulator (integration/E2E tests).
 *
 * Runs against the Firebase Local Emulator Suite with the Admin SDK, which
 * BYPASSES security rules — exactly what a seeded environment needs:
 *
 *   firebase emulators:exec --project meupet-agenda-app \
 *     --only auth,firestore,storage,functions \
 *     "node functions/seed-emulator.js && <integration tests>"
 *
 * O projeto dos emuladores deve ser o MESMO do app (meupet-agenda-app): o
 * namespace do Auth Emulator e por projeto e os usuarios so sao encontrados
 * pelo app quando seed e emulador usam o mesmo id.
 *
 * Idempotent: re-running never duplicates users or documents.
 *
 * Guarda de seguranca: o seed so roda contra emuladores locais (o host do
 * Firestore/Auth emulator precisa ser loopback), nunca contra producao.
 */
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const PROJECT_ID = process.env.FIREBASE_TEST_PROJECT_ID ?? 'meupet-agenda-app';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';
for (const host of [
  process.env.FIRESTORE_EMULATOR_HOST,
  process.env.FIREBASE_AUTH_EMULATOR_HOST,
]) {
  if (!host.startsWith('127.0.0.1:') && !host.startsWith('localhost:')) {
    throw new Error(
      `Seed exige emuladores locais, nao ${host} ` +
        '(configure FIRESTORE_EMULATOR_HOST/FIREBASE_AUTH_EMULATOR_HOST)',
    );
  }
}

async function main() {
  // initializeApp sem credenciais funciona no emulador (sem verificar
  // projeto real). projectId explicito aponta para o emulador.
  const app = initializeApp({ projectId: PROJECT_ID });
  const auth = getAuth(app);
  const db = getFirestore(app);

  async function upsertUser(uid, email, password, profile) {
    try {
      await auth.updateUser(uid, { email, password, emailVerified: true });
    } catch {
      await auth.createUser({ uid, email, password, emailVerified: true });
    }
    await db.doc(`users/${uid}`).set(
      {
        nome: profile.nome,
        email,
        telefone: profile.telefone ?? '11999999999',
        role: profile.role,
        tipo_usuario: profile.role,
        ativo: true,
        // Perfis semeados sao conhecidos e completos: o gate de perfil
        // (CompleteProfileScreen) nao deve bloquear alice/admin1 no E2E.
        profileComplete: true,
        schemaVersion: 2,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    console.log(`seeded user ${uid} (${profile.role})`);
  }

  await upsertUser('alice', 'alice@exemplo.com', 'senha-forte-123', {
    nome: 'Alice Silva',
    role: 'client',
  });
  await upsertUser('admin1', 'admin@exemplo.com', 'senha-forte-admin', {
    nome: 'Admin Um',
    role: 'super_admin',
  });

  // Loja (tenant) + memberships: o app so acessa o shell com uma loja ativa.
  await db.doc('businesses/biz1').set({
    nome: 'Pet Shop Teste',
    descricao: 'Loja semeadora para testes',
    timezone: 'America/Sao_Paulo',
    status: 'ATIVO',
    id_dono: 'admin1',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await db.doc('businesses/biz1/members/admin1').set({
    uid: 'admin1',
    role: 'owner',
    ativo: true,
    createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await db.doc('businesses/biz1/members/alice').set({
    uid: 'alice',
    role: 'client',
    ativo: true,
    createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await db.doc('users/alice/businessMemberships/biz1').set({
    businessId: 'biz1',
    businessName: 'Pet Shop Teste',
    role: 'client',
    ativo: true,
    createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await db.doc('users/admin1/businessMemberships/biz1').set({
    businessId: 'biz1',
    businessName: 'Pet Shop Teste',
    role: 'owner',
    ativo: true,
    createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  console.log('seeded business biz1');

  await db.doc('businesses/biz1/services/svc60').set({
    nome: 'Banho',
    descricao: 'Banho completo',
    duracao_minutos: 60,
    valor: 60,
    ativo: true,
    createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  console.log('seeded service svc60');

  await db.doc('businesses/biz1/packages/bp1').set({
    nome: 'Pacote Banho 5x',
    id_servico: 'svc60',
    serviceName: 'Banho',
    quantidade_creditos: 5,
    valor: 250,
    validade_dias: 30,
    ativo: true,
    createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  console.log('seeded package bp1');

  await deleteApp(app);
  console.log('seed complete');
}

main().catch((error) => {
  console.error('seed failed:', error);
  process.exit(1);
});
