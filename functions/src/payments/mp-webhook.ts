import { createHmac, timingSafeEqual } from 'node:crypto';
import { getFirestore } from 'firebase-admin/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { onRequest } from 'firebase-functions/v2/https';
import type { Request } from 'firebase-functions/v2/https';

import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';
import { apiError } from '../shared/errors';
import { withTransaction } from '../shared/firestore';
import { activatePackageInTransaction } from '../packages/activate-package';
import { readMerchantConnection, findMerchantConnectionByCollector } from './merchant-connection-store';
import { createMpClient, getMpAccessToken, getMpWebhookSecret } from './mercadopago-client';
import type { MpClient } from './mercadopago-client';
import { applyStatusTransition } from './apply-status';

const STATUS_ATIVO = 'ATIVO';
const STATUS_REEMBOLSADO = 'REEMBOLSADO';

/** 100 KB: notificacoes reais do Mercado Pago cabem em poucos KB. */
const MAX_WEBHOOK_BODY_BYTES = 100 * 1024;

/** Rough UTF-8 byte length of the request body, whatever its JSON shape. */
function bodyByteLength(body: unknown): number {
  if (typeof body === 'string') {
    return Buffer.byteLength(body, 'utf8');
  }
  try {
    return Buffer.byteLength(JSON.stringify(body ?? ''), 'utf8');
  } catch {
    return 0;
  }
}

/** Minimal Express-like response surface (structural: express.Response satisfies it). */
export interface WebhookResponseLike {
  status(code: number): WebhookResponseLike;
  json(body?: unknown): WebhookResponseLike;
  send(body?: unknown): WebhookResponseLike;
}

export interface MercadoPagoWebhookBody {
  type?: string;
  topic?: string;
  data?: { id?: number | string };
  id?: number | string;
  /** Seller (collector) id — used to validate the payment's owner. */
  user_id?: number | string;
}

export interface MercadoPagoWebhookOutcome {
  received: boolean;
  outcome:
    | 'noop' // already processed (replay) or no status change needed
    | 'applied' // payment transitioned and package activated (when approved)
    | 'invalid' // state machine rejected the target status
    | 'missing' // payment doc not found (late/foreign notification)
    | 'gateway'; // gateway fields updated only
}

/**
 * Mercado Pago payment webhook (HTTP). Both v2 (`type: payment`,
 * `data.id`) and v3 (`topic: payment`, `id`) notification shapes are
 * accepted; every other topic is acknowledged and ignored.
 *
 * The payment is ALWAYS re-read from the Mercado Pago API — the notification
 * body is never trusted. `external_reference` (our payment id, set by
 * createMercadoPagoCheckout) is the only link back to Firestore.
 *
 * Status mapping (Mercado Pago -> our machine):
 *   approved      -> PAGO     (+ package activation in the same transaction)
 *   pending       -> gateway fields only (document is born PENDENTE)
 *   in_process, authorized -> EM_ANALISE
 *   rejected / cancelled / expired   -> CANCELADO
 *   refunded / charged_back          -> REEMBOLSADO
 *
 * Idempotency: replays are detected via gatewayPaymentId + target status
 * (charged_back after approved is legitimately a different target).
 *
 * Ack policy: non-payment topics resolve to 200 (no retry); permanent
 * conditions (missing payment, HttpsError) are acknowledged with 200/ignored;
 * unexpected errors return 500 so Mercado Pago retries.
 */
