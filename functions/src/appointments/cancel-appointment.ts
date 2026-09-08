import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import type { CallableRequest } from 'firebase-functions/v2/https';

import { authUser, requireActiveProfile } from '../auth/authorization';
import { requireBusinessMembership } from '../businesses/business-authorization';
import { apiError, wrap } from '../shared/errors';
import { withTransaction } from '../shared/firestore';
import { slotDocId, slotRange } from './slot-keys';

export interface CancelAppointmentArgs {
  /** Business id (tenant) the appointment lives in. */
  businessId: string;
  appointmentId: string;
  idempotencyKey?: string;
}

export interface CancelAppointmentResult {
  appointmentId: string;
  /** false when the appointment was already canceled (idempotent no-op). */
  canceled: boolean;
}

const STATUS_CANCELADO = 'CANCELADO';
const STATUS_AGENDADO = 'AGENDADO';
const STATUS_CONFIRMADO = 'CONFIRMADO';
const STATUS_ATIVO = 'ATIVO';
const STATUS_FINALIZADO = 'FINALIZADO';

/** Roles allowed to manage any appointment, mirroring isStaff() in the rules. */
const STAFF_ROLES = new Set(['owner', 'admin', 'collaborator']);

/**
 * Core handler. Cancellation is idempotent: canceling an already-canceled
 * appointment is a no-op that never touches credits, usage or slot locks a
 * second time. Slot locks are released and package credits refunded exactly
 * once, atomically.
 */
