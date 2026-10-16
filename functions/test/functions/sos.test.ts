import { HttpsError } from 'firebase-functions/v2/https';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { acceptInvitation, createFamily, createInvitation } from '../../src/families.js';
import { raiseSos, type Notifier } from '../../src/sos.js';
import { clearEmulator, closeApps, ctxFor, emulatorDb, TestClock } from './helpers.js';

const db = emulatorDb();
let clock: TestClock;
const as = (uid: string) => ctxFor(db, uid, clock);

class FakeNotifier implements Notifier {
  calls: { tokens: string[]; data: unknown }[] = [];
  accept = (tokens: string[]) => tokens.length;
  invalid: string[] = [];
  async notifySos(tokens: string[], data: { familyId: string; alertId: string }) {
    this.calls.push({ tokens, data });
    return { accepted: this.accept(tokens), invalidTokens: this.invalid };
  }
}

async function reason(promise: Promise<unknown>): Promise<string> {
  try {
    await promise;
  } catch (error) {
    if (error instanceof HttpsError) return (error.details as { reason: string }).reason;
    throw error;
  }
  throw new Error('Se esperaba un error');
}

let familyId: string;
let notifier: FakeNotifier;

beforeEach(async () => {
  clock = new TestClock();
  notifier = new FakeNotifier();
  await clearEmulator();
  ({ familyId } = await createFamily(as('ana'), { name: 'Familia' }));
  for (const uid of ['luis', 'sofia']) {
    const { code } = await createInvitation(as('ana'), { familyId });
    await acceptInvitation(as(uid), { code });
  }
  await db.doc('users/ana/devices/a1').set({ token: 'tok-ana', platform: 'android' });
  await db.doc('users/sofia/devices/s1').set({ token: 'tok-sofia', platform: 'ios' });
  await db.doc('users/luis/devices/l1').set({ token: 'tok-luis', platform: 'ios' });
});

afterAll(closeApps);

