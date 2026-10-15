// Conformidad de las funciones con docs/architecture/05-api-backend.md,
// ejecutadas contra el emulador de Firestore.
import { HttpsError } from 'firebase-functions/v2/https';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { deleteAccount } from '../../src/account.js';
import {
  acceptInvitation,
  createFamily,
  createInvitation,
  hashCode,
  leaveFamily,
  removeMember,
} from '../../src/families.js';
import { clearEmulator, closeApps, ctxFor, dumpAll, emulatorDb, TestClock } from './helpers.js';

const db = emulatorDb();
let clock: TestClock;
const as = (uid: string) => ctxFor(db, uid, clock);

async function reason(promise: Promise<unknown>): Promise<string> {
  try {
    await promise;
  } catch (error) {
    if (error instanceof HttpsError) return (error.details as { reason: string }).reason;
    throw error;
  }
  throw new Error('Se esperaba un error');
}

async function setupFamily(): Promise<string> {
  await db.doc('users/ana').set({ displayName: 'Ana' });
  await db.doc('users/luis').set({ displayName: 'Luis' });
  const { familyId } = await createFamily(as('ana'), { name: 'Familia Uno' });
  return familyId;
}

async function join(familyId: string, uid: string, inviter = 'ana'): Promise<void> {
  const { code } = await createInvitation(as(inviter), { familyId });
  await acceptInvitation(as(uid), { code });
}

beforeEach(async () => {
  clock = new TestClock();
  await clearEmulator();
});

afterAll(closeApps);

describe('createFamily', () => {
  it('crea la familia, la membresía owner, el consentimiento y la auditoría', async () => {
    const familyId = await setupFamily();
    const family = await db.doc(`families/${familyId}`).get();
    expect(family.get('name')).toBe('Familia Uno');
    expect(family.get('memberCount')).toBe(1);
    expect((await db.doc(`families/${familyId}/members/ana`).get()).get('role')).toBe('owner');
    expect((await db.doc(`families/${familyId}/members/ana`).get()).get('displayName')).toBe('Ana');
    expect((await db.doc(`users/ana/memberships/${familyId}`).get()).get('familyName')).toBe('Familia Uno');
    expect((await db.doc(`families/${familyId}/consents/ana`).get()).get('state')).toBe('notConfigured');
    expect((await db.collection(`families/${familyId}/audit`).get()).size).toBe(1);
  });

  it('valida el nombre y limita a 5 familias por persona', async () => {
    expect(await reason(createFamily(as('ana'), { name: '  ' }))).toBe('name-required');
    expect(await reason(createFamily(as('ana'), { name: 'x'.repeat(41) }))).toBe('family-name-invalid');
    expect(await reason(createFamily(as('ana'), { name: '\u200B\u200B' }))).toBe('family-name-invalid');
    for (let i = 0; i < 5; i++) await createFamily(as('ana'), { name: `F${i}` });
    expect(await reason(createFamily(as('ana'), { name: 'Sexta' }))).toBe('too-many-families');
  });
});

