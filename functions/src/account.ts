import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import type { Ctx } from './families.js';
import { leaveFamily } from './families.js';
import { paths } from './paths.js';

/** Borra los datos de autenticación (Firebase Auth en producción). */
export interface AuthDeleter {
  deleteUser(uid: string): Promise<void>;
}

/** Revoca las sesiones (Firebase Auth en producción). */
export interface SessionRevoker {
  revokeRefreshTokens(uid: string): Promise<void>;
}

/**
 * "Cerrar sesión en todos los dispositivos" (amenaza 2: cuenta
 * comprometida). Revoca los refresh tokens, así que ningún dispositivo puede
 * renovar su sesión, y borra los dispositivos registrados para avisos: un
 * teléfono perdido deja de recibir alertas SOS de la familia.
 *
 * También revoca las invitaciones activas que creó.
 *
 * Límite conocido: un ID token ya emitido sigue siendo válido para Firestore
 * y las Functions hasta que vence (≤ 1 h); las reglas no pueden consultar la
 * revocación.
 */
export async function signOutEverywhere(
  ctx: Ctx,
  auth: SessionRevoker,
): Promise<Record<string, never>> {
  await auth.revokeRefreshTokens(ctx.uid);
  await ctx.db.recursiveDelete(ctx.db.collection(paths.devices(ctx.uid)));
  // Un código creado desde la sesión comprometida dejaría entrar a alguien
  // más tarde: se revocan los que siguen activos.
  const active = await ctx.db
    .collection('invitations')
    .where('createdBy', '==', ctx.uid)
    .where('status', '==', 'active')
    .get();
  await inBatches(ctx.db, active.docs, (batch, ref) => batch.update(ref, { status: 'revoked' }));
  return {};
}

/** Sustituye el identificador de una cuenta eliminada en la auditoría. */
export const DELETED_USER = 'deleted-user';

/** Eventos del historial que contienen datos personales de su autor. */
const PERSONAL_EVENT_TYPES = new Set(['checkIn', 'geofence']);

/**
 * Elimina la cuenta: sale de todas las familias (con las mismas reglas de
 * herencia y borrado), limpia lo que dejó en **cualquier** familia, borra el
 * perfil y sus subcolecciones y, por último, el usuario de autenticación.
 *
 * Es idempotente: si falla a mitad, el reintento vuelve a buscar los restos
 * en todas las familias (no solo en las membresías que aún existen), así que
 * nada queda sin limpiar aunque la persona ya hubiera salido de una familia.
 */
export async function deleteAccount(ctx: Ctx, auth: AuthDeleter): Promise<Record<string, never>> {
  const memberships = await ctx.db.collection(paths.memberships(ctx.uid)).get();
  for (const membership of memberships.docs) {
    try {
      await leaveFamily(ctx, { familyId: membership.id });
    } catch (error) {
      // Si la expulsaron mientras tanto, ya salió: se sigue con el resto.
      if (!isReason(error, 'not-member')) throw error;
    }
  }
  await scrubEverywhere(ctx.db, ctx.uid);
  await ctx.db.recursiveDelete(ctx.db.doc(paths.user(ctx.uid)));
  await ctx.db.doc(paths.rateLimit(ctx.uid)).delete();
  await auth.deleteUser(ctx.uid);
  return {};
}

function isReason(error: unknown, reason: string): boolean {
  return (error as { details?: { reason?: string } }).details?.reason === reason;
}

/**
 * Lo que la persona deja en las familias, incluidas aquellas de las que ya
 * salió o la expulsaron (consultas de grupo de colecciones; sus índices están
 * en firestore.indexes.json):
 * - sus check-ins y eventos de zona (mensajes y lugares) se borran ya, sin
 *   esperar a la TTL;
 * - sus alertas SOS se conservan para la familia hasta su TTL, pero sin
 *   coordenadas;
 * - la auditoría se anonimiza, igual que `createdBy` en familias y zonas
 *   (campos sin TTL);
 * - sus invitaciones se borran (nadie podrá usarlas).
 */
async function scrubEverywhere(db: Firestore, uid: string): Promise<void> {
  const events = await db.collectionGroup('events').where('actorUid', '==', uid).get();
  await inBatches(
    db,
    events.docs.filter((d) => PERSONAL_EVENT_TYPES.has(d.get('type') as string)),
    (batch, ref) => batch.delete(ref),
  );

  const alerts = await db.collectionGroup('emergencies').where('uid', '==', uid).get();
  await updateEach(alerts.docs, {
    lat: FieldValue.delete(),
    lng: FieldValue.delete(),
    accuracyM: FieldValue.delete(),
  });

  for (const field of ['actorUid', 'targetUid']) {
    const docs = await db.collectionGroup('audit').where(field, '==', uid).get();
    await updateEach(docs.docs, { [field]: DELETED_USER });
  }

  const families = await db.collection('families').where('createdBy', '==', uid).get();
  await updateEach(families.docs, { createdBy: DELETED_USER });

  // La versión sube: un cliente con la zona antigua en caché recibe el
  // conflicto de versión en lugar de pisar el cambio.
  const zones = await db.collectionGroup('geofences').where('createdBy', '==', uid).get();
  await updateEach(zones.docs, { createdBy: DELETED_USER, version: FieldValue.increment(1) });

  const invitations = await db.collection('invitations').where('createdBy', '==', uid).get();
  await inBatches(db, invitations.docs, (batch, ref) => batch.delete(ref));
}

/**
 * `update` documento a documento: si la TTL o un borrado de la familia se
 * llevó uno entre la consulta y la escritura (NOT_FOUND), ya no hay nada que
 * limpiar y no debe hacer fallar el resto.
 */
async function updateEach(
  docs: { ref: FirebaseFirestore.DocumentReference }[],
  data: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData>,
): Promise<void> {
  const results = await Promise.allSettled(docs.map((d) => d.ref.update(data)));
  for (const result of results) {
    if (result.status === 'rejected' && (result.reason as { code?: number }).code !== NOT_FOUND) {
      throw result.reason;
    }
  }
}

/** Código gRPC de documento inexistente. */
const NOT_FOUND = 5;

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