export async function mercadoPagoWebhookHandler(
  request: Request,
  response: WebhookResponseLike,
  mp?: MpClient,
): Promise<void> {
  try {
    // Limite de tamanho do corpo: o webhook e publico, e um payload de
    // varios MB (JSON desconhecido) consumiria memoria/CPU antes de qualquer
    // validacao. Notificacoes reais do Mercado Pago sao pequenas.
    const bodySize = bodyByteLength(request.body);
    if (bodySize > MAX_WEBHOOK_BODY_BYTES) {
      logger.warn('Webhook Mercado Pago com corpo grande demais', { bodySize });
      response.status(413).send('payload muito grande');
      return;
    }
    const secret = getMpWebhookSecret();
    if (!isRunningInEmulator() && secret === '') {
      // Fail closed in production: without the shared secret, no signature
      // can be verified, so unauthenticated status updates would be possible.
      logger.error(
        'MERCADOPAGO_WEBHOOK_SECRET ausente em produção; webhook recusado.',
      );
      response.status(500).send('webhook não configurado');
      return;
    }
    if (secret !== '') {
      const mpPaymentId = extractMpPaymentId(request.body);
      const headers = request.headers ?? {};
      const valid = validateMpWebhookSignature(
        headerValue(headers['x-signature']),
        headerValue(headers['x-request-id']),
        mpPaymentId,
        secret,
      );
      if (!valid) {
        logger.warn('Webhook Mercado Pago com assinatura inválida', {
          paymentId: mpPaymentId,
        });
        response.status(401).json({ received: false, reason: 'invalid-signature' });
        return;
      }
    }
    const outcome = await handleWebhook(request.body, mp);
    response.status(200).json(outcome);
  } catch (err) {
    if (err instanceof HttpsError) {
      // Permanent condition (e.g. machine rejects the target): ack so MP
      // stops retrying; the payment state on our side is untouched.
      logger.warn(`Webhook ignorado (permanente): ${err.code}`, { message: err.message });
      response.status(200).json({ received: true, outcome: 'invalid' as const });
      return;
    }
    logger.error('Erro inesperado no webhook Mercado Pago', err);
    response.status(500).send('erro interno');
  }
}

