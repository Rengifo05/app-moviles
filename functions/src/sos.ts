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
    // La ubicación se ajusta al consentimiento VIGENTE, no al del momento en
    // que el teléfono preparó la alerta: un reintento de un SOS en cola
    // después de pausar no publica coordenadas, y con "aproximada" se
    // redondean como en la app (rejilla de 0,01°).
    const consent = await tx.get(ctx.db.doc(paths.consent(familyId, ctx.uid)));
    const location = shareableLocation(
      hasLocation ? { lat: lat!, lng: lng!, accuracyM } : null,
      consent.get('state'),
      consent.get('precision'),
    );
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
      ...(location ?? {}),
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
    await forgetInvalidDevices(devices, result.invalidTokens);
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
  /** Para no borrar un dispositivo que renovó su token mientras tanto. */
  updateTime: Timestamp;
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
      if (typeof token === 'string' && token.length > 0) {
        result.push({ token, ref: device.ref, updateTime: device.updateTime });
      }
    }
  }
  return result;
}

/**
 * Borra los dispositivos cuyo token el proveedor rechazó como inválido: no
 * vuelven a contarse ni a intentarse. Es una limpieza: si falla, el aviso
 * ya se envió y no debe convertirse en error.
 */
async function forgetInvalidDevices(devices: Device[], invalid: string[]): Promise<void> {
  if (invalid.length === 0) return;
  const stale = new Set(invalid);
  // Solo si el documento no cambió desde que se leyó: si el teléfono renovó
  // su token en paralelo, el documento nuevo se conserva. Los fallos se
  // ignoran (se reintentará con la siguiente alerta).
  await Promise.allSettled(
    devices
      .filter((d) => stale.has(d.token))
      .map((d) => d.ref.delete({ lastUpdateTime: d.updateTime })),
  );
}

/** Ubicación que se puede guardar según el consentimiento vigente. */
export function shareableLocation(
  point: { lat: number; lng: number; accuracyM: number | undefined } | null,
  state: unknown,
  precision: unknown,
): { lat: number; lng: number; accuracyM: number | null } | null {
  if (point === null || state !== 'sharing') return null;
  if (precision === 'exact') {
    return { lat: point.lat, lng: point.lng, accuracyM: point.accuracyM ?? null };
  }
  // Cualquier otra precisión se trata como la que menos revela.
  const snap = (degrees: number) => Math.round(degrees * 100) / 100 + 0;
  return {
    lat: snap(point.lat),
    lng: snap(point.lng),
    accuracyM: Math.max(point.accuracyM ?? 0, 1000),
  };
}
