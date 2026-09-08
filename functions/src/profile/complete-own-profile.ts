import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { defineSecret } from 'firebase-functions/params';
import { onCall } from 'firebase-functions/v2/https';
import type { CallableRequest } from 'firebase-functions/v2/https';

import { authUser } from '../auth/authorization';
import { cpfClaimId } from './cpf-claim';
import { validateAddress, validateCpf } from './profile-validation';
import type { PostalAddressRecord } from './profile-validation';
import { apiError, wrap } from '../shared/errors';
import { withTransaction } from '../shared/firestore';
import { requireText } from '../shared/validation';

export interface CompleteOwnProfileArgs {
  name: string;
  phone?: string | null;
  cpf: string;
  address: {
    postalCode: string;
    street: string;
    number: string;
    complement?: string | null;
    neighborhood: string;
    city: string;
    state: string;
    country: 'BR';
  };
}

export interface CompleteOwnProfileResult {
  profileComplete: true;
  cpfMasked: string;
}

const SCHEMA_VERSION = 2;
const ROLE_CLIENT = 'client';

/**
 * Mascara o CPF mostrando apenas os 2 ultimos digitos
 * (`***.***.***-NN`), consistente com o campo `cpfLast2` gravado em
 * `userPrivate/{uid}`: os 9 primeiros digitos ficam ocultos.
 */
function maskCpf(cpf: string): string {
  return `***.***.***-${cpf.slice(-2)}`;
}

/**
 * Telefone opcional. Aceita qualquer formatacao (DDD + numero com ou sem
 * separadores), canonizado para 10 ou 11 digitos.
 */
function validatePhone(value: unknown): string | undefined {
  if (value === undefined || value === null || value === '') {
    return undefined;
  }
  if (typeof value !== 'string') {
    throw apiError('invalid-argument', 'Telefone invalido.');
  }
  const digits = value.replace(/\D/g, '');
  if (digits.length !== 10 && digits.length !== 11) {
    throw apiError('invalid-argument', 'Telefone invalido.');
  }
  return digits;
}

/**
 * Conclui o perfil privado do usuario autenticado (nome, telefone, CPF e
 * endereco) de forma transacional:
 *
 * - `users/{uid}`: upsert preservando role/ativo de perfis existentes
 *   (perfil novo vira `client` + `ativo: true`), gravando
 *   `profileComplete: true` e `schemaVersion: 2`, com email vindo do
 *   Firebase Auth (fonte autoritativa).
 * - `userPrivate/{uid}`: CPF canonico, `cpfLast2` e endereco estruturado.
 * - `cpfClaims/{claimId}` (HMAC-SHA256 do CPF): unicidade do CPF entre
 *   UIDs. Uma claim de outro UID rejeita a chamada com `already-exists`; a
 *   troca de CPF apos a conclusao rejeita com `failed-precondition`.
 *
 * Retorna apenas o CPF mascarado — o valor completo nunca sai do handler.
 */
export async function completeOwnProfileHandler(
  request: CallableRequest<CompleteOwnProfileArgs>,
  cpfHmacSecret: string,
): Promise<CompleteOwnProfileResult> {
  const { uid } = authUser(request);
  const db = getFirestore();

  const email = (await getAuth().getUser(uid)).email ?? '';

  const args = (request.data ?? {}) as Partial<CompleteOwnProfileArgs>;
  const name = requireText(args.name, 'nome');
  const phone = validatePhone(args.phone);
  const cpf = validateCpf(args.cpf);
  const address: PostalAddressRecord = validateAddress(args.address);
  const claimId = cpfClaimId(cpf, cpfHmacSecret);

  const cpfMasked = await withTransaction(db, async (transaction) => {
    const userRef = db.doc(`users/${uid}`);
    const privateRef = db.doc(`userPrivate/${uid}`);
    const claimRef = db.doc(`cpfClaims/${claimId}`);

    const [userSnap, privateSnap, claimSnap] = await Promise.all([
      transaction.get(userRef),
      transaction.get(privateRef),
      transaction.get(claimRef),
    ]);

    if (claimSnap.exists) {
      const claimUid = claimSnap.data()?.uid;
      if (typeof claimUid === 'string' && claimUid !== uid) {
        throw apiError(
          'already-exists',
          'CPF ja cadastrado para outro usuario.',
        );
      }
    }

    const existingPrivate = privateSnap.data();
    const existingCpf =
      typeof existingPrivate?.cpf === 'string' ? existingPrivate.cpf : null;
    if (existingCpf !== null && existingCpf !== cpf) {
      throw apiError('failed-precondition', 'CPF nao pode ser alterado.');
    }

    const now = FieldValue.serverTimestamp();
    const existingUser = userSnap.data();
    const role =
      typeof existingUser?.role === 'string'
        ? existingUser.role
        : typeof existingUser?.tipo_usuario === 'string'
          ? existingUser.tipo_usuario
          : ROLE_CLIENT;
    const ativo =
      typeof existingUser?.ativo === 'boolean' ? existingUser.ativo : true;

    transaction.set(
      userRef,
      {
        nome: name,
        ...(email === '' ? {} : { email }),
        ...(phone === undefined ? {} : { telefone: phone }),
        role,
        tipo_usuario: role,
        ativo,
        profileComplete: true,
        schemaVersion: SCHEMA_VERSION,
        ...(userSnap.exists ? {} : { createdAt: now }),
        updatedAt: now,
      },
      { merge: true },
    );

    transaction.set(
      privateRef,
      {
        cpf,
        cpfLast2: cpf.slice(-2),
        address,
        ...(privateSnap.exists ? {} : { createdAt: now }),
        updatedAt: now,
      },
      { merge: true },
    );

    if (!claimSnap.exists) {
      transaction.set(claimRef, {
        uid,
        cpfLast2: cpf.slice(-2),
        createdAt: now,
      });
    }

    return maskCpf(cpf);
  });

  return { profileComplete: true, cpfMasked };
}

const CPF_HMAC_SECRET = defineSecret('CPF_HMAC_SECRET');

/** Public callable (registered via functions/src/index.ts). */
export const completeOwnProfile = onCall(
  { secrets: [CPF_HMAC_SECRET] },
  wrap<CompleteOwnProfileArgs, CompleteOwnProfileResult>((request) =>
    completeOwnProfileHandler(request, CPF_HMAC_SECRET.value())),
);