async function handleWebhook(
  body: unknown,
  mp?: MpClient,
): Promise<MercadoPagoWebhookOutcome> {
  const mpPaymentId = extractMpPaymentId(body);
  if (mpPaymentId === '') {
    return { received: true, outcome: 'noop' };
  }

  const db = getFirestore();

  // O user_id do seller identifica a conexão — o webhook nunca consulta o
  // pagamento com o token global da plataforma. Em arquitetura multi-seller
  // cada loja tem a própria conta Mercado Pago conectada via OAuth; o token
  // global não consegue ler o pagamento de outro seller (403/404). Buscamos
  // a connection pelo collectorId e usamos o accessToken dela. Sem connection
  // localizável, caímos no token global apenas como compatibilidade legada.
  const sellerUserId = extractMpSellerUserId(body);
  let sellerConnection: import('./merchant-connection-store').MerchantConnection | null = null;
  if (sellerUserId !== '') {
    sellerConnection = await findMerchantConnectionByCollector(sellerUserId);
  }
  const accessToken =
    sellerConnection !== null && sellerConnection.accessToken !== ''
      ? sellerConnection.accessToken
      : getMpAccessToken();
  const client = mp ?? createMpClient(accessToken);
  const info = await client.getPayment(mpPaymentId);
  if (
    info === null ||
    info.id === '' ||
    info.status === '' ||
    info.externalReference === undefined ||
    info.externalReference === ''
  ) {
    return { received: true, outcome: 'noop' };
  }

  const paymentId = info.externalReference;

  // Resolve a rota external_reference -> businessId (criada pelo checkout).
  // Sem rota, o webhook nao sabe em qual tenant o pagamento vive.
  const routeSnap = await db.doc(`paymentRoutes/${paymentId}`).get();
  if (!routeSnap.exists) {
    return { received: true, outcome: 'missing' };
  }
  const route = routeSnap.data()!;
  const businessId =
    typeof route.businessId === 'string' ? route.businessId : '';
  if (businessId === '') {
    return { received: true, outcome: 'missing' };
  }

  // Validacao multi-seller: o pagamento consultado precisa pertencer ao
  // seller conectado da loja (binding recebedor-pagamento).
  const connection = await readMerchantConnection(businessId);
  if (connection !== null && sellerUserId !== '' && sellerUserId !== connection.collectorId) {
    logger.warn('Webhook com seller incompatível com a loja', {
      businessId,
      sellerUserId,
      collectorId: connection.collectorId,
    });
    return { received: true, outcome: 'missing' };
  }

  const target = mapMpStatusToPaymentStatus(info.status);

  const outcome = await withTransaction(db, async (transaction) => {
    const paymentRef = db.doc(`businesses/${businessId}/payments/${paymentId}`);
    const paymentSnap = await transaction.get(paymentRef);
    if (!paymentSnap.exists) {
      // Late notification for an already-deleted payment (or foreign
      // external_reference): acknowledge, nothing to do.
      return 'missing' as const;
    }
    const payment = paymentSnap.data()!;
    const currentStatus =
      typeof payment.status === 'string' ? payment.status : '';

    // Todas as reads ANTES de qualquer write (regra do Firestore). O pacote
    // vinculado pode precisar ser bloqueado no reembolso.
    const customerPackageId =
      target === 'REEMBOLSADO' &&
      typeof payment.id_pacote_cliente === 'string'
        ? payment.id_pacote_cliente
        : '';
    const customerPackageRef =
      customerPackageId === ''
        ? null
        : db.doc(
            `businesses/${businessId}/customerPackages/${customerPackageId}`,
          );
    const customerPackageSnap =
      customerPackageRef === null ? null : await transaction.get(customerPackageRef);

    const gatewayUpdates: Record<string, unknown> = {
      gatewayPaymentId: info.id,
      gatewayStatus: info.status,
      gatewayMethod: info.paymentMethodId ?? null,
      gatewaySyncedAt: FieldValue.serverTimestamp(),
    };
    const forma = mapMethodIdToForma(info.paymentMethodId);
    if (forma !== undefined) {
      gatewayUpdates.forma_pagamento = forma;
    }

    // Replay detection: same MP payment + same target already processed.
    if (
      payment.gatewayPaymentId === info.id &&
      (target === undefined || target === currentStatus)
    ) {
      // Still refresh gateway metadata, but never repeat a state change.
      transaction.update(paymentRef, gatewayUpdates);
      return 'noop' as const;
    }

    if (target === undefined) {
      // pending/unknown: no state change.
      transaction.update(paymentRef, gatewayUpdates);
      return 'gateway' as const;
    }

    if (target === 'PAGO') {
      // approved: activate the package in the SAME transaction the payment
      // transitions to PAGO. Already-activated payments are a no-op.
      const activateOutcome = await activatePackageInTransaction(
        transaction,
        paymentRef,
        payment,
        'mercadopago',
        true,
      );
      transaction.update(paymentRef, gatewayUpdates);
      if (activateOutcome === null) {
        return 'noop' as const;
      }
      return 'applied' as const;
    }

    // CANCELADO / REEMBOLSADO through the shared state machine.
    const transition = applyStatusTransition(transaction, paymentRef, payment, target, 'mercadopago');
    if (transition === 'invalid') {
      // E.g. approved -> CANCELADO (real payment already made): keep state,
      // but persist gateway metadata so the mismatch is traceable.
      transaction.update(paymentRef, gatewayUpdates);
      throw apiError('failed-precondition', `Transição inválida para ${target}.`);
    }
    transaction.update(paymentRef, gatewayUpdates);

    // Reembolso: bloqueia o saldo restante do pacote vinculado. Os créditos
    // já consumidos ficam preservados para auditoria; novos usos são
    // impedidos (createAppointment só consome pacotes ATIVO).
    if (
      target === 'REEMBOLSADO' &&
      transition !== 'noop' &&
      customerPackageRef !== null &&
      customerPackageSnap !== null &&
      customerPackageSnap.exists
    ) {
      const customerPackage = customerPackageSnap.data()!;
      if (customerPackage.status === STATUS_ATIVO) {
        transaction.update(customerPackageRef, {
          status: STATUS_REEMBOLSADO,
          refundedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }

    return transition === 'noop' ? ('noop' as const) : ('applied' as const);
  });

  return { received: true, outcome };
}

/**
 * Extracts the Mercado Pago payment id from both notification shapes.
 * Returns '' when the topic is not payment (acknowledge + ignore).
 */
export function extractMpPaymentId(body: unknown): string {
  if (typeof body !== 'object' || body === null) {
    return '';
  }
  const raw = body as MercadoPagoWebhookBody;
  if (raw.type === 'payment' && raw.data !== undefined && raw.data !== null) {
    return String(raw.data.id ?? '');
  }
  if (
    (raw.topic === 'payment' || raw.topic === undefined) &&
    raw.id !== undefined &&
    raw.id !== null
  ) {
    return String(raw.id);
  }
  return '';
}

/**
 * Extracts the seller `user_id` from the notification. The webhook uses it to
 * validate that the payment belongs to the connected seller of the business.
 */
export function extractMpSellerUserId(body: unknown): string {
  if (typeof body !== 'object' || body === null) {
    return '';
  }
  const raw = body as Record<string, unknown>;
  const userId = raw.user_id ?? raw.userId;
  if (typeof userId === 'number') {
    return String(userId);
  }
  return typeof userId === 'string' ? userId : '';
}

/**
 * Verifies the Mercado Pago v2 webhook signature (docs: "Webhook Mercado
 * Pago", validação de assinatura). `x-signature` carries
 * `ts=<timestamp>,v1=<hex>` and the signed manifest is
 * `id:<data.id>;request-id:<x-request-id>;ts:<ts>;` — the secret is the HMAC
 * key, never part of the signed text.
 */
export function validateMpWebhookSignature(
  xSignature: string | undefined,
  xRequestId: string | undefined,
  mpPaymentId: string,
  secret: string,
): boolean {
  if (xSignature === undefined || xSignature === '') {
    return false;
  }
  const pairs = new Map<string, string>();
  for (const part of xSignature.split(',')) {
    const index = part.indexOf('=');
    if (index <= 0) {
      continue;
    }
    pairs.set(part.slice(0, index), part.slice(index + 1));
  }
  const timestamp = pairs.get('ts');
  const signature = pairs.get('v1');
  if (timestamp === undefined || signature === undefined || signature === '') {
    return false;
  }
  const manifest = `id:${mpPaymentId};request-id:${xRequestId ?? ''};ts:${timestamp};`;
  const expected = createHmac('sha256', secret).update(manifest).digest('hex');
  const expectedBuffer = Buffer.from(expected, 'hex');
  const givenBuffer = Buffer.from(signature, 'hex');
  return (
    expectedBuffer.length === givenBuffer.length &&
    timingSafeEqual(expectedBuffer, givenBuffer)
  );
}

function headerValue(value: string | string[] | undefined): string | undefined {
  if (typeof value === 'string') {
    return value;
  }
  return undefined;
}

/**
 * True when running under the Firebase emulator (FUNCTIONS_EMULATOR=true).
 * Signature enforcement is relaxed there; production always requires
 * MERCADOPAGO_WEBHOOK_SECRET (see mercadoPagoWebhookHandler).
 */
export function isRunningInEmulator(): boolean {
  return process.env.FUNCTIONS_EMULATOR === 'true';
}

/** Maps a Mercado Pago payment status onto our machine; undefined = no state change. */
export function mapMpStatusToPaymentStatus(status: string): string | undefined {
  switch (status) {
    case 'approved':
      return 'PAGO';
    case 'pending':
      // The document is born PENDENTE; keep it there.
      return undefined;
    case 'in_process':
    case 'authorized':
      return 'EM_ANALISE';
    case 'rejected':
    case 'cancelled':
    case 'expired':
      return 'CANCELADO';
    case 'refunded':
    case 'charged_back':
      return 'REEMBOLSADO';
    default:
      return undefined;
  }
}

/** Refines forma_pagamento from the payment method used at Mercado Pago. */
export function mapMethodIdToForma(methodId: string | undefined): string | undefined {
  switch (methodId) {
    case 'pix':
      return 'PIX';
    case 'credit_card':
    case 'debit_card':
      return 'CARTAO';
    case 'bolbradesco':
      return 'BOLETO';
    // Real-world Checkout Pro sends the card brand as payment_method_id
    // (e.g. 'visa'); map the common brands to CARTAO.
    case 'visa':
    case 'master':
    case 'amex':
    case 'elo':
    case 'hipercard':
    case 'hiper':
    case 'naranja':
    case 'argencard':
    case 'cabal':
    case 'maestro':
      return 'CARTAO';
    default:
      return undefined;
  }
}

/** Registered via functions/src/index.ts. */
export const mercadoPagoWebhook = onRequest(mercadoPagoWebhookHandler);