describe('raiseSos', () => {
  it('registra la alerta y notifica solo a los demás integrantes', async () => {
    const result = await raiseSos(as('luis'), { familyId, alertId: 'sos-1', lat: 4.6, lng: -74.1, accuracyM: 12 }, notifier);
    expect(result).toEqual({ alertId: 'sos-1', notifiedCount: 2, alreadyExisted: false });
    expect(notifier.calls).toHaveLength(1);
    expect(notifier.calls[0]!.tokens.sort()).toEqual(['tok-ana', 'tok-sofia']);
    // El payload de la notificación no lleva ubicación.
    expect(JSON.stringify(notifier.calls[0]!.data)).not.toMatch(/4\.6|74\.1/);
    const alert = await db.doc(`families/${familyId}/emergencies/sos-1`).get();
    expect(alert.get('uid')).toBe('luis');
    expect(alert.get('notifiedCount')).toBe(2);
    expect(alert.get('acks')).toEqual({});
    expect(alert.get('resolvedAt')).toBeNull();
    const events = await db.collection(`families/${familyId}/events`).where('type', '==', 'sos').get();
    expect(events.size).toBe(1);
  });

  it('la alerta, su evento y su auditoría vencen a los 90/90/180 días', async () => {
    await raiseSos(as('luis'), { familyId, alertId: 'a-ttl' }, notifier);
    const days = (ts: { toMillis(): number }) => Math.round((ts.toMillis() - clock.now.getTime()) / 864e5);
    expect(days((await db.doc(`families/${familyId}/emergencies/a-ttl`).get()).get('expireAt'))).toBe(90);
    const event = await db.collection(`families/${familyId}/events`).where('alertId', '==', 'a-ttl').get();
    expect(days(event.docs[0]!.get('expireAt'))).toBe(90);
    const audit = await db.collection(`families/${familyId}/audit`).where('action', '==', 'raiseSos').get();
    expect(days(audit.docs[0]!.get('expireAt'))).toBe(180);
  });

  it('es idempotente: un reintento no duplica la alerta ni la notificación', async () => {
    await raiseSos(as('luis'), { familyId, alertId: 'sos-1' }, notifier);
    const again = await raiseSos(as('luis'), { familyId, alertId: 'sos-1' }, notifier);
    expect(again).toEqual({ alertId: 'sos-1', notifiedCount: 2, alreadyExisted: true });
    expect(notifier.calls).toHaveLength(1);
    const events = await db.collection(`families/${familyId}/events`).where('type', '==', 'sos').get();
    expect(events.size).toBe(1);
  });

  it('si el envío falla, responde transitorio y el reintento completa la notificación', async () => {
    notifier.accept = () => {
      throw new Error('FCM caído');
    };
    expect(await reason(raiseSos(as('luis'), { familyId, alertId: 'sos-1' }, notifier))).toBe(
      'notification-unavailable',
    );
    const pending = await db.doc(`families/${familyId}/emergencies/sos-1`).get();
    // La alerta existe; el conteo sigue desconocido (no se finge un 0).
    expect(pending.exists).toBe(true);
    expect(pending.get('notifiedCount')).toBeNull();

    notifier.accept = (tokens) => tokens.length;
    const retry = await raiseSos(as('luis'), { familyId, alertId: 'sos-1' }, notifier);
    expect(retry).toEqual({ alertId: 'sos-1', notifiedCount: 2, alreadyExisted: true });
    const events = await db.collection(`families/${familyId}/events`).where('type', '==', 'sos').get();
    expect(events.size).toBe(1);
  });

  it('un reintento simultáneo no notifica dos veces mientras dura el lease', async () => {
    // Simula un primer intento que tomó el lease y aún no termina.
    await raiseSos(as('luis'), { familyId, alertId: 'sos-1' }, notifier);
    await db.doc(`families/${familyId}/emergencies/sos-1`).update({
      notifiedCount: null,
      notifyStartedAt: clock.now,
    });
    const concurrent = await raiseSos(as('luis'), { familyId, alertId: 'sos-1' }, notifier);
    expect(concurrent.notifiedCount).toBeNull();
    expect(notifier.calls).toHaveLength(1);
    clock.advance(61 * 1000);
    const afterLease = await raiseSos(as('luis'), { familyId, alertId: 'sos-1' }, notifier);
    expect(afterLease.notifiedCount).toBe(2);
    expect(notifier.calls).toHaveLength(2);
  });

  it('sin dispositivos registrados informa 0 notificados', async () => {
    await db.doc('users/ana/devices/a1').delete();
    await db.doc('users/sofia/devices/s1').delete();
    const result = await raiseSos(as('luis'), { familyId, alertId: 'sos-1' }, notifier);
    expect(result.notifiedCount).toBe(0);
    expect(notifier.calls).toHaveLength(0);
  });

  it('el conteo refleja los mensajes ACEPTADOS, no los enviados', async () => {
    notifier.accept = () => 1;
    expect((await raiseSos(as('luis'), { familyId, alertId: 'sos-1' }, notifier)).notifiedCount).toBe(1);
  });

  it('olvida los dispositivos cuyo token el proveedor declara inválido', async () => {
    notifier.invalid = ['tok-sofia'];
    notifier.accept = (tokens) => tokens.length - 1;
    const result = await raiseSos(as('luis'), { familyId, alertId: 'inv-1' }, notifier);
    expect(result.notifiedCount).toBe(1);
    expect((await db.doc('users/sofia/devices/s1').get()).exists).toBe(false);
    expect((await db.doc('users/ana/devices/a1').get()).exists).toBe(true);
    // La siguiente alerta ya no lo intenta.
    notifier.invalid = [];
    notifier.accept = (tokens) => tokens.length;
    await raiseSos(as('luis'), { familyId, alertId: 'inv-2' }, notifier);
    expect(notifier.calls.at(-1)!.tokens).toEqual(['tok-ana']);
  });

  it('no olvida un dispositivo que renovó su token mientras se enviaba', async () => {
    notifier.invalid = ['tok-sofia'];
    const original = notifier.notifySos.bind(notifier);
    notifier.notifySos = async (tokens, data) => {
      // El teléfono de Sofía renueva su token en paralelo al envío.
      await db.doc('users/sofia/devices/s1').set({ token: 'tok-sofia-nuevo', platform: 'ios' });
      return original(tokens, data);
    };
    await raiseSos(as('luis'), { familyId, alertId: 'race-1' }, notifier);
    expect((await db.doc('users/sofia/devices/s1').get()).get('token')).toBe('tok-sofia-nuevo');
  });

  it('rechaza a quien no es integrante y alertId de otra persona', async () => {
    expect(await reason(raiseSos(as('mallory'), { familyId, alertId: 'x' }, notifier))).toBe('not-member');
    await raiseSos(as('luis'), { familyId, alertId: 'sos-1' }, notifier);
    expect(await reason(raiseSos(as('ana'), { familyId, alertId: 'sos-1' }, notifier))).toBe('not-allowed');
  });

  it('limita a 5 alertas por hora', async () => {
    for (let i = 0; i < 5; i++) await raiseSos(as('luis'), { familyId, alertId: `sos-${i}` }, notifier);
    expect(await reason(raiseSos(as('luis'), { familyId, alertId: 'sos-6' }, notifier))).toBe('rate-limited');
    clock.advance(3600 * 1000 + 1);
    await raiseSos(as('luis'), { familyId, alertId: 'sos-7' }, notifier);
  });

  it('la ubicación sigue el consentimiento VIGENTE: exacta, aproximada o ninguna', async () => {
    const consent = (state: string, precision: string) =>
      db.doc(`families/${familyId}/consents/luis`).set({ state, precision });
    const point = { lat: 4.61734, lng: -74.07291, accuracyM: 12 };

    await consent('sharing', 'exact');
    await raiseSos(as('luis'), { familyId, alertId: 'c-exacta', ...point }, notifier);
    expect((await db.doc(`families/${familyId}/emergencies/c-exacta`).get()).data()).toMatchObject(point);

    await consent('sharing', 'approximate');
    await raiseSos(as('luis'), { familyId, alertId: 'c-aprox', ...point }, notifier);
    expect((await db.doc(`families/${familyId}/emergencies/c-aprox`).get()).data()).toMatchObject({
      lat: 4.62, lng: -74.07, accuracyM: 1000,
    });

    // Pausó después de preparar la alerta: el reintento no publica nada.
    await consent('paused', 'exact');
    await raiseSos(as('luis'), { familyId, alertId: 'c-pausa', ...point }, notifier);
    const paused = (await db.doc(`families/${familyId}/emergencies/c-pausa`).get()).data()!;
    expect(paused.lat).toBeUndefined();
    expect(paused.accuracyM).toBeUndefined();
  });

  it('ignora coordenadas fuera de rango y valida tipos', async () => {
    // Comparte en exacta: lo único que descarta la ubicación es el rango.
    await db.doc(`families/${familyId}/consents/luis`).set({ state: 'sharing', precision: 'exact' });
    await raiseSos(as('luis'), { familyId, alertId: 'sos-1', lat: 200, lng: 10 }, notifier);
    const alert = await db.doc(`families/${familyId}/emergencies/sos-1`).get();
    expect(alert.get('lat')).toBeUndefined();
    expect(await reason(raiseSos(as('luis'), { familyId, alertId: 'sos-2', lat: 'x' }, notifier))).toBe('lat-invalid');
  });
});
