import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import type { CallableRequest } from 'firebase-functions/v2/https';

import { authUser, requireActiveProfile } from '../auth/authorization';
import { apiError, wrap } from '../shared/errors';
import { withTransaction } from '../shared/firestore';
import { optionalIdempotencyKey, requireText } from '../shared/validation';

export interface CreateBusinessArgs {
  name: string;
  description?: string;
  timezone?: string;
  idempotencyKey?: string;
}

export interface CreateBusinessResult {
  businessId: string;
}

const DEFAULT_TIMEZONE = 'America/Sao_Paulo';

const SUPPORTED_TIMEZONES: ReadonlySet<string> = new Set([
  'America/Sao_Paulo',
  'America/Manaus',
  'America/Cuiaba',
  'America/Recife',
  'America/Belem',
  'America/Bahia',
  'America/Porto_Velho',
  'America/Boa_Vista',
  'America/Noronha',
  'America/Rio_Branco',
]);

/**
 * Core handler. Creates a `businesses/{businessId}` document and the owner
 * membership (`businesses/{businessId}/members/{uid}`) in the SAME
 * transaction, plus the denormalized projection
 * `users/{uid}/businessMemberships/{businessId}` so the app can list the
 * user's businesses without cross-tenant queries.
 *
 * Idempotency: `businessIdempotency/{key}` records the created businessId;
 * a replay returns it verbatim. The business name is not part of the
 * idempotency record, so a repeated gesture cannot fork two businesses.
 */
export async function createBusinessHandler(
  request: CallableRequest<CreateBusinessArgs>,
): Promise<CreateBusinessResult> {
  const { uid } = authUser(request);
  const db = getFirestore();

  const args = (request.data ?? {}) as Partial<CreateBusinessArgs>;
  const name = requireText(args.name, 'name');
  const idempotencyKey = optionalIdempotencyKey(args.idempotencyKey);

  const description =
    typeof args.description === 'string' && args.description.trim() !== ''
      ? args.description.trim().slice(0, 500)
      : undefined;
  const timezone =
    typeof args.timezone === 'string' && args.timezone.trim() !== ''
      ? args.timezone.trim()
      : DEFAULT_TIMEZONE;
  if (!SUPPORTED_TIMEZONES.has(timezone)) {
    throw apiError('invalid-argument', 'Timezone nao suportado.');
  }

  await requireActiveProfile(db, uid);

  let businessId = '';
  const replay = await withTransaction(db, async (transaction) => {
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
          return storedBusinessId;
        }
      }
    }

    const businessRef = db.collection('businesses').doc();
    const now = FieldValue.serverTimestamp();
    transaction.set(businessRef, {
      nome: name,
      ...(description === undefined ? {} : { descricao: description }),
      timezone,
      status: 'ATIVO',
      ownerId: uid,
      createdAt: now,
      updatedAt: now,
    });
    transaction.set(businessRef.collection('members').doc(uid), {
      role: 'owner',
      ativo: true,
      createdAt: Timestamp.now(),
    });
    transaction.set(
      db.doc(`users/${uid}/businessMemberships/${businessRef.id}`),
      {
        businessId: businessRef.id,
        businessName: name,
        role: 'owner',
        ativo: true,
        createdAt: Timestamp.now(),
      },
    );

    businessId = businessRef.id;

    if (idempotencyKey !== undefined) {
      transaction.set(db.doc(`businessIdempotency/${idempotencyKey}`), {
        uid,
        businessId,
        createdAt: now,
      });
    }
    return undefined;
  });

  if (replay !== undefined) {
    return { businessId: replay };
  }
  return { businessId };
}

/** Public callable (registered via functions/src/index.ts). */
export const createBusiness = onCall(wrap(createBusinessHandler));
