import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import type { DocumentReference, Transaction } from 'firebase-admin/firestore';

import { canTransition, SEMANTIC_TIMESTAMP_FIELD } from './payment-state-machine';

export type StatusTransitionResult = 'applied' | 'noop' | 'invalid';

/**
 * Shared single-transaction status transition step (Task 13 machine).
 * Applies the `to` transition to `payments/{id}` when allowed:
 *
 * - 'noop': payment is already in `to`; nothing written.
 * - 'invalid': the state machine rejects `current -> to`; nothing written.
 * - 'applied': status + statusChangedAt/statusChangedBy + statusHistory
 *   updated and the semantic timestamp (paidAt / canceledAt / refundedAt)
 *   stamped.
 *
 * `changedBy` names the actor; webhook flows pass 'mercadopago'.
 */
export function applyStatusTransition(
  transaction: Transaction,
  paymentRef: DocumentReference,
  payment: Record<string, unknown>,
  to: string,
  changedBy: string,
): StatusTransitionResult {
  const currentStatus = typeof payment.status === 'string' ? payment.status : '';

  if (currentStatus === to) {
    return 'noop';
  }
  if (!canTransition(currentStatus, to)) {
    return 'invalid';
  }

  const statusHistory = Array.isArray(payment.statusHistory)
    ? [...(payment.statusHistory as Array<Record<string, unknown>>)]
    : [];
  statusHistory.push({
    status: to,
    changedBy,
    changedAt: Timestamp.now(),
  });

  const update: Record<string, unknown> = {
    status: to,
    statusChangedAt: FieldValue.serverTimestamp(),
    statusChangedBy: changedBy,
    statusHistory,
  };
  const semanticField = SEMANTIC_TIMESTAMP_FIELD[to];
  if (semanticField !== undefined) {
    update[semanticField] = FieldValue.serverTimestamp();
  }
  transaction.update(paymentRef, update);

  return 'applied';
}