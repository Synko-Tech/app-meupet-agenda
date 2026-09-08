import { getFirestore } from 'firebase-admin/firestore';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import type { CallableRequest } from 'firebase-functions/v2/https';

import { authUser, requireActiveProfile } from '../auth/authorization';
import { requireBusinessMembership } from '../businesses/business-authorization';
import { apiError, HttpsError, wrap } from '../shared/errors';
import { withTransaction } from '../shared/firestore';
import { optionalIdempotencyKey, requireDocId, requireText } from '../shared/validation';
import { requireCatalogValue } from '../packages/purchase-package';
import { isConnectionExpired, readMerchantConnection } from './merchant-connection-store';
import { createMpClient, getMpWebhookUrl } from './mercadopago-client';
import type { MpClient } from './mercadopago-client';

export interface CreateMercadoPagoCheckoutArgs {
  /** Business id (tenant) the checkout happens in. */
  businessId: string;
  packageId: string;
  idempotencyKey?: string;
}

export interface CreateMercadoPagoCheckoutResult {
  paymentId: string;
  preferenceId: string;
  initPoint: string;
}

const STATUS_PENDENTE = 'PENDENTE';
const STATUS_CANCELADO = 'CANCELADO';
const FORMA_MERCADO_PAGO = 'MERCADO_PAGO';
const TIPO_PACOTE = 'PACOTE';
const CANCEL_ACTOR = 'sistema';

/**
 * Core handler. Starts a Mercado Pago Checkout Pro flow for one catalog
 * package: creates a PENDENTE `payments` doc (server-authoritative price,
 * same shape as purchasePackage), asks Mercado Pago for a preference, and
 * pins the preference ids back on the payment. The webhook
 * (mercadoPagoWebhook) later finishes the payment and activates the package.
 *
 * Idempotency: `mpCheckoutIdempotency/{key}` records the pair
 * paymentId + preferenceId. A complete replay returns the stored result
 * verbatim; an incomplete one (payment was created, preference never
 * returned) reuses the payment and recreates the preference.
 *
 * When Mercado Pago cannot be reached, the payment is cancelled server-side
 * (gatewayStatus 'ERROR') and the call fails with `unavailable` so the app
 * can tell the user to retry (a new attempt starts a new payment).
 */
