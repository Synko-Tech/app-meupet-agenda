import { getFirestore } from 'firebase-admin/firestore';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import type { DocumentReference, Transaction } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import type { CallableRequest } from 'firebase-functions/v2/https';

import { authUser, requireActiveProfile } from '../auth/authorization';
import { apiError, wrap } from '../shared/errors';
import { withTransaction } from '../shared/firestore';
import { optionalIdempotencyKey, requireDocId, requireText } from '../shared/validation';
import { requireCatalogValue } from './purchase-package';

export interface ActivatePackageArgs {
  /** Business id (tenant) the payment lives in. */
  businessId: string;
  paymentId: string;
  idempotencyKey?: string;
}

export interface ActivatePackageResult {
  customerPackageId: string;
}

const STATUS_PENDENTE = 'PENDENTE';
const STATUS_EM_ANALISE = 'EM_ANALISE';
const STATUS_PAGO = 'PAGO';
const STATUS_ATIVO = 'ATIVO';
const SUPER_ADMIN_ROLE = 'super_admin';

/**
 * Core handler. SUPER_ADMIN only. Confirms a package payment and creates the
 * customerPackage doc in one atomic transaction (see
 * activatePackageInTransaction for the shared step). Delegates the
 * transaction to activatePackageCore so the Mercado Pago webhook can reuse
 * the exact same activation logic with `changedBy: 'mercadopago'`.
 */
export async function activatePackageHandler(
  request: CallableRequest<ActivatePackageArgs>,
): Promise<ActivatePackageResult> {
  const { uid } = authUser(request);
  const db = getFirestore();

  const args = (request.data ?? {}) as Partial<ActivatePackageArgs>;
  const businessId = requireDocId(args.businessId, 'businessId');
  const paymentId = requireText(args.paymentId, 'paymentId');
  const idempotencyKey = optionalIdempotencyKey(args.idempotencyKey);

  const profile = await requireActiveProfile(db, uid);
  if (profile.role !== SUPER_ADMIN_ROLE) {
    throw apiError('permission-denied', 'Apenas administradores podem ativar pacotes.');
  }

  return activatePackageCore(db, {
    businessId,
    paymentId,
    changedBy: uid,
    idempotencyKey,
  });
}

/**
 * Shared activation core (callable or webhook). Runs the activatePackage
 * idempotency protocol (`activateIdempotency/{key}`) and delegates the
 * single-transaction activation to activatePackageInTransaction.
 *
 * Idempotent: activating an already-activated PAGO payment is a no-op that
 * returns the stored customerPackageId without creating a duplicate.
 */
