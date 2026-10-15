import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import type { Ctx } from './families.js';
import { leaveFamily } from './families.js';
import { paths } from './paths.js';

/** Borra los datos de autenticación (Firebase Auth en producción). */
export interface AuthDeleter {
  deleteUser(uid: string): Promise<void>;
}

/** Sustituye el identificador de una cuenta eliminada en la auditoría. */
export const DELETED_USER = 'deleted-user';

/** Eventos del historial que contienen datos personales de su autor. */
const PERSONAL_EVENT_TYPES = new Set(['checkIn', 'geofence']);

/**
 * Elimina la cuenta: sale de todas las familias (con las mismas reglas de
 * herencia y borrado), limpia lo que dejó en ellas, borra el perfil y sus
 * subcolecciones y, por último, el usuario de autenticación.
 */
export async function deleteAccount(ctx: Ctx, auth: AuthDeleter): Promise<Record<string, never>> {
  const memberships = await ctx.db.collection(paths.memberships(ctx.uid)).get();
  for (const membership of memberships.docs) {
    await leaveFamily(ctx, { familyId: membership.id });
    await scrubFamily(ctx.db, membership.id, ctx.uid);
  }
  await ctx.db.recursiveDelete(ctx.db.doc(paths.user(ctx.uid)));
  await ctx.db.doc(paths.rateLimit(ctx.uid)).delete();
  await auth.deleteUser(ctx.uid);
  return {};
}

/**
 * Lo que la persona deja en una familia de la que ya salió (si la familia
 * se borró por quedar vacía, las consultas no devuelven nada):
 * - sus check-ins y eventos de zona (mensajes y lugares) se borran ya, sin
 *   esperar a la TTL;
 * - sus alertas SOS se conservan para la familia hasta su TTL, pero sin
 *   coordenadas;
 * - la auditoría se anonimiza.
 */
async function scrubFamily(db: Firestore, familyId: string, uid: string): Promise<void> {
  const events = await db.collection(paths.events(familyId)).where('actorUid', '==', uid).get();
  await inBatches(
    db,
    events.docs.filter((d) => PERSONAL_EVENT_TYPES.has(d.get('type') as string)),
    (batch, ref) => batch.delete(ref),
  );

  const alerts = await db.collection(paths.emergencies(familyId)).where('uid', '==', uid).get();
  await inBatches(db, alerts.docs, (batch, ref) =>
    batch.update(ref, {
      lat: FieldValue.delete(),
      lng: FieldValue.delete(),
      accuracyM: FieldValue.delete(),
    }),
  );

  const audit = db.collection(paths.audit(familyId));
  for (const field of ['actorUid', 'targetUid']) {
    const docs = await audit.where(field, '==', uid).get();
    await inBatches(db, docs.docs, (batch, ref) => batch.update(ref, { [field]: DELETED_USER }));
  }
}

/** Aplica una escritura por documento en lotes (Firestore admite 500). */
async function inBatches(
  db: Firestore,
  docs: { ref: FirebaseFirestore.DocumentReference }[],
  write: (batch: FirebaseFirestore.WriteBatch, ref: FirebaseFirestore.DocumentReference) => void,
): Promise<void> {
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    for (const doc of docs.slice(i, i + 400)) write(batch, doc.ref);
    await batch.commit();
  }
}
