import { HttpsError, type FunctionsErrorCode } from 'firebase-functions/v2/https';

/**
 * Rechaza una llamada con un código HTTP estándar y un motivo estable
 * (`details.reason`) que la app traduce a un mensaje. Nunca incluye datos
 * personales ni coordenadas.
 */
export function reject(code: FunctionsErrorCode, reason: string): never {
  throw new HttpsError(code, reason, { reason });
}

export function requireString(data: unknown, key: string, max = 200): string {
  const value = (data as Record<string, unknown> | null)?.[key];
  if (typeof value !== 'string' || value.trim().length === 0 || value.length > max) {
    reject('invalid-argument', `${toKebab(key)}-required`);
  }
  return value;
}

export function optionalNumber(data: unknown, key: string): number | undefined {
  const value = (data as Record<string, unknown> | null)?.[key];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    reject('invalid-argument', `${toKebab(key)}-invalid`);
  }
  return value;
}

function toKebab(key: string): string {
  return key.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);
}
