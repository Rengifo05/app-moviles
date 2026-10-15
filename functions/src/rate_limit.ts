import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { reject } from './errors.js';
import { paths } from './paths.js';

const HOUR_MS = 60 * 60 * 1000;

/**
 * Límite deslizante por usuario y acción, dentro de una transacción.
 * Debe llamarse antes de cualquier escritura de la transacción (Firestore
 * exige leer antes de escribir).
 */
export async function checkRateLimit(
  db: Firestore,
  tx: Transaction,
  uid: string,
  key: string,
  maxPerHour: number,
  now: Date,
): Promise<() => void> {
  const ref = db.doc(paths.rateLimit(uid));
  const snap = await tx.get(ref);
  const recent = ((snap.get(key) as number[] | undefined) ?? []).filter(
    (t) => now.getTime() - t < HOUR_MS,
  );
  if (recent.length >= maxPerHour) reject('resource-exhausted', 'rate-limited');
  // Se devuelve la escritura para hacerla después de las demás lecturas.
  return () => tx.set(ref, { [key]: [...recent, now.getTime()] }, { merge: true });
}
