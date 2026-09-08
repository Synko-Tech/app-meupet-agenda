import { Firestore } from 'firebase-admin/firestore';

import { apiError } from '../shared/errors';

export interface BusinessMembershipRecord {
  businessId: string;
  role: string;
  ativo: boolean;
}

export const BUSINESS_ROLE = {
  OWNER: 'owner',
  ADMIN: 'admin',
  COLLABORATOR: 'collaborator',
  CLIENT: 'client',
} as const;

/** Every known business role; used to validate membership writes. */
export const ALL_BUSINESS_ROLES: ReadonlySet<string> = new Set(
  Object.values(BUSINESS_ROLE),
);

/**
 * Reads `businesses/{businessId}/members/{uid}`. Returns null when the user
 * has no membership (or the doc is missing). The membership is the canonical
 * tenant boundary: every tenant-scoped operation must check it.
 */
export async function getBusinessMembership(
  db: Firestore,
  uid: string,
  businessId: string,
): Promise<BusinessMembershipRecord | null> {
  const snapshot = await db.doc(
    `businesses/${businessId}/members/${uid}`,
  ).get();
  if (!snapshot.exists) {
    return null;
  }
  const data = snapshot.data();
  if (data === undefined) {
    return null;
  }
  return {
    businessId,
    role: typeof data.role === 'string' ? data.role : BUSINESS_ROLE.CLIENT,
    ativo: data.ativo === true,
  };
}

/**
 * Requires the caller to be an ACTIVE member of `businessId` with one of the
 * given roles (any role when `roles` is omitted). Throws `permission-denied`
 * otherwise. This is the server-side twin of the Firestore rules membership
 * check — the Admin SDK bypasses rules, so every callable must re-check.
 */
export async function requireBusinessMembership(
  db: Firestore,
  uid: string,
  businessId: string,
  roles?: ReadonlySet<string>,
): Promise<BusinessMembershipRecord> {
  const membership = await getBusinessMembership(db, uid, businessId);
  if (membership === null || !membership.ativo) {
    throw apiError(
      'permission-denied',
      'Voce nao faz parte desta loja ou esta inativo.',
    );
  }
  if (roles !== undefined && !roles.has(membership.role)) {
    throw apiError(
      'permission-denied',
      'Voce nao tem permissao para esta acao nesta loja.',
    );
  }
  return membership;
}

/** True when the role is owner or admin (business management tier). */
export function isBusinessManager(role: string): boolean {
  return role === BUSINESS_ROLE.OWNER || role === BUSINESS_ROLE.ADMIN;
}

/** True when the role belongs to the establishment staff. */
export function isBusinessStaff(role: string): boolean {
  return (
    role === BUSINESS_ROLE.OWNER ||
    role === BUSINESS_ROLE.ADMIN ||
    role === BUSINESS_ROLE.COLLABORATOR
  );
}