describe('invitaciones', () => {
  it('solo owner o admin invitan; el código no se guarda en claro', async () => {
    const familyId = await setupFamily();
    const invitation = await createInvitation(as('ana'), { familyId });
    expect(invitation.code).toMatch(/^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{10}$/);
    expect(invitation.maxUses).toBe(1);
    expect(invitation.expiresAt - clock.now.getTime()).toBe(48 * 3600 * 1000);
    expect((await db.doc(`invitations/${hashCode(invitation.code)}`).get()).exists).toBe(true);
    expect(await dumpAll(db)).not.toContain(invitation.code);

    await join(familyId, 'luis');
    expect(await reason(createInvitation(as('luis'), { familyId }))).toBe('not-allowed');
    expect(await reason(createInvitation(as('mallory'), { familyId }))).toBe('not-allowed');
  });

  it('acepta el código con guiones, espacios y minúsculas', async () => {
    const familyId = await setupFamily();
    const { code } = await createInvitation(as('ana'), { familyId });
    const typed = ` ${code.slice(0, 5).toLowerCase()}-${code.slice(5)} `;
    expect(await acceptInvitation(as('luis'), { code: typed })).toEqual({ familyId });
    expect((await db.doc(`families/${familyId}`).get()).get('memberCount')).toBe(2);
    expect((await db.doc(`families/${familyId}/members/luis`).get()).get('role')).toBe('member');
    const events = await db.collection(`families/${familyId}/events`).get();
    expect(events.docs.map((d) => d.get('change'))).toContain('joined');
  });

  it('un código usado, vencido o inexistente da siempre el mismo error', async () => {
    const familyId = await setupFamily();
    const used = await createInvitation(as('ana'), { familyId });
    await acceptInvitation(as('luis'), { code: used.code });
    const expired = await createInvitation(as('ana'), { familyId });
    clock.advance(48 * 3600 * 1000 + 1);
    expect(await reason(acceptInvitation(as('mallory'), { code: used.code }))).toBe('invitation-invalid');
    expect(await reason(acceptInvitation(as('mallory'), { code: expired.code }))).toBe('invitation-invalid');
    expect(await reason(acceptInvitation(as('mallory'), { code: 'ABCDEFGHJK' }))).toBe('invitation-invalid');
    expect((await db.doc(`invitations/${hashCode(used.code)}`).get()).get('status')).toBe('exhausted');
  });

  it('los intentos fallidos cuentan para el límite (contra fuerza bruta)', async () => {
    const familyId = await setupFamily();
    for (let i = 0; i < 10; i++) {
      expect(await reason(acceptInvitation(as('mallory'), { code: `ZZZZZZZZ${i}2` }))).toBe('invitation-invalid');
    }
    const { code } = await createInvitation(as('ana'), { familyId });
    expect(await reason(acceptInvitation(as('mallory'), { code }))).toBe('rate-limited');
    clock.advance(3600 * 1000 + 1);
    expect(await acceptInvitation(as('mallory'), { code })).toEqual({ familyId });
  });

  it('rechaza unirse dos veces y familias llenas', async () => {
    const familyId = await setupFamily();
    await join(familyId, 'luis');
    const again = await createInvitation(as('ana'), { familyId });
    expect(await reason(acceptInvitation(as('luis'), { code: again.code }))).toBe('already-member');
    await db.doc(`families/${familyId}`).update({ memberCount: 12 });
    expect(await reason(acceptInvitation(as('mallory'), { code: again.code }))).toBe('family-full');
  });

  it('limita a 10 invitaciones activas por familia', async () => {
    const familyId = await setupFamily();
    for (let i = 0; i < 10; i++) await createInvitation(as('ana'), { familyId });
    expect(await reason(createInvitation(as('ana'), { familyId }))).toBe('too-many-invitations');
  });
});

describe('salir y expulsar', () => {
  it('salir borra membresía, ubicación y consentimiento', async () => {
    const familyId = await setupFamily();
    await join(familyId, 'luis');
    await db.doc(`families/${familyId}/locations/luis`).set({ lat: 1, lng: 1 });
    await leaveFamily(as('luis'), { familyId });
    for (const path of [
      `families/${familyId}/members/luis`,
      `users/luis/memberships/${familyId}`,
      `families/${familyId}/locations/luis`,
      `families/${familyId}/consents/luis`,
    ]) {
      expect((await db.doc(path).get()).exists, path).toBe(false);
    }
    expect((await db.doc(`families/${familyId}`).get()).get('memberCount')).toBe(1);
  });

  it('si sale el owner hereda el más antiguo; si sale el último, se borra todo', async () => {
    const familyId = await setupFamily();
    clock.advance(1000);
    await join(familyId, 'luis');
    await leaveFamily(as('ana'), { familyId });
    expect((await db.doc(`families/${familyId}/members/luis`).get()).get('role')).toBe('owner');
    expect((await db.doc(`users/luis/memberships/${familyId}`).get()).get('role')).toBe('owner');
    await leaveFamily(as('luis'), { familyId });
    expect((await db.doc(`families/${familyId}`).get()).exists).toBe(false);
    expect((await db.collection(`families/${familyId}/events`).get()).size).toBe(0);
    expect((await db.collection(`families/${familyId}/audit`).get()).size).toBe(0);
  });

  it('matriz de permisos de expulsión', async () => {
    const familyId = await setupFamily();
    await join(familyId, 'luis');
    await join(familyId, 'sofia');
    await db.doc(`families/${familyId}/members/luis`).update({ role: 'admin' });
    // Un member no expulsa; nadie se expulsa a sí mismo; un admin no expulsa al owner.
    expect(await reason(removeMember(as('sofia'), { familyId, uid: 'luis' }))).toBe('not-allowed');
    expect(await reason(removeMember(as('ana'), { familyId, uid: 'ana' }))).toBe('not-allowed');
    expect(await reason(removeMember(as('luis'), { familyId, uid: 'ana' }))).toBe('not-allowed');
    expect(await reason(removeMember(as('mallory'), { familyId, uid: 'sofia' }))).toBe('not-allowed');
    expect(await reason(removeMember(as('ana'), { familyId, uid: 'nadie' }))).toBe('not-member');
    await removeMember(as('luis'), { familyId, uid: 'sofia' });
    await removeMember(as('ana'), { familyId, uid: 'luis' });
    const events = await db.collection(`families/${familyId}/events`).where('change', '==', 'removed').get();
    expect(events.docs.map((d) => d.get('targetUid')).sort()).toEqual(['luis', 'sofia']);
  });
});

