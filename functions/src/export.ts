import { Timestamp } from 'firebase-admin/firestore';
import { LIMITS } from './config.js';
import type { Ctx } from './families.js';
import { paths } from './paths.js';
import { checkRateLimit } from './rate_limit.js';

/** Datos de la cuenta en el proveedor de autenticación (Firebase Auth). */
export interface AccountReader {
  account(uid: string): Promise<{ email: string | null; createdAt: string | null }>;
}

/** Formato del archivo; cambia si cambia la estructura. */
export const EXPORT_SCHEMA = 'nexo-familia/export@1';

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };

/**
 * Derecho de acceso (Ley 1581 de 2012): todo lo que el servicio guarda de la
 * persona, en JSON legible, en TODAS las familias (también aquellas de las
 * que ya salió).
 *
 * No incluye:
 * - los tokens de avisos (identificadores técnicos del teléfono): solo la
 *   plataforma y la fecha de cada dispositivo;
 * - datos de otras personas (sus ubicaciones, mensajes o nombres), salvo el
 *   nombre de cada familia;
 * - la auditoría de las familias.
 */
export async function exportMyData(
  ctx: Ctx,
  accounts: AccountReader,
): Promise<{ schema: string; generatedAt: string; data: Json }> {
  // Exportar cuesta lecturas: unas pocas por hora bastan.
  await ctx.db.runTransaction(async (tx) => {
    const commit = await checkRateLimit(
      ctx.db,
      tx,
      ctx.uid,
      'exportMyData',
      LIMITS.exportPerHour,
      ctx.now,
    );
    commit();
  });

  const [account, profile, devices, memberships, events, emergencies] = await Promise.all([
    accounts.account(ctx.uid),
    ctx.db.doc(paths.user(ctx.uid)).get(),
    ctx.db.collection(paths.devices(ctx.uid)).get(),
    ctx.db.collection(paths.memberships(ctx.uid)).get(),
    ctx.db.collectionGroup('events').where('actorUid', '==', ctx.uid).get(),
    ctx.db.collectionGroup('emergencies').where('uid', '==', ctx.uid).get(),
  ]);

  const families: Json[] = [];
  for (const membership of memberships.docs) {
    const familyId = membership.id;
    const [family, member, consent, location] = await Promise.all([
      ctx.db.doc(paths.family(familyId)).get(),
      ctx.db.doc(paths.member(familyId, ctx.uid)).get(),
      ctx.db.doc(paths.consent(familyId, ctx.uid)).get(),
      ctx.db.doc(paths.location(familyId, ctx.uid)).get(),
    ]);
    families.push({
      familyId,
      name: plain(family.get('name')),
      member: member.exists ? plain(member.data()) : null,
      sharingConsent: consent.exists ? plain(consent.data()) : null,
      lastLocation: location.exists ? plain(location.data()) : null,
    });
  }

  return {
    schema: EXPORT_SCHEMA,
    generatedAt: ctx.now.toISOString(),
    data: {
      account: { uid: ctx.uid, ...account },
      profile: profile.exists ? plain(profile.data()) : null,
      devices: devices.docs.map((d) => ({
        platform: plain(d.get('platform')),
        updatedAt: plain(d.get('updatedAt')),
      })),
      families,
      events: events.docs.map((d) => ({
        familyId: familyOf(d.ref.path),
        id: d.id,
        // `targetUid` es otra persona (p. ej., a quien quitó de la familia).
        ...withoutKeys(plain(d.data()), ['actorUid', 'targetUid', 'expireAt']),
      })),
      emergencies: emergencies.docs.map((d) => ({
        familyId: familyOf(d.ref.path),
        id: d.id,
        // Las confirmaciones son de otras personas: solo cuántas hubo.
        ...withoutKeys(plain(d.data()), ['uid', 'acks', 'expireAt', 'notifyStartedAt']),
        acknowledgements: Object.keys((d.get('acks') as object | undefined) ?? {}).length,
      })),
    },
  };
}

/** `families/{id}/...` → `id`. */
function familyOf(path: string): string {
  return path.split('/')[1]!;
}

function withoutKeys(value: Json, keys: string[]): { [key: string]: Json } {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return {};
  return Object.fromEntries(Object.entries(value).filter(([k]) => !keys.includes(k)));
}

/** Convierte un valor de Firestore en JSON (fechas en ISO 8601, UTC). */
function plain(value: unknown): Json {
  if (value === undefined || value === null) return null;
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map(plain);
  if (typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, plain(v)]));
  }
  if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
    return value;
  }
  return null;
}