export async function cancelAppointmentHandler(
  request: CallableRequest<CancelAppointmentArgs>,
): Promise<CancelAppointmentResult> {
  const { uid } = authUser(request);
  const db = getFirestore();

  const args = (request.data ?? {}) as Partial<CancelAppointmentArgs>;
  const businessId = requireDocId(args.businessId, 'businessId');
  const appointmentId = requireDocId(args.appointmentId, 'appointmentId');
  const idempotencyKey = optionalIdempotencyKey(args.idempotencyKey);

  const membership = await requireBusinessMembership(db, uid, businessId);
  const isStaff = STAFF_ROLES.has(membership.role);

  return withTransaction(db, async (transaction) => {
    if (idempotencyKey !== undefined) {
      const idempotencyRef = db.doc(
        `cancelAppointmentIdempotency/${idempotencyKey}`,
      );
      const idempotencySnap = await transaction.get(idempotencyRef);
      if (idempotencySnap.exists) {
        const existing = idempotencySnap.data()!;
        if (existing.uid !== uid) {
          throw apiError(
            'permission-denied',
            'Chave de idempotência pertence a outro usuário.',
          );
        }
        const storedAppointmentId =
          typeof existing.appointmentId === 'string'
            ? existing.appointmentId
            : '';
        if (storedAppointmentId === '' || typeof existing.canceled !== 'boolean') {
          throw apiError('failed-precondition', 'Registro de idempotência inválido.');
        }
        return {
          appointmentId: storedAppointmentId,
          canceled: existing.canceled,
        };
      }
    }

    // All reads first (Firestore requires reads before writes in a
    // transaction), then every write.
    const appointmentRef = db.doc(`businesses/${businessId}/appointments/${appointmentId}`);
    const appointmentSnap = await transaction.get(appointmentRef);
    if (!appointmentSnap.exists) {
      throw apiError('not-found', 'Agendamento não encontrado.');
    }
    const appointment = appointmentSnap.data()!;

    // Authorization mirrors the rules: client owner or staff may cancel;
    // anyone else is denied.
    if (!isStaff && appointment.id_cliente !== uid) {
      throw apiError('permission-denied', 'Acesso negado ao agendamento.');
    }

    if (appointment.status === STATUS_CANCELADO) {
      if (idempotencyKey !== undefined) {
        transaction.set(db.doc(`cancelAppointmentIdempotency/${idempotencyKey}`), {
          uid,
          appointmentId,
          canceled: false,
          createdAt: FieldValue.serverTimestamp(),
        });
      }
      return { appointmentId, canceled: false };
    }

    // Apenas agendamentos AGENDADO/CONFIRMADO podem ser cancelados. Um
    // atendimento CONCLUIDO (ou status desconhecido) nunca estorna credito.
    if (
      appointment.status !== STATUS_AGENDADO &&
      appointment.status !== STATUS_CONFIRMADO
    ) {
      throw apiError('failed-precondition', 'Agendamento não pode ser cancelado.');
    }

    const packageId = appointment.id_pacote_cliente;
    let packageData: Record<string, unknown> | undefined;
    if (typeof packageId === 'string' && packageId !== '') {
      
        packageData = (await transaction.get(db.doc(`businesses/${businessId}/customerPackages/${packageId}`)))
        .data();
    }

    // Flag every usage record tied to this appointment as estornado (the
    // create flow writes exactly one, but flag all matches defensively).
    const usageSnap = await transaction.get(
      db
          .collection(`businesses/${businessId}/packageUsage`)
          .where('id_agendamento', '==', appointmentId),
    );

    transaction.update(appointmentRef, {
      status: STATUS_CANCELADO,
      canceledAt: FieldValue.serverTimestamp(),
      canceledBy: uid,
      updatedAt: FieldValue.serverTimestamp(),
    });

    for (const docId of slotDocIdsToDelete(businessId, appointment)) {
      transaction.delete(db.doc(`businesses/${businessId}/appointmentSlots/${docId}`));
    }

    if (packageData !== undefined) {
      const usedCredits =
        typeof packageData.creditos_usados === 'number'
          ? packageData.creditos_usados
          : NaN;
      if (Number.isInteger(usedCredits) && usedCredits >= 0) {
        const statusUpdate: Record<string, unknown> = {
          creditos_usados: usedCredits > 0 ? usedCredits - 1 : 0,
          updatedAt: FieldValue.serverTimestamp(),
        };
        // Refund returns the package to ATIVO unless it left the active
        // lifecycle for good (expired or canceled — never resurrect those).
        // Um pacote com data_validade no passado NAO pode voltar a ATIVO:
        // createAppointment rejeita pacotes vencidos, entao ressuscita-lo
        // so criaria um pacote "ativo" inutilizavel com saldo inconsistente.
        const validity = packageData.data_validade as
          | import('firebase-admin/firestore').Timestamp
          | undefined;
        const expired =
          validity !== undefined && validity.toDate().getTime() <= Date.now();
        if (
          !expired &&
          (packageData.status === STATUS_ATIVO ||
            packageData.status === STATUS_FINALIZADO)
        ) {
          statusUpdate.status = STATUS_ATIVO;
        }
        transaction.update(db.doc(`businesses/${businessId}/customerPackages/${packageId}`), statusUpdate);
      }
    }

    for (const usageDoc of usageSnap.docs) {
      transaction.update(usageDoc.ref, {
        estornado: true,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    if (idempotencyKey !== undefined) {
      transaction.set(db.doc(`cancelAppointmentIdempotency/${idempotencyKey}`), {
        uid,
        appointmentId,
        canceled: true,
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    return { appointmentId, canceled: true };
  });
}

/** Public callable (registered via functions/src/index.ts). */
export const cancelAppointment = onCall(wrap(cancelAppointmentHandler));

function requireText(value: unknown, field: string): string {
  if (typeof value !== 'string' || value.trim() === '') {
    throw apiError('invalid-argument', `Campo ${field} é obrigatório.`);
  }
  return value;
}

function requireDocId(value: unknown, field: string): string {
  const text = requireText(value, field);
  if (
    text.length > 100 ||
    /[\/\\\s\x00-\x1f]/.test(text) ||
    text === '.' ||
    text === '..'
  ) {
    throw apiError(
      'invalid-argument',
      `Campo ${field} contém caracteres inválidos.`,
    );
  }
  return text;
}

function optionalIdempotencyKey(value: unknown): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (
    typeof value !== 'string' ||
    value.trim() === '' ||
    value.length > 1500 ||
    value.includes('/')
  ) {
    throw apiError('invalid-argument', 'Campo idempotencyKey inválido.');
  }
  return value;
}

/**
 * Slot lock doc ids the appointment holds. Derived from the same
 * start/end timestamps the create flow used, so every lock created is
 * released. Falls back to the dayKey/timeKey single slot for legacy
 * appointments without timestamps.
 */
function slotDocIdsToDelete(
  businessId: string,
  appointment: Record<string, unknown>,
): string[] {
  const startAt = asDate(appointment.data_hora_inicio);
  const endAt = asDate(appointment.data_hora_fim);
  if (
    startAt !== null &&
    endAt !== null &&
    endAt.getTime() > startAt.getTime()
  ) {
    return slotRange(businessId, startAt, endAt).map(
      (slot) => slot.docId,
    );
  }
  if (
    typeof appointment.dayKey === 'string' &&
    typeof appointment.timeKey === 'string'
  ) {
    return [
      slotDocId(businessId, appointment.dayKey, appointment.timeKey),
    ];
  }
  return [];
}

function asDate(value: unknown): Date | null {
  if (value instanceof Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value;
  }
  return null;
}
