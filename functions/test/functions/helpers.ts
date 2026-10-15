import { deleteApp, getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import type { Ctx } from '../../src/families.js';

/** Firestore del emulador (FIRESTORE_EMULATOR_HOST lo define emulators:exec). */
export function emulatorDb(): Firestore {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('Ejecuta estas pruebas con `npm test` (requiere el emulador).');
  }
  const app = getApps()[0] ?? initializeApp({ projectId: 'demo-nexo' });
  return getFirestore(app);
}

export async function clearEmulator(): Promise<void> {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const response = await fetch(
    `http://${host}/emulator/v1/projects/demo-nexo/databases/(default)/documents`,
    { method: 'DELETE' },
  );
  if (!response.ok) throw new Error(`No se pudo limpiar el emulador: ${response.status}`);
}

export async function closeApps(): Promise<void> {
  await Promise.all(getApps().map((app) => deleteApp(app)));
}

/** Reloj controlable para límites por hora y vencimientos. */
export class TestClock {
  constructor(private millis = Date.UTC(2026, 0, 1, 12)) {}
  get now(): Date {
    return new Date(this.millis);
  }
  advance(ms: number): void {
    this.millis += ms;
  }
}

export function ctxFor(db: Firestore, uid: string, clock: TestClock): Ctx {
  return { db, uid, now: clock.now };
}

/** Todos los documentos de la base (para buscar fugas de datos). */
export async function dumpAll(db: Firestore): Promise<string> {
  const out: unknown[] = [];
  async function walk(collections: FirebaseFirestore.CollectionReference[]) {
    for (const col of collections) {
      const docs = await col.listDocuments();
      for (const ref of docs) {
        const snap = await ref.get();
        if (snap.exists) out.push({ path: ref.path, data: snap.data() });
        await walk(await ref.listCollections());
      }
    }
  }
  await walk(await db.listCollections());
  return JSON.stringify(out);
}

export { Timestamp };
