import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { defineSecret } from 'firebase-functions/params';
import { onCall } from 'firebase-functions/v2/https';
import type { CallableRequest } from 'firebase-functions/v2/https';

import { authUser } from '../auth/authorization';
import { cnpjClaimId, validateCnpj, validatePhone } from './cnpj-validation';
import { cpfClaimId } from '../profile/cpf-claim';
import {
  validateAddress,
  validateCpf,
  type PostalAddressRecord,
} from '../profile/profile-validation';
import { apiError, wrap } from '../shared/errors';
import { withTransaction } from '../shared/firestore';
import { optionalIdempotencyKey, requireText } from '../shared/validation';

export interface RegisterBusinessArgs {
  name: string;
  phone?: string | null;
  cpf: string;
  cnpj: string;
  businessName: string;
  businessLegalName?: string | null;
  businessPhone?: string | null;
  businessDescription?: string | null;
  address: PostalAddressRecord;
  idempotencyKey?: string;
}

export interface RegisterBusinessResult {
  businessId: string;
  cnpjMasked: string;
}

const SCHEMA_VERSION = 2;
const ROLE_ADMIN = 'admin';
const ROLE_OWNER = 'owner';
const DEFAULT_TIMEZONE = 'America/Sao_Paulo';

/**
 * Mascara o CNPJ mostrando apenas os 2 ultimos digitos, consistente com
 * o campo `cnpjLast2` gravado em `businesses/{id}`: os 12 primeiros
 * digitos ficam ocultos.
 */
function maskCnpj(cnpj: string): string {
  return `**.***.***/****-${cnpj.slice(-2)}`;
}

/**
 * Cadastra um novo estabelecimento (pet shop) e seu dono na mesma
 * transacao:
 *
 * - `users/{uid}`: upsert preservando role/ativo de perfis existentes
 *   (perfil novo vira `admin` + `ativo: true`), gravando
 *   `profileComplete: true` e `schemaVersion: 2`.
 * - `userPrivate/{uid}`: CPF canonico do responsavel, `cpfLast2` e
 *   endereco do responsavel.
 * - `cpfClaims/{claimId}` (HMAC-SHA256 do CPF): unicidade do CPF entre
 *   UIDs.
 * - `businesses/{businessId}`: dados publicos da loja (nome fantasia,
 *   razao social, CNPJ, telefone, descricao, endereco e status ATIVO).
 * - `businesses/{businessId}/members/{uid}`: membership `owner`.
 * - `users/{uid}/businessMemberships/{businessId}`: projecao denormalizada
 *   para o app listar as lojas do usuario.
 * - `cnpjClaims/{claimId}` (HMAC-SHA256 do CNPJ): unicidade do CNPJ entre
 *   lojas.
 *
 * O usuario do Firebase Auth e criado pelo cliente (Flutter) ANTES desta
 * chamada; o handler assume `request.auth.uid` ja autenticado.
 */
