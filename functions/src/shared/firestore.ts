import { Firestore, Transaction } from 'firebase-admin/firestore';

/**
 * Runs `fn` inside a Firestore transaction, automatically retrying the
 * entire transaction on contention. Throws if the transaction fails after
 * the retry budget is exhausted.
 */
export function withTransaction<T>(
  db: Firestore,
  fn: (t: Transaction) => Promise<T>,
): Promise<T> {
  return db.runTransaction(fn);
}
