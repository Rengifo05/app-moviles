import { HttpsError } from 'firebase-functions/v2/https';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { acceptInvitation, createFamily, createInvitation } from '../../src/families.js';
import { createGeofence } from '../../src/geofences.js';
import { clearEmulator, closeApps, ctxFor, emulatorDb, TestClock } from './helpers.js';

const db = emulatorDb();
let clock: TestClock;
const as = (uid: string) => ctxFor(db, uid, clock);
let familyId: string;

// Coordenadas sintéticas.
const zone = (geofenceId: string, extra: Record<string, unknown> = {}) => ({
  familyId, geofenceId, name: 'Colegio', lat: 4.65, lng: -74.05, radiusM: 300, ...extra,
});

async function reason(promise: Promise<unknown>): Promise<string | undefined> {
  try {
    await promise;
    return undefined;
  } catch (error) {
    return ((error as HttpsError).details as { reason?: string } | undefined)?.reason;
  }
}

beforeEach(async () => {
  await clearEmulator();
  clock = new TestClock();
  ({ familyId } = await createFamily(as('ana'), { name: 'Familia' }));
  const { code } = await createInvitation(as('ana'), { familyId });
  await acceptInvitation(as('luis'), { code });
});

afterAll(closeApps);

describe('createGeofence', () => {
  it('crea la zona con versión 1 y su autor', async () => {
    expect(await createGeofence(as('ana'), zone('z1'))).toEqual({ geofenceId: 'z1', alreadyExisted: false });
    const doc = (await db.doc(`families/${familyId}/geofences/z1`).get()).data()!;
    expect(doc).toMatchObject({ name: 'Colegio', lat: 4.65, lng: -74.05, radiusM: 300, createdBy: 'ana', version: 1 });
    expect(doc.updatedAt).toBeDefined();
  });

  it('es idempotente: el reintento no crea otra ni cuenta dos veces', async () => {
    await createGeofence(as('ana'), zone('z1'));
    expect(await createGeofence(as('ana'), zone('z1'))).toEqual({ geofenceId: 'z1', alreadyExisted: true });
    expect((await db.collection(`families/${familyId}/geofences`).get()).size).toBe(1);
  });

  it('un id ajeno ya usado es un conflicto', async () => {
    await db.doc(`families/${familyId}/members/luis`).update({ role: 'admin' });
    await createGeofence(as('ana'), zone('z1'));
    expect(await reason(createGeofence(as('luis'), zone('z1')))).toBe('conflict');
  });

  it('aplica el máximo de 10 zonas por familia', async () => {
    for (let i = 0; i < 10; i++) await createGeofence(as('ana'), zone(`z${i}`));
    expect(await reason(createGeofence(as('ana'), zone('z10')))).toBe('too-many-geofences');
    // El reintento de una que ya existe sigue funcionando en el límite.
    expect((await createGeofence(as('ana'), zone('z3'))).alreadyExisted).toBe(true);
  });

  it('solo owner o admin, y solo integrantes', async () => {
    expect(await reason(createGeofence(as('luis'), zone('z1')))).toBe('not-allowed');
    expect(await reason(createGeofence(as('mallory'), zone('z1')))).toBe('not-member');
  });

  it('valida nombre, coordenadas, radio e id', async () => {
    expect(await reason(createGeofence(as('ana'), zone('z1', { name: '​​' })))).toBe('geofence-name-invalid');
    expect(await reason(createGeofence(as('ana'), zone('z1', { name: 'x'.repeat(41) })))).toBe('name-required');
    expect(await reason(createGeofence(as('ana'), zone('z1', { lat: 91 })))).toBe('lat-invalid');
    expect(await reason(createGeofence(as('ana'), zone('z1', { lng: 'x' })))).toBe('lng-invalid');
    expect(await reason(createGeofence(as('ana'), zone('z1', { radiusM: 50 })))).toBe('radius-invalid');
    expect(await reason(createGeofence(as('ana'), zone('z1', { radiusM: 2500 })))).toBe('radius-invalid');
    expect(await reason(createGeofence(as('ana'), zone('a/b')))).toBe('geofence-id-invalid');
  });
});
