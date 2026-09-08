/**
 * Strict payment status state machine (Task 13). Single source of truth for
 * the allowed `payments/{id}` transitions and the semantic timestamp each
 * terminal-ish status stamps on the doc (paidAt / canceledAt / refundedAt).
 */

export const PAYMENT_STATUS = {
  PENDENTE: 'PENDENTE',
  PAGO: 'PAGO',
  CANCELADO: 'CANCELADO',
  REEMBOLSADO: 'REEMBOLSADO',
  EM_ANALISE: 'EM_ANALISE',
} as const;

/** Every known status value; used to validate callable input. */
export const ALL_PAYMENT_STATUSES: ReadonlySet<string> = new Set(
  Object.values(PAYMENT_STATUS),
);

/**
 * Allowed transitions, per the plan:
 * PENDENTE -> PAGO | CANCELADO | EM_ANALISE
 * EM_ANALISE -> PAGO | CANCELADO
 * PAGO -> REEMBOLSADO
 * Anything else (including repeats of terminal statuses) is invalid.
 */
export const ALLOWED_TRANSITIONS: Readonly<Record<string, ReadonlySet<string>>> = {
  [PAYMENT_STATUS.PENDENTE]: new Set([
    PAYMENT_STATUS.PAGO,
    PAYMENT_STATUS.CANCELADO,
    PAYMENT_STATUS.EM_ANALISE,
  ]),
  [PAYMENT_STATUS.EM_ANALISE]: new Set([
    PAYMENT_STATUS.PAGO,
    PAYMENT_STATUS.CANCELADO,
  ]),
  [PAYMENT_STATUS.PAGO]: new Set([PAYMENT_STATUS.REEMBOLSADO]),
};

/**
 * The semantic timestamp field each status writes (if any). Only the
 * payment-defining outcomes stamp a doc field; EM_ANALISE does not.
 */
export const SEMANTIC_TIMESTAMP_FIELD: Readonly<Record<string, string>> = {
  [PAYMENT_STATUS.PAGO]: 'paidAt',
  [PAYMENT_STATUS.CANCELADO]: 'canceledAt',
  [PAYMENT_STATUS.REEMBOLSADO]: 'refundedAt',
};

/** True when the state machine allows `from -> to`. */
export function canTransition(from: string, to: string): boolean {
  return ALLOWED_TRANSITIONS[from]?.has(to) ?? false;
}
