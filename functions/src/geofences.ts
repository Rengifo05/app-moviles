import { FieldValue } from 'firebase-admin/firestore';
import { LIMITS } from './config.js';
import { reject, requireString } from './errors.js';
import { roleOf, type Ctx } from './families.js';
import { paths } from './paths.js';

/** Identificador de zona que genera la app (UUID v7) o equivalente. */
const ID = /^[A-Za-z0-9_-]{1,64}$/;

/**
 * Crea una zona. Pasa por el servidor para aplicar el máximo de zonas por
 * familia, que las reglas no pueden contar. Cambiar y borrar zonas sigue
 * siendo una escritura directa validada por las reglas.
 *
 * Idempotente por `geofenceId`: el reintento de una creación que sí llegó al
 * servidor devuelve la zona existente sin contarla dos veces.
 */
export async function createGeofence(
  ctx: Ctx,
  data: unknown,
): Promise<{ geofenceId: string; alreadyExisted: boolean }> {
  const familyId = requireString(data, 'familyId');
  const geofenceId = requireString(data, 'geofenceId', 64);
  if (!ID.test(geofenceId)) reject('invalid-argument', 'geofence-id-invalid');
  const name = requireString(data, 'name', LIMITS.geofenceNameMax).trim();
  if (name.length === 0 || !/[\p{L}\p{N}]/u.test(name)) {
    reject('invalid-argument', 'geofence-name-invalid');
  }
  const { lat, lng, radiusM } = (data ?? {}) as Record<string, unknown>;
  if (typeof lat !== 'number' || !Number.isFinite(lat) || Math.abs(lat) > 90) {
    reject('invalid-argument', 'lat-invalid');
  }
  if (typeof lng !== 'number' || !Number.isFinite(lng) || Math.abs(lng) > 180) {
    reject('invalid-argument', 'lng-invalid');
  }
  if (
    typeof radiusM !== 'number' ||
    !Number.isFinite(radiusM) ||
    radiusM < LIMITS.geofenceRadiusMin ||
    radiusM > LIMITS.geofenceRadiusMax
  ) {
    reject('invalid-argument', 'radius-invalid');
  }

  return ctx.db.runTransaction(async (tx) => {
    const role = await roleOf(ctx, tx, familyId, ctx.uid);
    if (role === null) reject('permission-denied', 'not-member');
    if (role === 'member') reject('permission-denied', 'not-allowed');
    const ref = ctx.db.doc(paths.geofence(familyId, geofenceId));
    const [existing, zones] = await Promise.all([
      tx.get(ref),
      tx.get(ctx.db.collection(paths.geofences(familyId)).select()),
    ]);
    if (existing.exists) {
      // Solo es un reintento si es la misma persona; si no, choca.
      if (existing.get('createdBy') !== ctx.uid) reject('already-exists', 'conflict');
      return { geofenceId, alreadyExisted: true };
    }
    if (zones.size >= LIMITS.maxGeofencesPerFamily) {
      reject('resource-exhausted', 'too-many-geofences');
    }
    tx.create(ref, {
      name,
      lat,
      lng,
      radiusM,
      createdBy: ctx.uid,
      version: 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { geofenceId, alreadyExisted: false };
  });
}
