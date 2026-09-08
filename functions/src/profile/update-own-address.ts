import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import type { CallableRequest } from 'firebase-functions/v2/https';

import { authUser, requireActiveProfile } from '../auth/authorization';
import { apiError, wrap } from '../shared/errors';
import { withTransaction } from '../shared/firestore';
import { validateAddress } from './profile-validation';
import type { PostalAddressRecord } from './profile-validation';

export interface UpdateOwnAddressArgs {
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

export interface UpdateOwnAddressResult {
  updated: true;
}

/**
 * Atualiza SOMENTE o endereco do perfil privado do usuario autenticado:
 *
 * - `userPrivate/{uid}/address` (validado e canonizado por
 *   `validateAddress`, sem tocar em CPF/cpfLast2).
 * - `userPrivate/{uid}/updatedAt` via server timestamp.
 *
 * Nunca escreve em `users/{uid}` (role/status intactos) e nunca recebe CPF
 * na payload. Exige perfil publico ativo (`requireActiveProfile`) e
 * documento privado existente (usuario que completou o cadastro).
 *
 * Resultado minimalista: `{ updated: true }` — a UI reflete o novo valor
 * pela propria stream do Firestore.
 */
export async function updateOwnAddressHandler(
  request: CallableRequest<UpdateOwnAddressArgs>,
): Promise<UpdateOwnAddressResult> {
  const { uid } = authUser(request);
  const db = getFirestore();

  await requireActiveProfile(db, uid);

  const args = (request.data ?? {}) as Partial<UpdateOwnAddressArgs>;
  const address: PostalAddressRecord = validateAddress(args.address);

  await withTransaction(db, async (transaction) => {
    const privateRef = db.doc(`userPrivate/${uid}`);
    const privateSnap = await transaction.get(privateRef);
    if (!privateSnap.exists) {
      throw apiError(
        'failed-precondition',
        'Perfil privado nao encontrado. Complete seu cadastro.',
      );
    }
    transaction.update(privateRef, {
      address,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return { updated: true };
}

/** Public callable (registered via functions/src/index.ts). */
export const updateOwnAddress = onCall(
  wrap<UpdateOwnAddressArgs, UpdateOwnAddressResult>(updateOwnAddressHandler),
);
