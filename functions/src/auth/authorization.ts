import { Firestore } from 'firebase-admin/firestore';
// Type-only import: CallableContext lives in the v1 public surface; v2
// handlers pass CallableRequest (a structural superset of CallableContext),
// so `authUser(request)` works for v2 onCall handlers without casts.
import type { CallableContext } from 'firebase-functions/v1/https';

import { apiError } from '../shared/errors';

export interface AuthUser {
  uid: string;
}

/**
 * Resolves the authenticated caller. Throws `unauthenticated` when
 * `context.auth` is null (unauthenticated calls).
 */
export function authUser(context: CallableContext): AuthUser {
  if (context.auth === null || context.auth === undefined) {
    throw apiError('unauthenticated', 'Usuário não autenticado.');
  }
  return { uid: context.auth.uid };
}

export interface ProfileRecord {
  uid: string;
  role: string;
  ativo: boolean;
}

/**
 * Reads `users/{uid}` and returns the profile when the user exists and is
 * active. Throws `permission-denied` when the document is missing and
 * `failed-precondition` when the profile is inactive.
 */
export async function requireActiveProfile(
  db: Firestore,
  uid: string,
): Promise<ProfileRecord> {
  const snapshot = await db.doc(`users/${uid}`).get();
  if (!snapshot.exists) {
    throw apiError('permission-denied', 'Perfil não encontrado.');
  }

  const data = snapshot.data();
  if (data === undefined || data.ativo !== true) {
    throw apiError('failed-precondition', 'Perfil inativo.');
  }

  return {
    uid,
    role: typeof data.role === 'string' ? data.role : 'client',
    ativo: true,
  };
}