export async function activatePackageCore(
  db: import('firebase-admin/firestore').Firestore,
  args: {
    businessId: string;
    paymentId: string;
    changedBy: string;
    idempotencyKey?: string;
  },
): Promise<ActivatePackageResult> {
  const { businessId, paymentId, changedBy, idempotencyKey } = args;

  return withTransaction(db, async (transaction) => {
    if (idempotencyKey !== undefined) {
      const idempotencyRef = db.doc(`activateIdempotency/${idempotencyKey}`);
      const idempotencySnap = await transaction.get(idempotencyRef);
      if (idempotencySnap.exists) {
        const existing = idempotencySnap.data()!;
        if (existing.uid !== changedBy) {
          throw apiError(
            'permission-denied',
            'Chave de idempotência pertence a outro usuário.',
          );
        }
        const existingPackageId =
          typeof existing.customerPackageId === 'string'
            ? existing.customerPackageId
            : '';
        if (existingPackageId === '') {
          throw apiError('failed-precondition', 'Registro de idempotência inválido.');
        }
        return { customerPackageId: existingPackageId };
      }
    }

    // All reads first (Firestore requires reads before writes in a
    // transaction), then every write.
    const paymentRef = db.doc(`businesses/${businessId}/payments/${paymentId}`);
    const paymentSnap = await transaction.get(paymentRef);
    if (!paymentSnap.exists) {
      throw apiError('not-found', 'Pagamento não encontrado.');
    }
    const payment = paymentSnap.data()!;

    const customerPackageId = await activatePackageInTransaction(
      transaction,
      paymentRef,
      payment,
      changedBy,
    );
    if (customerPackageId === null) {
      // Already activated: idempotent no-op, never create a duplicate.
      const storedPackageId =
        typeof payment.id_pacote_cliente === 'string'
          ? payment.id_pacote_cliente
          : '';
      if (idempotencyKey !== undefined) {
        transaction.set(db.doc(`activateIdempotency/${idempotencyKey}`), {
          uid: changedBy,
          customerPackageId: storedPackageId,
          createdAt: FieldValue.serverTimestamp(),
        });
      }
      return { customerPackageId: storedPackageId };
    }

    if (idempotencyKey !== undefined) {
      transaction.set(db.doc(`activateIdempotency/${idempotencyKey}`), {
        uid: changedBy,
        customerPackageId,
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    return { customerPackageId };
  });
}

/**
 * Shared single-transaction activation step. Creates the customerPackages
 * doc from the linked business package (credits + validity are
 * server-authoritative) and back-fills `id_pacote_cliente` on the payment:
 *
 * - PENDENTE / EM_ANALISE (allowAnalysis): payment PENDENTE/EM_ANALISE ->
 *   PAGO with paidAt + history stamped, then activated.
 * - PAGO without id_pacote_cliente (admin-approved earlier): activated
 *   WITHOUT re-stamping the transition fields.
 * - PAGO with id_pacote_cliente: returns null (already activated).
 * - Anything else: failed-precondition.
 */
export async function activatePackageInTransaction(
  transaction: Transaction,
  paymentRef: DocumentReference,
  payment: Record<string, unknown>,
  changedBy: string,
  allowAnalysis = false,
): Promise<string | null> {
  const db = paymentRef.firestore;
  // paymentRef = businesses/{businessId}/payments/{paymentId}
  const businessId = paymentRef.parent.parent?.id ?? '';
  if (businessId === '') {
    throw apiError('internal', 'Pagamento fora de loja.');
  }
  const currentStatus = typeof payment.status === 'string' ? payment.status : '';

  if (currentStatus === STATUS_PAGO) {
    const storedPackageId =
      typeof payment.id_pacote_cliente === 'string'
        ? payment.id_pacote_cliente
        : '';
    if (storedPackageId !== '') {
      return null;
    }
    // PAGO without a customer package: fall through and activate without
    // re-stamping the transition fields.
  } else if (
    currentStatus !== STATUS_PENDENTE &&
    !(currentStatus === STATUS_EM_ANALISE && allowAnalysis)
  ) {
    throw apiError('failed-precondition', 'Pagamento não pode ser ativado.');
  }

  const packageId = typeof payment.id_pacote === 'string' ? payment.id_pacote : '';
  if (packageId === '') {
    throw apiError('failed-precondition', 'Pagamento sem pacote vinculado.');
  }

  const packageSnap = await transaction.get(db.doc(`businesses/${businessId}/packages/${packageId}`));
  if (!packageSnap.exists) {
    throw apiError('not-found', 'Pacote não encontrado.');
  }
  const pkg = packageSnap.data()!;
  const catalog = requireCatalogValue(pkg);

  const clientId =
    typeof payment.id_cliente === 'string' ? payment.id_cliente : '';
  const clientName =
    typeof payment.clientName === 'string' ? payment.clientName : '';
  const serviceId = typeof pkg.id_servico === 'string' ? pkg.id_servico : '';
  const serviceName =
    typeof pkg.serviceName === 'string' ? pkg.serviceName : '';
  const packageName = typeof pkg.nome === 'string' ? pkg.nome : '';

  const customerPackageRef = db
      .collection(`businesses/${businessId}/customerPackages`)
      .doc();
  const nowMillis = Date.now();
  transaction.set(customerPackageRef, {
    id_cliente: clientId,
    clientName,
    id_pacote: packageId,
    id_servico: serviceId,
    packageName,
    serviceName,
    creditos_totais: catalog.creditos,
    creditos_usados: 0,
    data_compra: Timestamp.fromMillis(nowMillis),
    data_validade: Timestamp.fromMillis(nowMillis + catalog.validadeDias * 86_400_000),
    status: STATUS_ATIVO,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  if (currentStatus === STATUS_PENDENTE || currentStatus === STATUS_EM_ANALISE) {
    const statusHistory = Array.isArray(payment.statusHistory)
      ? [...(payment.statusHistory as Array<Record<string, unknown>>)]
      : [];
    statusHistory.push({
      status: STATUS_PAGO,
      changedBy,
      changedAt: Timestamp.now(),
    });

    transaction.update(paymentRef, {
      status: STATUS_PAGO,
      id_pacote_cliente: customerPackageRef.id,
      paidAt: Timestamp.fromMillis(nowMillis),
      statusChangedAt: Timestamp.fromMillis(nowMillis),
      statusChangedBy: changedBy,
      statusHistory,
    });
  } else {
    transaction.update(paymentRef, {
      id_pacote_cliente: customerPackageRef.id,
    });
  }

  return customerPackageRef.id;
}

/** Public callable (registered via functions/src/index.ts). */
export const activatePackage = onCall(wrap(activatePackageHandler));