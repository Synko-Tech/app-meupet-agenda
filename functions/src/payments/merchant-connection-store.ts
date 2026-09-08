import { getFirestore, Transaction } from 'firebase-admin/firestore';

import { decryptSecret, encryptSecret } from '../security/token-encryption';

/**
 * Store for seller OAuth credentials, private to the backend.
 *
 * Tokens live in `merchantConnections/{businessId}` — a collection the
 * client SDK can never read (firestore.rules denies it). Access tokens are
 * encrypted at rest; only a masked summary is exposed to the owner through
 * the business public doc (written by the OAuth handlers).
 */

export interface MerchantConnection {
  businessId: string;
  /** Mercado Pago seller/collector id. */
  collectorId: string;
  /** Plaintext access token (only in memory; encrypted at rest). */
  accessToken: string;
  /** Plaintext refresh token (only in memory; encrypted at rest). */
  refreshToken: string;
  publicKey: string;
  liveMode: boolean;
  /** Epoch millis when the access token expires. */
  expiresAt: number;
  connectedAt: number;
  updatedAt: number;
}

export interface MerchantConnectionSummary {
  status: 'CONECTADO' | 'DESCONECTADO';
  collectorId?: string;
  liveMode?: boolean;
  connectedAt?: number;
  expiresAt?: number;
}

const ENCRYPTED_PREFIX = 'enc:v1:';

export async function readMerchantConnection(
  businessId: string,
): Promise<MerchantConnection | null> {
  const db = getFirestore();
  const snap = await db.doc(`merchantConnections/${businessId}`).get();
  if (!snap.exists) {
    return null;
  }
  const data = snap.data()!;
  const accessTokenEnc = typeof data.accessTokenEnc === 'string' ? data.accessTokenEnc : '';
  const refreshTokenEnc =
    typeof data.refreshTokenEnc === 'string' ? data.refreshTokenEnc : '';
  if (accessTokenEnc === '' || refreshTokenEnc === '') {
    return null;
  }
  return {
    businessId,
    collectorId: typeof data.collectorId === 'string' ? data.collectorId : '',
    accessToken: decryptSecret(stripPrefix(accessTokenEnc)),
    refreshToken: decryptSecret(stripPrefix(refreshTokenEnc)),
    publicKey: typeof data.publicKey === 'string' ? data.publicKey : '',
    liveMode: data.liveMode === true,
    expiresAt: typeof data.expiresAt === 'number' ? data.expiresAt : 0,
    connectedAt: typeof data.connectedAt === 'number' ? data.connectedAt : 0,
    updatedAt: typeof data.updatedAt === 'number' ? data.updatedAt : 0,
  };
}

/**
 * Finds a connection by the seller/collector id. The webhook receives the
 * seller `user_id` before it can resolve the businessId from the payment
 * route, so it needs a collector-first lookup to know which seller token to
 * use when querying the Mercado Pago API (multi-seller architecture).
 */
export async function findMerchantConnectionByCollector(
  collectorId: string,
): Promise<MerchantConnection | null> {
  if (collectorId === '') {
    return null;
  }
  const db = getFirestore();
  const snap = await db
    .collection('merchantConnections')
    .where('collectorId', '==', collectorId)
    .limit(1)
    .get();
  if (snap.empty) {
    return null;
  }
  return readMerchantConnection(snap.docs[0].id);
}

/** Persists (or replaces) the connection, always encrypted at rest. */
export async function writeMerchantConnection(
  connection: MerchantConnection,
): Promise<void> {
  const db = getFirestore();
  await db.doc(`merchantConnections/${connection.businessId}`).set({
    collectorId: connection.collectorId,
    accessTokenEnc: `${ENCRYPTED_PREFIX}${encryptSecret(connection.accessToken)}`,
    refreshTokenEnc: `${ENCRYPTED_PREFIX}${encryptSecret(connection.refreshToken)}`,
    publicKey: connection.publicKey,
    liveMode: connection.liveMode,
    expiresAt: connection.expiresAt,
    connectedAt: connection.connectedAt,
    updatedAt: connection.updatedAt,
  });
}

/** Transactional variant: same payload, written through a Firestore
 * transaction so the connection and the business summary can be updated
 * atomically (see refreshMpConnection). */
export function writeMerchantConnectionInTransaction(
  transaction: Transaction,
  connection: MerchantConnection,
): void {
  const db = getFirestore();
  transaction.set(
    db.doc(`merchantConnections/${connection.businessId}`),
    {
      collectorId: connection.collectorId,
      accessTokenEnc: `${ENCRYPTED_PREFIX}${encryptSecret(connection.accessToken)}`,
      refreshTokenEnc: `${ENCRYPTED_PREFIX}${encryptSecret(connection.refreshToken)}`,
      publicKey: connection.publicKey,
      liveMode: connection.liveMode,
      expiresAt: connection.expiresAt,
      connectedAt: connection.connectedAt,
      updatedAt: connection.updatedAt,
    },
  );
}

/** Deletes the connection (disconnect). Also clears the public summary. */
export async function deleteMerchantConnection(businessId: string): Promise<void> {
  const db = getFirestore();
  await db.doc(`merchantConnections/${businessId}`).delete();
  await db.doc(`businesses/${businessId}`).update({
    merchantSummary: {
      status: 'DESCONECTADO',
      updatedAt: Date.now(),
    },
  });
}

/** Publishes the safe summary on the business public doc (owner-visible). */
export async function publishMerchantSummary(
  businessId: string,
  summary: MerchantConnectionSummary,
): Promise<void> {
  const db = getFirestore();
  await db.doc(`businesses/${businessId}`).update({
    merchantSummary: summary,
  });
}

function stripPrefix(value: string): string {
  return value.startsWith(ENCRYPTED_PREFIX)
    ? value.slice(ENCRYPTED_PREFIX.length)
    : value;
}

/** True when the access token is missing or already expired. */
export function isConnectionExpired(connection: MerchantConnection): boolean {
  return (
    connection.accessToken === '' ||
    connection.refreshToken === '' ||
    connection.expiresAt <= Date.now()
  );
}
