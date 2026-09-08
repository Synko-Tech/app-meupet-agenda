import { getFirestore } from 'firebase-admin/firestore';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import type { CallableRequest } from 'firebase-functions/v2/https';

import { authUser, requireActiveProfile } from '../auth/authorization';
import { requireBusinessMembership } from '../businesses/business-authorization';
import { apiError, wrap } from '../shared/errors';
import { withTransaction } from '../shared/firestore';
import { optionalIdempotencyKey, requireDocId, requireText } from '../shared/validation';

export interface PurchasePackageArgs {
  /** Business id (tenant) the purchase happens in. */
  businessId: string;
  /** Business package id from the catalog (`businesses/{id}/packages/{id}`). */
  packageId: string;
  /** Payment method; allowlist ['PIX', 'CARTAO', 'DINHEIRO'], default 'PIX'. */
  method?: string;
  idempotencyKey?: string;
}

export interface PurchasePackageResult {
  paymentId: string;
}

const STATUS_PENDENTE = 'PENDENTE';
const TIPO_PACOTE = 'PACOTE';
const ALLOWED_METHODS = new Set(['PIX', 'CARTAO', 'DINHEIRO']);

/**
 * Core handler. Creates a PENDENTE `payments` doc for a real catalog
 * package — a `customerPackages` doc is NEVER created here (that only
 * happens on activation, once payment is confirmed). All data on the
 * payment (valor, id_pacote, client identity) comes from the server:
 * the client only supplies the package id and an optional method.
 *
 * `id_pacote` on the payment links the business package; `id_pacote_cliente`
 * stays null until activation. Extra fields (id_pacote, statusHistory, ...)
 * are written with the Admin SDK, which bypasses security rules — the client
 * write allowlist in firestore.rules is unaffected.
 */
export async function purchasePackageHandler(
  request: CallableRequest<PurchasePackageArgs>,
): Promise<PurchasePackageResult> {
  const { uid } = authUser(request);
  const db = getFirestore();

  const args = (request.data ?? {}) as Partial<PurchasePackageArgs>;
  const businessId = requireDocId(args.businessId, 'businessId');
  const packageId = requireDocId(args.packageId, 'packageId');
  const method = requireMethod(args.method);
  const idempotencyKey = optionalIdempotencyKey(args.idempotencyKey);

  await requireActiveProfile(db, uid);
  await requireBusinessMembership(db, uid, businessId);

  const userSnap = await db.doc(`users/${uid}`).get();
  const userData = userSnap.data();
  const clientName =
    typeof userData?.nome === 'string' && userData.nome.trim() !== ''
      ? userData.nome
      : '';

  return withTransaction(db, async (transaction) => {
    if (idempotencyKey !== undefined) {
      const idempotencyRef = db.doc(`purchaseIdempotency/${idempotencyKey}`);
      const idempotencySnap = await transaction.get(idempotencyRef);
      if (idempotencySnap.exists) {
        const existing = idempotencySnap.data()!;
        if (existing.uid !== uid) {
          throw apiError(
            'permission-denied',
            'Chave de idempotência pertence a outro usuário.',
          );
        }
        const existingPaymentId =
          typeof existing.paymentId === 'string' ? existing.paymentId : '';
        if (existingPaymentId === '') {
          throw apiError('failed-precondition', 'Registro de idempotência inválido.');
        }
        return { paymentId: existingPaymentId };
      }
    }

    // All reads first (Firestore requires reads before writes in a
    // transaction), then every write.
    const packageRef = db.doc(`businesses/${businessId}/packages/${packageId}`);
    const packageSnap = await transaction.get(packageRef);
    if (!packageSnap.exists) {
      throw apiError('not-found', 'Pacote não encontrado.');
    }
    const pkg = packageSnap.data()!;
    if (pkg.ativo !== true) {
      throw apiError('failed-precondition', 'Pacote inativo.');
    }
    const value = requireCatalogValue(pkg);

    const paymentRef = db
      .collection(`businesses/${businessId}/payments`)
      .doc();
    const now = FieldValue.serverTimestamp();
    transaction.set(paymentRef, {
      businessId,
      id_cliente: uid,
      clientName,
      tipo: TIPO_PACOTE,
      id_pacote: packageId,
      id_pacote_cliente: null,
      id_agendamento: null,
      valor: value.valor,
      forma_pagamento: method,
      status: STATUS_PENDENTE,
      statusHistory: [
        { status: STATUS_PENDENTE, changedBy: uid, changedAt: Timestamp.now() },
      ],
      statusChangedAt: now,
      statusChangedBy: uid,
      createdAt: now,
    });

    if (idempotencyKey !== undefined) {
      transaction.set(db.doc(`purchaseIdempotency/${idempotencyKey}`), {
        uid,
        paymentId: paymentRef.id,
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    return { paymentId: paymentRef.id };
  });
}

/** Public callable (registered via functions/src/index.ts). */
export const purchasePackage = onCall(wrap(purchasePackageHandler));

/**
 * Validates the catalog package fields the flow depends on
 * (credits, price, validity) so a broken catalog entry can never
 * produce a payment or, later, a customer package with garbage values.
 * Shared with activate-package.
 */
export function requireCatalogValue(pkg: Record<string, unknown>): {
  creditos: number;
  valor: number;
  validadeDias: number;
} {
  const creditos =
    typeof pkg.quantidade_creditos === 'number' ? pkg.quantidade_creditos : NaN;
  const valor = typeof pkg.valor === 'number' ? pkg.valor : NaN;
  const validadeDias =
    typeof pkg.validade_dias === 'number' ? pkg.validade_dias : NaN;
  if (
    !Number.isInteger(creditos) ||
    creditos <= 0 ||
    !Number.isFinite(valor) ||
    valor <= 0 ||
    !Number.isInteger(validadeDias) ||
    validadeDias <= 0
  ) {
    throw apiError('failed-precondition', 'Pacote inválido.');
  }
  return { creditos, valor, validadeDias };
}

function requireMethod(value: unknown): string {
  if (value === undefined || value === null) {
    return 'PIX';
  }
  if (typeof value !== 'string') {
    throw apiError('invalid-argument', 'Campo method inválido.');
  }
  const normalized = value.trim().toUpperCase();
  if (!ALLOWED_METHODS.has(normalized)) {
    throw apiError('invalid-argument', 'Campo method inválido.');
  }
  return normalized;
}