export async function registerBusinessHandler(
  request: CallableRequest<RegisterBusinessArgs>,
  cpfHmacSecret: string,
  cnpjHmacSecret: string,
): Promise<RegisterBusinessResult> {
  const { uid } = authUser(request);
  const db = getFirestore();

  const email = (await getAuth().getUser(uid)).email ?? '';

  const args = (request.data ?? {}) as Partial<RegisterBusinessArgs>;
  const name = requireText(args.name, 'nome');
  const phone = validatePhone(args.phone);
  const cpf = validateCpf(args.cpf);
  const cnpj = validateCnpj(args.cnpj);
  const businessName = requireText(args.businessName, 'nome fantasia');
  const businessLegalName = optionalText(args.businessLegalName, 140);
  const businessPhone = validatePhone(args.businessPhone);
  const businessDescription = optionalText(args.businessDescription, 500);
  const address: PostalAddressRecord = validateAddress(args.address);
  const idempotencyKey = optionalIdempotencyKey(args.idempotencyKey);

  const cpfClaimIdValue = cpfClaimId(cpf, cpfHmacSecret);
  const cnpjClaimIdValue = cnpjClaimId(cnpj, cnpjHmacSecret);

  const result = await withTransaction(db, async (transaction) => {
    if (idempotencyKey !== undefined) {
      const idempotencyRef = db.doc(`businessIdempotency/${idempotencyKey}`);
      const idempotencySnap = await transaction.get(idempotencyRef);
      if (idempotencySnap.exists) {
        const existing = idempotencySnap.data()!;
        if (existing.uid !== uid) {
          throw apiError(
            'permission-denied',
            'Chave de idempotencia pertence a outro usuario.',
          );
        }
        const storedBusinessId =
          typeof existing.businessId === 'string'
            ? existing.businessId
            : '';
        if (storedBusinessId !== '') {
          return { businessId: storedBusinessId, cnpjMasked: maskCnpj(cnpj) };
        }
      }
    }

    const userRef = db.doc(`users/${uid}`);
    const privateRef = db.doc(`userPrivate/${uid}`);
    const cpfClaimRef = db.doc(`cpfClaims/${cpfClaimIdValue}`);
    const cnpjClaimRef = db.doc(`cnpjClaims/${cnpjClaimIdValue}`);

    const [userSnap, privateSnap, cpfClaimSnap, cnpjClaimSnap] =
      await Promise.all([
        transaction.get(userRef),
        transaction.get(privateRef),
        transaction.get(cpfClaimRef),
        transaction.get(cnpjClaimRef),
      ]);

    if (cpfClaimSnap.exists) {
      const claimUid = cpfClaimSnap.data()?.uid;
      if (typeof claimUid === 'string' && claimUid !== uid) {
        throw apiError(
          'already-exists',
          'CPF ja cadastrado para outro usuario.',
        );
      }
    }
    if (cnpjClaimSnap.exists) {
      throw apiError(
        'already-exists',
        'CNPJ ja cadastrado para outra loja.',
      );
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
          : ROLE_ADMIN;
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

    if (!cpfClaimSnap.exists) {
      transaction.set(cpfClaimRef, {
        uid,
        cpfLast2: cpf.slice(-2),
        createdAt: now,
      });
    }

    const businessRef = db.collection('businesses').doc();
    transaction.set(businessRef, {
      nome: businessName,
      ...(businessLegalName === undefined
        ? {}
        : { razaoSocial: businessLegalName }),
      cnpj,
      cnpjLast2: cnpj.slice(-2),
      ...(businessPhone === undefined ? {} : { telefone: businessPhone }),
      ...(businessDescription === undefined
        ? {}
        : { descricao: businessDescription }),
      endereco: address,
      timezone: DEFAULT_TIMEZONE,
      status: 'ATIVO',
      ownerId: uid,
      createdAt: now,
      updatedAt: now,
    });

    transaction.set(businessRef.collection('members').doc(uid), {
      role: ROLE_OWNER,
      ativo: true,
      createdAt: Timestamp.now(),
    });

    transaction.set(
      db.doc(`users/${uid}/businessMemberships/${businessRef.id}`),
      {
        businessId: businessRef.id,
        businessName,
        role: ROLE_OWNER,
        ativo: true,
        createdAt: Timestamp.now(),
      },
    );

    if (!cnpjClaimSnap.exists) {
      transaction.set(cnpjClaimRef, {
        uid,
        businessId: businessRef.id,
        cnpjLast2: cnpj.slice(-2),
        createdAt: now,
      });
    }

    if (idempotencyKey !== undefined) {
      transaction.set(db.doc(`businessIdempotency/${idempotencyKey}`), {
        uid,
        businessId: businessRef.id,
        createdAt: now,
      });
    }

    return {
      businessId: businessRef.id,
      cnpjMasked: maskCnpj(cnpj),
    };
  });

  return result;
}

/** Optional text field: trims, normalizes blank to undefined, caps length. */
function optionalText(value: unknown, maxLength: number): string | undefined {
  if (value === undefined || value === null || value === '') {
    return undefined;
  }
  if (typeof value !== 'string') {
    throw apiError('invalid-argument', 'Campo texto invalido.');
  }
  const trimmed = value.trim();
  if (trimmed === '') {
    return undefined;
  }
  return trimmed.slice(0, maxLength);
}

const CPF_HMAC_SECRET = defineSecret('CPF_HMAC_SECRET');
const CNPJ_HMAC_SECRET = defineSecret('CNPJ_HMAC_SECRET');

/** Public callable (registered via functions/src/index.ts). */
export const registerBusiness = onCall(
  { secrets: [CPF_HMAC_SECRET, CNPJ_HMAC_SECRET] },
  wrap<RegisterBusinessArgs, RegisterBusinessResult>((request) =>
    registerBusinessHandler(
      request,
      CPF_HMAC_SECRET.value(),
      CNPJ_HMAC_SECRET.value(),
    )),
);