import { HttpsError } from 'firebase-functions/v2/https';
import { Timestamp } from 'firebase-admin/firestore';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { exportMyData, EXPORT_SCHEMA, type AccountReader } from '../../src/export.js';
import { acceptInvitation, createFamily, createInvitation, leaveFamily, removeMember } from '../../src/families.js';
import { clearEmulator, closeApps, ctxFor, emulatorDb, TestClock } from './helpers.js';

const db = emulatorDb();
let clock: TestClock;
const as = (uid: string) => ctxFor(db, uid, clock);
const accounts: AccountReader = {
  async account(uid) {
    return { email: `${uid}@example.com`, createdAt: '2025-12-01T00:00:00.000Z' };
  },
};

let familyId: string;
let formerId: string;

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
  ({ familyId } = await createFamily(as('ana'), { name: 'Familia Rojas' }));
  ({ familyId: formerId } = await createFamily(as('luis'), { name: 'Antigua' }));
  for (const id of [familyId, formerId]) {
    const owner = id === familyId ? 'ana' : 'luis';
    const { code } = await createInvitation(as(owner), { familyId: id });
    await acceptInvitation(as(owner === 'ana' ? 'luis' : 'ana'), { code });
  }
  // Ana salió de la familia de Luis: sus datos allí también son suyos.
  await leaveFamily(as('ana'), { familyId: formerId });

  const ts = Timestamp.fromDate(clock.now);
  await db.doc('users/ana').set({ displayName: 'Ana', createdAt: ts });
  await db.doc('users/ana/devices/d1').set({ token: 'tok-secreto', platform: 'ios', updatedAt: ts });
  await db.doc(`families/${familyId}/consents/ana`).set({ state: 'sharing', precision: 'exact', updatedAt: ts });
  await db.doc(`families/${familyId}/locations/ana`).set({ lat: 4.61, lng: -74.07, accuracyM: 10, capturedAt: ts });
  await db.doc(`families/${familyId}/locations/luis`).set({ lat: 6.25, lng: -75.56, accuracyM: 10, capturedAt: ts });
  await db.doc(`families/${familyId}/events/e1`).set({
    type: 'checkIn', actorUid: 'ana', kind: 'ok', message: 'Llegué', createdAt: ts, expireAt: ts,
  });
  await db.doc(`families/${formerId}/events/e2`).set({
    type: 'checkIn', actorUid: 'ana', kind: 'needHelp', createdAt: ts, expireAt: ts,
  });
  await db.doc(`families/${familyId}/events/e3`).set({
    type: 'checkIn', actorUid: 'luis', kind: 'ok', message: 'De Luis', createdAt: ts, expireAt: ts,
  });
  await db.doc(`families/${familyId}/emergencies/a1`).set({
    uid: 'ana', createdAt: ts, lat: 4.61, lng: -74.07, notifiedCount: 1, acks: { luis: ts }, expireAt: ts,
  });
});

afterAll(closeApps);

describe('exportMyData', () => {
  it('reúne los datos de la persona en todas sus familias', async () => {
    const result = await exportMyData(as('ana'), accounts);
    expect(result.schema).toBe(EXPORT_SCHEMA);
    const data = result.data as Record<string, any>;
    expect(data.account).toEqual({ uid: 'ana', email: 'ana@example.com', createdAt: '2025-12-01T00:00:00.000Z' });
    expect(data.profile.displayName).toBe('Ana');
    expect(data.profile.createdAt).toBe(clock.now.toISOString());
    expect(data.families).toHaveLength(1);
    expect(data.families[0]).toMatchObject({
      familyId,
      name: 'Familia Rojas',
      sharingConsent: { state: 'sharing', precision: 'exact' },
      lastLocation: { lat: 4.61, lng: -74.07 },
    });
    expect(data.families[0].member.role).toBe('owner');
    // Incluye sus check-ins de la familia de la que salió.
    const checkIns = data.events.filter((e: { type: string }) => e.type === 'checkIn');
    expect(checkIns.map((e: { id: string }) => e.id).sort()).toEqual(['e1', 'e2']);
    // También sus entradas y salidas de familias.
    expect(data.events.filter((e: { type: string }) => e.type === 'membership').length).toBeGreaterThan(0);
    expect(data.events.find((e: { id: string }) => e.id === 'e1')).toMatchObject({
      familyId, type: 'checkIn', kind: 'ok', message: 'Llegué',
    });
    expect(data.emergencies).toEqual([
      expect.objectContaining({ familyId, id: 'a1', lat: 4.61, notifiedCount: 1, acknowledgements: 1 }),
    ]);
  });

  it('no incluye tokens ni datos de otras personas', async () => {
    const text = JSON.stringify(await exportMyData(as('ana'), accounts));
    expect(text).not.toContain('tok-secreto');
    expect(text).not.toContain('De Luis');
    expect(text).not.toContain('6.25');
    expect(text).not.toContain('"luis"');
    expect(text).toContain('"platform":"ios"');
  });

  it('al quitar a alguien, el evento no lleva el uid de esa persona', async () => {
    await removeMember(as('ana'), { familyId, uid: 'luis' });
    const data = (await exportMyData(as('ana'), accounts)).data as Record<string, any>;
    expect(data.events.some((e: { change?: string }) => e.change === 'removed')).toBe(true);
    expect(JSON.stringify(data)).not.toContain('"luis"');
  });

  it('limita a 3 exportaciones por hora', async () => {
    for (let i = 0; i < 3; i++) await exportMyData(as('ana'), accounts);
    expect(await reason(exportMyData(as('ana'), accounts))).toBe('rate-limited');
    clock.advance(3600 * 1000 + 1);
    await exportMyData(as('ana'), accounts);
  });
});
