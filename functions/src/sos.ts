import { FieldValue, Timestamp, type DocumentReference } from 'firebase-admin/firestore';
import { LIMITS } from './config.js';
import { optionalNumber, reject, requireString } from './errors.js';
import { expireAt, type Ctx } from './families.js';
import { paths } from './paths.js';
import { checkRateLimit } from './rate_limit.js';

/** Envío de notificaciones push (FCM en producción, simulado en pruebas). */
export interface NotifyResult {
  /** Mensajes que ACEPTÓ el proveedor (no cuántos se leyeron). */
  accepted: number;
  /** Tokens que el proveedor declaró inválidos (app desinstalada, etc.). */
  invalidTokens: string[];
}

export interface Notifier {
  notifySos(tokens: string[], data: { familyId: string; alertId: string }): Promise<NotifyResult>;
}

export interface SosResult {
  alertId: string;
  notifiedCount: number | null;
  alreadyExisted: boolean;
}

/**
 * Registra una alerta SOS y avisa a los demás integrantes.
 *
 * Idempotente por `alertId`: un reintento devuelve la alerta existente. Si un
 * intento anterior se interrumpió antes de notificar, el siguiente completa
 * la notificación (un *lease* evita duplicados entre reintentos simultáneos).
 */
export async function raiseSos(ctx: Ctx, data: unknown, notifier: Notifier): Promise<SosResult> {
  const familyId = requireString(data, 'familyId');
  const alertId = requireString(data, 'alertId', 64);
  const lat = optionalNumber(data, 'lat');
  const lng = optionalNumber(data, 'lng');
  const accuracyM = optionalNumber(data, 'accuracyM');
  const hasLocation =
    lat !== undefined && lng !== undefined && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;

  const ref = ctx.db.doc(paths.emergency(familyId, alertId));
  const outcome = await ctx.db.runTransaction(async (tx) => {
    const member = await tx.get(ctx.db.doc(paths.member(familyId, ctx.uid)));
    if (!member.exists) reject('permission-denied', 'not-member');
    const existing = await tx.get(ref);
    if (existing.exists) {
      if (existing.get('uid') !== ctx.uid) reject('permission-denied', 'not-allowed');
      const notified = existing.get('notifiedCount') as number | null;
      const leaseAt = existing.get('notifyStartedAt') as Timestamp | null | undefined;
      const leaseFree =
        notified === null &&
        (leaseAt == null || ctx.now.getTime() - leaseAt.toMillis() > LIMITS.sosNotifyLeaseMs);
      if (leaseFree) tx.update(ref, { notifyStartedAt: Timestamp.fromDate(ctx.now) });
      return { created: false, notify: leaseFree, notified };
    }
    const commitRateLimit = await checkRateLimit(
      ctx.db,
      tx,
      ctx.uid,
      'raiseSos',
      LIMITS.sosPerHour,
      ctx.now,
    );
    commitRateLimit();
    tx.set(ref, {
      uid: ctx.uid,
      createdAt: FieldValue.serverTimestamp(),
      ...(hasLocation ? { lat, lng, accuracyM: accuracyM ?? null } : {}),
      notifiedCount: null,
      notifyStartedAt: Timestamp.fromDate(ctx.now),
      acks: {},
      resolvedAt: null,
      expireAt: expireAt(ctx.now, LIMITS.sosTtlDays),
    });
    tx.set(ctx.db.collection(paths.events(familyId)).doc(), {
      type: 'sos',
      actorUid: ctx.uid,
      alertId,
      createdAt: FieldValue.serverTimestamp(),
      expireAt: expireAt(ctx.now, LIMITS.sosTtlDays),
    });
    tx.set(ctx.db.collection(paths.audit(familyId)).doc(), {
      action: 'raiseSos',
      actorUid: ctx.uid,
      createdAt: FieldValue.serverTimestamp(),
      expireAt: expireAt(ctx.now, LIMITS.auditTtlDays),
    });
    return { created: true, notify: true, notified: null };
  });

  if (!outcome.notify) {
    return { alertId, notifiedCount: outcome.notified, alreadyExisted: !outcome.created };
  }
  const devices = await recipientDevices(ctx, familyId);
  let notifiedCount: number;
  try {
    const result =
      devices.length === 0
        ? { accepted: 0, invalidTokens: [] }
        : await notifier.notifySos(
            devices.map((d) => d.token),
            { familyId, alertId },
          );
    notifiedCount = result.accepted;
    await forgetInvalidDevices(ctx, devices, result.invalidTokens);
  } catch {
    // Se libera el lease y el conteo sigue «desconocido» (null): el cliente
    // recibe un error transitorio y su bandeja de salida reintenta, y ese
    // reintento completa la notificación (nunca se finge un 0 definitivo).
    await ref.update({ notifyStartedAt: null });
    reject('unavailable', 'notification-unavailable');
  }
  await ref.update({ notifiedCount, notifyStartedAt: null });
  return { alertId, notifiedCount, alreadyExisted: !outcome.created };
}

interface Device {
  token: string;
  ref: DocumentReference;
}

/** Dispositivos de los DEMÁS integrantes. */
async function recipientDevices(ctx: Ctx, familyId: string): Promise<Device[]> {
  const members = await ctx.db.collection(paths.members(familyId)).get();
  const result: Device[] = [];
  for (const member of members.docs) {
    if (member.id === ctx.uid) continue;
    const devices = await ctx.db.collection(paths.devices(member.id)).get();
    for (const device of devices.docs) {
      const token = device.get('token');
      if (typeof token === 'string' && token.length > 0) result.push({ token, ref: device.ref });
    }
  }
  return result;
}

/**
 * Borra los dispositivos cuyo token el proveedor rechazó como inválido: no
 * vuelven a contarse ni a intentarse. Es una limpieza: si falla, el aviso
 * ya se envió y no debe convertirse en error.
 */
async function forgetInvalidDevices(ctx: Ctx, devices: Device[], invalid: string[]): Promise<void> {
  if (invalid.length === 0) return;
  const stale = new Set(invalid);
  try {
    const batch = ctx.db.batch();
    for (const device of devices) if (stale.has(device.token)) batch.delete(device.ref);
    await batch.commit();
  } catch {
    // Se reintentará con la siguiente alerta.
  }
}
