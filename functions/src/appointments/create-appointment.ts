import { getFirestore } from 'firebase-admin/firestore';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import type { CallableRequest } from 'firebase-functions/v2/https';

import { authUser, requireActiveProfile } from '../auth/authorization';
import { requireBusinessMembership } from '../businesses/business-authorization';
import { apiError, wrap } from '../shared/errors';
import { withTransaction } from '../shared/firestore';
import {
  SLOT_MINUTES,
  businessWeekday,
  dayKey,
  minutesOfDay,
  slotRange,
  timeKey,
} from './slot-keys';

export interface CreateAppointmentArgs {
  /** Business id (tenant) the appointment is booked in. */
  businessId: string;
  serviceId: string;
  /** ISO 8601 timestamp; wall-clock is interpreted in America/Sao_Paulo. */
  startAt: string;
  customerPackageId?: string;
  idempotencyKey?: string;
}

export interface CreateAppointmentResult {
  appointmentId: string;
}

const STATUS_AGENDADO = 'AGENDADO';
const STATUS_ATIVO = 'ATIVO';
const STATUS_FINALIZADO = 'FINALIZADO';

// Business hours port of lib/services/business_hours.dart.
const WEEKDAY_OPEN_MIN = 8 * 60; // 08:00
const WEEKDAY_CLOSE_MIN = 18 * 60; // 18:00 (exclusive)
const SATURDAY_CLOSE_MIN = 12 * 60; // 12:00 (inclusive)
const RESTRICTED_WEEKDAY_CLOSE_MIN = 16 * 60; // 16:00 (inclusive)
const RESTRICTED_SATURDAY_CLOSE_MIN = 10 * 60; // 10:00 (inclusive)

/**
 * Accent normalization matching lib/services/business_hours.dart: lowercase,
 * strip common accents, collapse whitespace.
 */
export function normalizeAccents(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/[\u00E0\u00E1\u00E2\u00E3\u00E4]/g, 'a')
    .replace(/[\u00E8\u00E9\u00EA\u00EB]/g, 'e')
    .replace(/[\u00EC\u00ED\u00EE\u00EF]/g, 'i')
    .replace(/[\u00F2\u00F3\u00F4\u00F5\u00F6]/g, 'o')
    .replace(/[\u00F9\u00FA\u00FB\u00FC]/g, 'u')
    .replace(/\u00E7/g, 'c')
    .replace(/\s+/g, ' ');
}

/** Bath/grooming services ('banho'/'tosa') have narrower booking windows. */
export function isBathOrGrooming(serviceName: string): boolean {
  const normalized = normalizeAccents(serviceName);
  return normalized.includes('banho') || normalized.includes('tosa');
}

/**
 * Business-hours check ported from lib/services/business_hours.dart:
 * Sunday closed; Monday-Friday 08:00-18:00 (bath/grooming 08:00-16:00);
 * Saturday 08:00-12:00 (bath/grooming 08:00-10:00).
 */
export function isInsideBookingHours(startAt: Date, serviceName: string): boolean {
  const minutes = minutesOfDay(startAt);
  const weekday = businessWeekday(startAt);

  if (weekday === 7) {
    return false;
  }
  const restricted = isBathOrGrooming(serviceName);
  if (weekday === 6) {
    return (
      minutes >= WEEKDAY_OPEN_MIN &&
      minutes <= (restricted ? RESTRICTED_SATURDAY_CLOSE_MIN : SATURDAY_CLOSE_MIN)
    );
  }
  if (restricted) {
    return minutes >= WEEKDAY_OPEN_MIN && minutes <= RESTRICTED_WEEKDAY_CLOSE_MIN;
  }
  return minutes >= WEEKDAY_OPEN_MIN && minutes < WEEKDAY_CLOSE_MIN;
}

/**
 * True when `endAt` is on or before the closing time for `serviceName`.
 * Closing is inclusive on Saturdays/restricted days (a 12:00 end is valid);
 * on regular weekdays the end must be at or before 18:00.
 */
export function serviceEndsByClosing(endAt: Date, serviceName: string): boolean {
  const minutes = minutesOfDay(endAt);
  const weekday = businessWeekday(endAt);

  if (weekday === 7) {
    return false;
  }
  const restricted = isBathOrGrooming(serviceName);
  if (weekday === 6) {
    return minutes <= (restricted ? RESTRICTED_SATURDAY_CLOSE_MIN : SATURDAY_CLOSE_MIN);
  }
  if (restricted) {
    return minutes <= RESTRICTED_WEEKDAY_CLOSE_MIN;
  }
  return minutes <= WEEKDAY_CLOSE_MIN;
}