export async function createMercadoPagoCheckoutHandler(
  request: CallableRequest<CreateMercadoPagoCheckoutArgs>,
  mp?: MpClient,
): Promise<CreateMercadoPagoCheckoutResult> {
  const { uid } = authUser(request);
  const db = getFirestore();

  const args = (request.data ?? {}) as Partial<CreateMercadoPagoCheckoutArgs>;
  const businessId = requireDocId(args.businessId, 'businessId');
  const packageId = requireDocId(args.packageId, 'packageId');
  const idempotencyKey = optionalIdempotencyKey(args.idempotencyKey);

  await requireActiveProfile(db, uid);
  await requireBusinessMembership(db, uid, businessId);

  // Checkout per seller: o token vem da conexão OAuth da loja (nunca do
  // token global da plataforma). Sem conexão ativa, a loja não recebe.
  const connection = await readMerchantConnection(businessId);
  if (connection === null || isConnectionExpired(connection)) {
    throw apiError(
      'failed-precondition',
      'Esta loja ainda nao conectou a conta Mercado Pago para receber vendas.',
    );
  }


  const userSnap = await db.doc(`users/${uid}`).get();
  const userData = userSnap.data();
  const payerName =
    typeof userData?.nome === 'string' && userData.nome.trim() !== ''
      ? userData.nome.trim()
      : '';

  const packageSnap = await db.doc(`businesses/${businessId}/packages/${packageId}`).get();
  if (!packageSnap.exists) {
    throw apiError('not-found', 'Pacote não encontrado.');
  }
  const pkg = packageSnap.data()!;
  if (pkg.ativo !== true) {
    throw apiError('failed-precondition', 'Pacote inativo.');
  }
  const value = requireCatalogValue(pkg);
  const title =
    typeof pkg.nome === 'string' && pkg.nome.trim() !== ''
      ? pkg.nome.trim()
      : 'Pacote';

  // Phase 1 (transaction): replay complete checkouts, otherwise create the
  // PENDENTE payment the preference will be pinned to.
  let paymentId = '';
  const replay = await withTransaction(db, async (transaction) => {
    if (idempotencyKey !== undefined) {
      const idempotencyRef = db.doc(`mpCheckoutIdempotency/${idempotencyKey}`);
      const idempotencySnap = await transaction.get(idempotencyRef);
      if (idempotencySnap.exists) {
        const existing = idempotencySnap.data()!;
        if (existing.uid !== uid) {
          throw apiError(
            'permission-denied',
            'Chave de idempotência pertence a outro usuário.',
          );
        }
        const storedPaymentId =
          typeof existing.paymentId === 'string' ? existing.paymentId : '';
        const storedPreferenceId =
          typeof existing.preferenceId === 'string' ? existing.preferenceId : '';
        const storedInitPoint =
          typeof existing.initPoint === 'string' ? existing.initPoint : '';
        if (storedPaymentId !== '' && storedPreferenceId !== '' && storedInitPoint !== '') {
          return {
            paymentId: storedPaymentId,
            preferenceId: storedPreferenceId,
            initPoint: storedInitPoint,
          };
        }
        if (storedPaymentId === '') {
          throw apiError('failed-precondition', 'Registro de idempotência inválido.');
        }
        // Incomplete replay (payment created, preference lost): reuse it.
        paymentId = storedPaymentId;
      }
    }

    if (paymentId === '') {
      const paymentRef = db
        .collection(`businesses/${businessId}/payments`)
        .doc();
      const now = FieldValue.serverTimestamp();
      transaction.set(paymentRef, {
        businessId,
      id_cliente: uid,
        clientName: payerName,
        tipo: TIPO_PACOTE,
        id_pacote: packageId,
        id_pacote_cliente: null,
        id_agendamento: null,
        valor: value.valor,
        forma_pagamento: FORMA_MERCADO_PAGO,
        status: STATUS_PENDENTE,
        statusHistory: [
          { status: STATUS_PENDENTE, changedBy: uid, changedAt: Timestamp.now() },
        ],
        statusChangedAt: now,
        statusChangedBy: uid,
        gatewayStatus: 'CREATING',
        // Snapshot do recebedor: identifica em qual conta Mercado Pago o
        // pagamento sera creditado e permite o webhook validar o seller.
        merchantConnectionId: businessId,
        collectorId: connection.collectorId,
        liveMode: connection.liveMode,
        createdAt: now,
      });
      paymentId = paymentRef.id;

      if (idempotencyKey !== undefined) {
        transaction.set(db.doc(`mpCheckoutIdempotency/${idempotencyKey}`), {
          uid,
          paymentId,
          status: 'CREATING',
          createdAt: FieldValue.serverTimestamp(),
        });
      }
      // Rota do webhook: external_reference (paymentId) -> businessId. Sem
      // ela o webhook nao saberia em qual tenant consultar o pagamento.
      transaction.set(db.doc(`paymentRoutes/${paymentRef.id}`), {
        businessId,
        paymentId: paymentRef.id,
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    return undefined;
  });
  if (replay !== undefined) {
    return replay;
  }

  // Phase 2: create the preference at Mercado Pago (outside the transaction:
  // a network call must never run inside a retried transaction).
  const sellerClient = mp ?? createMpClient(connection.accessToken);
  let preferenceId = '';
  let initPoint = '';
  try {
    const preference = await sellerClient.createPreference({
      title,
      unitPrice: value.valor,
      payerName,
      externalReference: paymentId,
      notificationUrl: getMpWebhookUrl(),
    });
    preferenceId = preference.id;
    initPoint = preference.initPoint;
  } catch (err) {
    if (err instanceof HttpsError) {
      throw err;
    }
    // Unreachable/unexpected Mercado Pago error: close the payment so the
    // pending checkout never leaks, then surface `unavailable` to the app.
    const { logger } = await import('firebase-functions');
    logger.error('Falha ao criar preferência no Mercado Pago', err);
    try {
      await cancelUnstartedPayment(db, businessId, paymentId);
    } catch (cancelErr) {
      logger.error('Falha ao cancelar pagamento não iniciado', cancelErr);
    }
    throw apiError(
      'unavailable',
      'Não foi possível iniciar o pagamento no momento. Tente novamente.',
    );
  }

  // Phase 3: pin the preference ids on the payment + idempotency record.
  await withTransaction(db, async (transaction) => {
    transaction.update(db.doc(`businesses/${businessId}/payments/${paymentId}`), {
      gatewayPreferenceId: preferenceId,
      gatewayInitPoint: initPoint,
      gatewayStatus: 'CREATED',
      gatewayUpdatedAt: FieldValue.serverTimestamp(),
    });
    if (idempotencyKey !== undefined) {
      transaction.update(db.doc(`mpCheckoutIdempotency/${idempotencyKey}`), {
        preferenceId,
        initPoint,
        status: 'CREATED',
      });
    }
  });

  return { paymentId, preferenceId, initPoint };
}

/** Public callable (registered via functions/src/index.ts). */
export const createMercadoPagoCheckout = onCall(wrap(createMercadoPagoCheckoutHandler));

/**
 * Closes a checkout that never reached Mercado Pago: cancels the payment
 * (only from PENDENTE — a concurrent webhook may have already paid it) and
 * stamps gatewayStatus 'ERROR' for traceability.
 */
async function cancelUnstartedPayment(
  db: import('firebase-admin/firestore').Firestore,
  businessId: string,
  paymentId: string,
): Promise<void> {
  await withTransaction(db, async (transaction) => {
    const paymentRef = db.doc(`businesses/${businessId}/payments/${paymentId}`);
    const paymentSnap = await transaction.get(paymentRef);
    if (!paymentSnap.exists) {
      return;
    }
    const payment = paymentSnap.data()!;
    if (payment.status !== STATUS_PENDENTE) {
      return;
    }
    const statusHistory = Array.isArray(payment.statusHistory)
      ? [...(payment.statusHistory as Array<Record<string, unknown>>)]
      : [];
    statusHistory.push({
      status: STATUS_CANCELADO,
      changedBy: CANCEL_ACTOR,
      changedAt: Timestamp.now(),
    });
    transaction.update(paymentRef, {
      status: STATUS_CANCELADO,
      statusChangedAt: FieldValue.serverTimestamp(),
      statusChangedBy: CANCEL_ACTOR,
      canceledAt: FieldValue.serverTimestamp(),
      statusHistory,
      gatewayStatus: 'ERROR',
    });
  });
}