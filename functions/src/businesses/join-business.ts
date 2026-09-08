import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import type { CallableRequest } from 'firebase-functions/v2/https';

import { authUser, requireActiveProfile } from '../auth/authorization';
import { apiError, wrap } from '../shared/errors';
import { withTransaction } from '../shared/firestore';
import { optionalIdempotencyKey, requireDocId } from '../shared/validation';

export interface JoinBusinessArgs {
  businessId: string;
  idempotencyKey?: string;
}

export interface JoinBusinessResult {
  businessId: string;
}

/**
 * Cliente entra em um pet shop ativo: cria a membership
 * `businesses/{businessId}/members/{uid}` (role `client`) e a projecao
 * denormalizada `users/{uid}/businessMemberships/{businessId}` na MESMA
 * transacao, permitindo ao app listar a loja e ativa-la como contexto.
 *
 * Idempotencia: uma membership existente (qualquer role) retorna sucesso sem
 * alterar nada — nunca rebaixa staff a `client`. A chave de idempotencia em
 * `businessJoinIdempotency/{key}` evita forkar lojas/registros em replay.
 */
export async function joinBusinessHandler(
  request: CallableRequest<JoinBusinessArgs>,
): Promise<JoinBusinessResult> {
  const { uid } = authUser(request);
  const db = getFirestore();

  const args = (request.data ?? {}) as Partial<JoinBusinessArgs>;
  const businessId = requireDocId(args.businessId, 'businessId');
  const idempotencyKey = optionalIdempotencyKey(args.idempotencyKey);

  await requireActiveProfile(db, uid);

  const result = await withTransaction(db, async (transaction) => {
    if (idempotencyKey !== undefined) {
      const idempotencyRef = db.doc(
        `businessJoinIdempotency/${idempotencyKey}`,
      );
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
          return { businessId: storedBusinessId };
        }
      }
    }

    const businessRef = db.doc(`businesses/${businessId}`);
    const businessSnap = await transaction.get(businessRef);
    if (!businessSnap.exists) {
      throw apiError('not-found', 'Pet shop nao encontrado.');
    }
    const businessData = businessSnap.data()!;
    if (businessData.status !== 'ATIVO') {
      throw apiError(
        'failed-precondition',
        'Este pet shop nao esta aceitando novos clientes no momento.',
      );
    }

    const businessName =
      typeof businessData.nome === 'string'
        ? businessData.nome
        : typeof businessData.name === 'string'
          ? businessData.name
          : '';

    const memberRef = businessRef.collection('members').doc(uid);
    const memberSnap = await transaction.get(memberRef);
    if (memberSnap.exists) {
      // Ja e membro (qualquer role): replay idempotente, sem rebaixar.
      return { businessId };
    }

    const now = FieldValue.serverTimestamp();
    transaction.set(memberRef, {
      role: 'client',
      ativo: true,
      createdAt: Timestamp.now(),
    });
    transaction.set(
      db.doc(`users/${uid}/businessMemberships/${businessId}`),
      {
        businessId,
        businessName,
        role: 'client',
        ativo: true,
        createdAt: now,
      },
    );

    if (idempotencyKey !== undefined) {
      transaction.set(db.doc(`businessJoinIdempotency/${idempotencyKey}`), {
        uid,
        businessId,
        createdAt: now,
      });
    }

    return { businessId };
  });

  return result;
}

/** Public callable (registered via functions/src/index.ts). */
export const joinBusiness = onCall(wrap(joinBusinessHandler));