/**
 * Core handler. The client identity is ALWAYS taken from the caller's auth
 * uid — a client-sent id is never accepted. All reads/writes run against the
 * authoritative Firestore data.
 */
export async function createAppointmentHandler(
  request: CallableRequest<CreateAppointmentArgs>,
): Promise<CreateAppointmentResult> {
  const { uid } = authUser(request);
  const db = getFirestore();

  const args = (request.data ?? {}) as Partial<CreateAppointmentArgs>;
  const businessId = requireDocId(args.businessId, 'businessId');
  const serviceId = requireDocId(args.serviceId, 'serviceId');
  const startAt = parseStartAt(args.startAt);
  if (startAt.getTime() <= Date.now()) {
    throw apiError('invalid-argument', 'Agendamento no passado.');
  }
  const customerPackageId = optionalText(args.customerPackageId, 'customerPackageId');
  const idempotencyKey = optionalIdempotencyKey(args.idempotencyKey);

  await requireActiveProfile(db, uid);
  await requireBusinessMembership(db, uid, businessId);

  const userSnap = await db.doc(`users/${uid}`).get();
  const userData = userSnap.data();
  const clientName =
    typeof userData?.nome === 'string' && userData.nome.trim() !== ''
      ? userData.nome
      : '';

  const serviceSnap = await db.doc(`businesses/${businessId}/services/${serviceId}`).get();
  if (!serviceSnap.exists) {
    throw apiError('not-found', 'Serviço não encontrado.');
  }

  const service = serviceSnap.data()!;
  if (service.ativo !== true) {
    throw apiError('failed-precondition', 'Serviço inativo.');
  }

  const serviceName = typeof service.nome === 'string' ? service.nome : '';
  const durationMinutes =
    typeof service.duracao_minutos === 'number' ? service.duracao_minutos : NaN;
  if (!Number.isInteger(durationMinutes) || durationMinutes <= 0) {
    throw apiError('invalid-argument', 'Duração do serviço inválida.');
  }
  if (durationMinutes % SLOT_MINUTES !== 0) {
    throw apiError('invalid-argument', 'Serviço com duração fora da grade de 30 minutos.');
  }
  if (minutesOfDay(startAt) % SLOT_MINUTES !== 0) {
    throw apiError('invalid-argument', 'Horário de início fora da grade de 30 minutos.');
  }
  if (!isInsideBookingHours(startAt, serviceName)) {
    throw apiError('failed-precondition', 'Fora do horário de atendimento.');
  }

  // O fechamento nao e "ultima hora de inicio": o servico inteiro precisa
  // terminar dentro do expediente (ex.: banho de 60min as 17:30 termina as
  // 18:30 e deve ser recusado num dia util).
  const endAt = new Date(startAt.getTime() + durationMinutes * 60_000);
  if (!serviceEndsByClosing(endAt, serviceName)) {
    throw apiError(
      'failed-precondition',
      'Serviço termina após o horário de atendimento.',
    );
  }

  const startDayKey = dayKey(startAt);
  const startTimeKey = timeKey(startAt);
  const slots = slotRange(businessId, startAt, endAt);

  const appointmentId = await withTransaction(db, async (transaction) => {
    if (idempotencyKey !== undefined) {
      const idempotencyRef = db.doc(`appointmentIdempotency/${idempotencyKey}`);
      const idempotencySnap = await transaction.get(idempotencyRef);
      if (idempotencySnap.exists) {
        const existing = idempotencySnap.data()!;
        if (existing.uid !== uid) {
          throw apiError('permission-denied', 'Chave de idempotência pertence a outro usuário.');
        }
        const existingAppointmentId =
          typeof existing.appointmentId === 'string' ? existing.appointmentId : '';
        if (existingAppointmentId === '') {
          throw apiError('failed-precondition', 'Registro de idempotência inválido.');
        }
        return existingAppointmentId;
      }
    }

    for (const slot of slots) {
      const slotSnap = await transaction.get(db.doc(`businesses/${businessId}/appointmentSlots/${slot.docId}`));
      if (slotSnap.exists) {
        throw apiError('already-exists', 'Horario ja reservado.');
      }
    }

    const appointmentRef = db
        .collection(`businesses/${businessId}/appointments`)
        .doc();
    let packageId: string | null = null;

    if (customerPackageId !== undefined) {
      const packageRef = db.doc(`businesses/${businessId}/customerPackages/${customerPackageId}`);
      const packageSnap = await transaction.get(packageRef);
      if (!packageSnap.exists) {
        throw apiError('not-found', 'Pacote do cliente não encontrado.');
      }

      const customerPackage = packageSnap.data()!;
      if (customerPackage.id_cliente !== uid) {
        throw apiError('permission-denied', 'Pacote não pertence ao usuário.');
      }
      const packageServiceId =
        typeof customerPackage.id_servico === 'string' ? customerPackage.id_servico : '';
      if (packageServiceId !== '' && packageServiceId !== serviceId) {
        throw apiError('failed-precondition', 'Pacote não é válido para este serviço.');
      }

      const totalCredits =
        typeof customerPackage.creditos_totais === 'number'
          ? customerPackage.creditos_totais
          : NaN;
      const usedCredits =
        typeof customerPackage.creditos_usados === 'number'
          ? customerPackage.creditos_usados
          : NaN;
      if (
        !Number.isInteger(totalCredits) ||
        totalCredits <= 0 ||
        !Number.isInteger(usedCredits) ||
        usedCredits < 0
      ) {
        throw apiError('failed-precondition', 'Pacote inválido.');
      }
      if (customerPackage.status !== STATUS_ATIVO || usedCredits >= totalCredits) {
        throw apiError('failed-precondition', 'Pacote sem créditos disponíveis.');
      }

      // Pacote vencido nunca pode ser consumido, mesmo se ainda marcado ATIVO.
      const validUntil = customerPackage.data_validade;
      if (
        validUntil instanceof Timestamp &&
        startAt.getTime() > validUntil.toDate().getTime()
      ) {
        throw apiError('failed-precondition', 'Pacote vencido.');
      }

      const newUsedCredits = usedCredits + 1;
      transaction.update(packageRef, {
        creditos_usados: newUsedCredits,
        status: newUsedCredits >= totalCredits ? STATUS_FINALIZADO : STATUS_ATIVO,
        updatedAt: FieldValue.serverTimestamp(),
      });

      transaction.set(db.collection(`businesses/${businessId}/packageUsage`).doc(), {
        id_cliente: uid,
        clientName,
        id_pacote_cliente: customerPackageId,
        id_agendamento: appointmentRef.id,
        serviceName,
        usedAt: Timestamp.fromDate(startAt),
        createdAt: FieldValue.serverTimestamp(),
      });
      packageId = customerPackageId;
    }

    transaction.set(appointmentRef, {
      id_cliente: uid,
      clientName,
      id_servico: serviceId,
      serviceName,
      id_pacote_cliente: packageId,
      data_hora_inicio: Timestamp.fromDate(startAt),
      data_hora_fim: Timestamp.fromDate(endAt),
      dayKey: startDayKey,
      timeKey: startTimeKey,
      status: STATUS_AGENDADO,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    for (const slot of slots) {
      transaction.set(db.doc(`businesses/${businessId}/appointmentSlots/${slot.docId}`), {
        dayKey: startDayKey,
        timeKey: slot.timeKey,
        appointmentId: appointmentRef.id,
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    if (idempotencyKey !== undefined) {
      transaction.set(db.doc(`appointmentIdempotency/${idempotencyKey}`), {
        uid,
        appointmentId: appointmentRef.id,
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    return appointmentRef.id;
  });

  return { appointmentId };
}

/** Public callable (registered via functions/src/index.ts). */
export const createAppointment = onCall(wrap(createAppointmentHandler));

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

function optionalText(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== 'string' || value.trim() === '') {
    throw apiError('invalid-argument', `Campo ${field} inválido.`);
  }
  return value;
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

function parseStartAt(value: unknown): Date {
  if (typeof value !== 'string' || value.trim() === '') {
    throw apiError('invalid-argument', 'Campo startAt é obrigatório.');
  }
  const trimmed = value.trim();
  // Rejeita ISO "naive" (sem fuso): new Date(...) interpretaria como hora
  // local do servidor, ambigua para wall-clock America/Sao_Paulo.
  if (!/(Z|[+-]\d{2}:\d{2})$/i.test(trimmed)) {
    throw apiError(
      'invalid-argument',
      'startAt deve incluir fuso horario (formato ISO 8601 com Z ou offset).',
    );
  }
  const date = new Date(trimmed);
  if (Number.isNaN(date.getTime())) {
    throw apiError('invalid-argument', 'Campo startAt inválido.');
  }
  return date;
}
