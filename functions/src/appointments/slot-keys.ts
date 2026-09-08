/**
 * Slot-grid key helpers (Task 10).
 *
 * dayKey/timeKey mirror the Flutter app (lib/app/formatters.dart):
 * dayKey 'YYYY-MM-DD', timeKey 'HH:MM' on 30-minute boundaries, expressed in
 * the business time zone (America/Sao_Paulo — the app's home market; the
 * Firestore region is southamerica-east1).
 */

export const SLOT_MINUTES = 30;
export const BUSINESS_TIME_ZONE = 'America/Sao_Paulo';

export interface Slot {
  timeKey: string;
  docId: string;
}

const pad2 = (n: number): string => n.toString().padStart(2, '0');

/**
 * Returns a Date whose UTC components hold the wall-clock time of `date` in
 * the business time zone, so getUTC* accessors can be used downstream.
 */
export function toBusinessLocal(date: Date): Date {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: BUSINESS_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(date);

  const read = (type: Intl.DateTimeFormatPartTypes): number => {
    const part = parts.find((p) => p.type === type);
    return part === undefined ? 0 : Number(part.value);
  };

  return new Date(
    Date.UTC(
      read('year'),
      read('month') - 1,
      read('day'),
      read('hour'),
      read('minute'),
      read('second'),
    ),
  );
}

/** 'YYYY-MM-DD' of `date` in the business time zone. */
export function dayKey(date: Date): string {
  const local = toBusinessLocal(date);
  return `${local.getUTCFullYear()}-${pad2(local.getUTCMonth() + 1)}-${pad2(local.getUTCDate())}`;
}

/** 'HH:MM' of `date` in the business time zone. */
export function timeKey(date: Date): string {
  const local = toBusinessLocal(date);
  return `${pad2(local.getUTCHours())}:${pad2(local.getUTCMinutes())}`;
}

/** Minutes since midnight of `date` in the business time zone. */
export function minutesOfDay(date: Date): number {
  const local = toBusinessLocal(date);
  return local.getUTCHours() * 60 + local.getUTCMinutes();
}

/** Weekday of `date` in the business time zone: 1 (Monday) .. 7 (Sunday). */
export function businessWeekday(date: Date): number {
  const local = toBusinessLocal(date);
  const day = local.getUTCDay();
  return day === 0 ? 7 : day;
}

/**
 * Document id for an appointment slot lock:
 * `appointmentSlots/{businessId}_{dayKey}_{timeKey}`.
 * The businessId prefix keeps slot locks isolated between tenants.
 */
export function slotDocId(
  businessId: string,
  dayKey: string,
  timeKey: string,
): string {
  return `${businessId}_${dayKey}_${timeKey}`;
}

/**
 * Every 30-minute boundary covered by [startAt, endAt): from startAt up to
 * (but not including) endAt. A 60-minute booking at 09:00 yields 09:00 and
 * 09:30. Shared by create (locks) and cancel (unlocks) — the document ids
 * must match exactly or stale locks would survive cancellation.
 */
export function slotRange(
  businessId: string,
  startAt: Date,
  endAt: Date,
): Slot[] {
  const startDayKey = dayKey(startAt);
  const slots: Slot[] = [];
  const startMs = startAt.getTime();
  const endMs = endAt.getTime();
  for (let cursor = startMs; cursor < endMs; cursor += SLOT_MINUTES * 60_000) {
    const slotStart = new Date(cursor);
    const slotTimeKey = timeKey(slotStart);
    slots.push({
      timeKey: slotTimeKey,
      docId: slotDocId(businessId, startDayKey, slotTimeKey),
    });
  }
  return slots;
}
