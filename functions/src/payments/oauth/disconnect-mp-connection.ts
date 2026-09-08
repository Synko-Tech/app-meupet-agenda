import { getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import type { CallableRequest } from 'firebase-functions/v2/https';

import { authUser, requireActiveProfile } from '../../auth/authorization';
import { requireBusinessMembership } from '../../businesses/business-authorization';
import { BUSINESS_ROLE } from '../../businesses/business-authorization';
import { requireDocId, requireText } from '../../shared/validation';
import { wrap } from '../../shared/errors';
import { deleteMerchantConnection } from '../merchant-connection-store';

export interface DisconnectMpConnectionArgs {
  businessId: string;
}

export interface DisconnectMpConnectionResult {
  disconnected: boolean;
}

/**
 * Disconnects the seller's Mercado Pago account. OWNER only. Deletes the
 * encrypted tokens and resets the public summary; future checkouts for this
 * business are blocked until a new connection is made.
 */
export async function disconnectMpConnectionHandler(
  request: CallableRequest<DisconnectMpConnectionArgs>,
): Promise<DisconnectMpConnectionResult> {
  const { uid } = authUser(request);
  const db = getFirestore();

  const args = (request.data ?? {}) as Partial<DisconnectMpConnectionArgs>;
  const businessId = requireDocId(args.businessId, 'businessId');

  await requireActiveProfile(db, uid);
  await requireBusinessMembership(db, uid, businessId, new Set([BUSINESS_ROLE.OWNER]));

  await deleteMerchantConnection(businessId);
  return { disconnected: true };
}

/** Public callable (registered via functions/src/index.ts). */
export const disconnectMpConnection = onCall(wrap(disconnectMpConnectionHandler));