describe('deleteAccount', () => {
  it('sale de todas las familias, borra el perfil y el usuario de Auth', async () => {
    const familyId = await setupFamily();
    await join(familyId, 'luis');
    await db.doc('users/luis/devices/d1').set({ token: 't', platform: 'ios' });
    const deleted: string[] = [];
    await deleteAccount(as('luis'), { deleteUser: async (uid) => void deleted.push(uid) });
    expect(deleted).toEqual(['luis']);
    expect((await db.doc('users/luis').get()).exists).toBe(false);
    expect((await db.doc('users/luis/devices/d1').get()).exists).toBe(false);
    expect((await db.doc(`families/${familyId}/members/luis`).get()).exists).toBe(false);
    expect((await db.doc(`families/${familyId}`).get()).exists).toBe(true);
  });

  it('borra sus check-ins, quita coordenadas de sus alertas y anonimiza la auditoría', async () => {
    const familyId = await setupFamily();
    await join(familyId, 'luis');
    const events = db.collection(`families/${familyId}/events`);
    await events.doc('c1').set({ type: 'checkIn', actorUid: 'luis', kind: 'ok', message: 'Llegué', lat: 1, lng: 2 });
    await events.doc('g1').set({ type: 'geofence', actorUid: 'luis', geofenceName: 'Colegio' });
    await events.doc('c2').set({ type: 'checkIn', actorUid: 'ana', kind: 'ok' });
    await db.doc(`families/${familyId}/emergencies/a1`).set({ uid: 'luis', lat: 1, lng: 2, accuracyM: 5, acks: {} });
    await db.doc(`families/${familyId}/emergencies/a2`).set({ uid: 'ana', lat: 3, lng: 4, acks: {} });

    await deleteAccount(as('luis'), { deleteUser: async () => {} });

    expect((await events.doc('c1').get()).exists).toBe(false);
    expect((await events.doc('g1').get()).exists).toBe(false);
    expect((await events.doc('c2').get()).exists).toBe(true);
    const alert = (await db.doc(`families/${familyId}/emergencies/a1`).get()).data();
    expect(alert).toEqual({ uid: 'luis', acks: {} });
    expect((await db.doc(`families/${familyId}/emergencies/a2`).get()).get('lat')).toBe(3);
    const audit = await db.collection(`families/${familyId}/audit`).get();
    const ids = audit.docs.flatMap((d) => [d.get('actorUid'), d.get('targetUid')]);
    expect(ids).not.toContain('luis');
    expect(ids).toContain('deleted-user');
    // Ningún mensaje ni lugar de la cuenta borrada queda en la base.
    const all = await dumpAll(db);
    expect(all).not.toContain('Llegué');
    expect(all).not.toContain('Colegio');
  });
});

describe('retención (TTL sobre expireAt)', () => {
  const days = (ts: { toMillis(): number }) => Math.round((ts.toMillis() - clock.now.getTime()) / 864e5);

  it('auditoría a 180 días, eventos a 30 e invitaciones a 7 días tras vencer', async () => {
    const familyId = await setupFamily();
    const { code } = await createInvitation(as('ana'), { familyId });
    await acceptInvitation(as('luis'), { code });
    const audit = await db.collection(`families/${familyId}/audit`).get();
    expect(audit.size).toBeGreaterThan(0);
    for (const doc of audit.docs) expect(days(doc.get('expireAt'))).toBe(180);
    const events = await db.collection(`families/${familyId}/events`).get();
    for (const doc of events.docs) expect(days(doc.get('expireAt'))).toBe(30);
    const invitation = await db.doc(`invitations/${hashCode(code)}`).get();
    expect(days(invitation.get('expireAt'))).toBe(2 + 7);
  });
});
