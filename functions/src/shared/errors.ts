import { logger } from 'firebase-functions';
import {
  CallableRequest,
  FunctionsErrorCode,
  HttpsError,
} from 'firebase-functions/v2/https';

export { HttpsError };
export type { CallableRequest, FunctionsErrorCode };

/** Builds a typed HttpsError (maps to the matching gRPC status over HTTP). */
export function apiError(code: FunctionsErrorCode, message: string): HttpsError {
  return new HttpsError(code, message);
}

/**
 * Wraps a v2 callable handler so any thrown HttpsError passes through
 * untouched, while unexpected errors become `internal` (500) with a generic
 * message. Internal details are logged server-side and never leaked.
 */
export function wrap<Args, T>(
  fn: (request: CallableRequest<Args>) => Promise<T>,
): (request: CallableRequest<Args>) => Promise<T> {
  return async (request: CallableRequest<Args>): Promise<T> => {
    try {
      return await fn(request);
    } catch (err) {
      if (err instanceof HttpsError) {
        throw err;
      }
      logger.error('Unexpected error in callable handler', err);
      throw new HttpsError('internal', 'Erro interno do servidor.');
    }
  };
}
