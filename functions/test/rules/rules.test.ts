// Pruebas de las reglas de Firestore contra el emulador.
// Matriz: docs/architecture/02-modelo-de-datos.md («Matriz de acceso»).
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
  type Firestore,
} from 'firebase/firestore';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';

// RULES_PATH permite probar reglas mutadas (scripts/mutate_rules.mjs).
const RULES =
  process.env.RULES_PATH ?? fileURLToPath(new URL('../../../firestore/firestore.rules', import.meta.url));
let env: RulesTestEnvironment;

// Datos sintéticos: dos familias aisladas y un usuario sin familia.
// f1: ana (owner), luis (member). f2: eve (owner). mallory: sin familia.
const T0 = Timestamp.fromMillis(Date.UTC(2026, 0, 1, 12));

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-nexo',
    firestore: { rules: readFileSync(RULES, 'utf8'), host: '127.0.0.1', port: 8085 },
  });
});

afterAll(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore() as unknown as Firestore;
    const set = (path: string, data: Record<string, unknown>) => setDoc(doc(db, path), data);
    await set('families/f1', { name: 'Familia Uno', createdBy: 'ana', createdAt: T0, memberCount: 2 });
    await set('families/f1/members/ana', { uid: 'ana', displayName: 'Ana', role: 'owner', joinedAt: T0 });
    await set('families/f1/members/luis', { uid: 'luis', displayName: 'Luis', role: 'member', joinedAt: T0 });
    await set('families/f1/consents/ana', { state: 'sharing', precision: 'exact', updatedAt: T0 });
    await set('families/f1/consents/luis', { state: 'paused', precision: 'exact', updatedAt: T0 });
    await set('families/f1/locations/ana', {
      lat: 4.6, lng: -74.08, accuracyM: 20, capturedAt: T0, receivedAt: T0, approximate: false,
    });
    await set('families/f1/geofences/g1', {
      name: 'Casa', lat: 4.6, lng: -74.08, radiusM: 200, createdBy: 'ana', version: 1, updatedAt: T0,
    });
    await set('families/f1/emergencies/sos1', {
      uid: 'luis', createdAt: T0, notifiedCount: 1, acks: {}, resolvedAt: null,
    });
    await set('families/f1/audit/a1', { action: 'createFamily', actorUid: 'ana', createdAt: T0 });
    await set('families/f2', { name: 'Familia Dos', createdBy: 'eve', createdAt: T0, memberCount: 1 });
    await set('families/f2/members/eve', { uid: 'eve', displayName: 'Eve', role: 'owner', joinedAt: T0 });
    await set('families/f2/locations/eve', {
      lat: 6.2, lng: -75.5, accuracyM: 10, capturedAt: T0, receivedAt: T0, approximate: false,
    });
    await set('invitations/hash1', { familyId: 'f1', status: 'active', uses: 0, maxUses: 1 });
    await set('users/ana/memberships/f1', { familyId: 'f1', familyName: 'Familia Uno', role: 'owner' });
  });
});

// rules-unit-testing devuelve el tipo «compat»; se usa con la API modular.
const as = (uid: string) => env.authenticatedContext(uid).firestore() as unknown as Firestore;
const anon = () => env.unauthenticatedContext().firestore() as unknown as Firestore;

const location = (capturedAt: Timestamp, extra: Record<string, unknown> = {}) => ({
  lat: 4.61, lng: -74.07, accuracyM: 15, capturedAt, receivedAt: serverTimestamp(), approximate: false,
  ...extra,
});

describe('aislamiento entre familias', () => {
  const f1Paths = [
    'families/f1',
    'families/f1/members/ana',
    'families/f1/consents/ana',
    'families/f1/locations/ana',
    'families/f1/geofences/g1',
    'families/f1/emergencies/sos1',
  ];

  it.each(f1Paths)('sin sesión no se lee %s', async (path) => {
    await assertFails(getDoc(doc(anon(), path)));
  });

  it.each(f1Paths)('un usuario de otra familia no lee %s', async (path) => {
    await assertFails(getDoc(doc(as('eve'), path)));
  });

  it.each(f1Paths)('un usuario sin familia no lee %s', async (path) => {
    await assertFails(getDoc(doc(as('mallory'), path)));
  });

  it.each(f1Paths)('un integrante sí lee %s', async (path) => {
    await assertSucceeds(getDoc(doc(as('luis'), path)));
  });

  it('un usuario de otra familia no lista sus ubicaciones', async () => {
    await assertFails(getDocs(collection(as('eve'), 'families/f1/locations')));
  });

  it('un usuario de otra familia no escribe ubicaciones en ella', async () => {
    await assertFails(setDoc(doc(as('eve'), 'families/f1/locations/eve'), location(T0)));
  });

  it('un ex integrante pierde el acceso de inmediato', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await deleteDoc(doc(c.firestore() as unknown as Firestore, 'families/f1/members/luis'));
    });
    await assertFails(getDoc(doc(as('luis'), 'families/f1/locations/ana')));
    await assertFails(getDocs(collection(as('luis'), 'families/f1/members')));
  });
});

describe('membresías e invitaciones (solo Functions)', () => {
  it('nadie modifica integrantes desde el cliente, ni el owner', async () => {
    await assertFails(updateDoc(doc(as('luis'), 'families/f1/members/luis'), { role: 'owner' }));
    await assertFails(setDoc(doc(as('ana'), 'families/f1/members/mallory'), { uid: 'mallory', role: 'member' }));
    await assertFails(setDoc(doc(as('mallory'), 'families/f1/members/mallory'), { uid: 'mallory', role: 'member' }));
  });

  it('nadie lee ni escribe invitaciones desde el cliente', async () => {
    await assertFails(getDoc(doc(as('ana'), 'invitations/hash1')));
    await assertFails(updateDoc(doc(as('mallory'), 'invitations/hash1'), { uses: 0 }));
  });

  it('nadie crea familias ni membresías desde el cliente', async () => {
    await assertFails(setDoc(doc(as('mallory'), 'families/f9'), { name: 'X' }));
    await assertFails(setDoc(doc(as('mallory'), 'users/mallory/memberships/f1'), { familyId: 'f1' }));
  });

  it('cada quien lee solo sus membresías', async () => {
    await assertSucceeds(getDoc(doc(as('ana'), 'users/ana/memberships/f1')));
    await assertFails(getDoc(doc(as('luis'), 'users/ana/memberships/f1')));
  });
});

describe('consentimiento', () => {
  it('cada persona cambia solo su propio consentimiento', async () => {
    await assertSucceeds(
      setDoc(doc(as('luis'), 'families/f1/consents/luis'), {
        state: 'sharing', precision: 'approximate', updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(as('ana'), 'families/f1/consents/luis'), {
        state: 'sharing', precision: 'exact', updatedAt: serverTimestamp(),
      }),
    );
  });

  it('rechaza estados inválidos, campos extra o fechas del cliente', async () => {
    const db = as('luis');
    const ref = doc(db, 'families/f1/consents/luis');
    await assertFails(setDoc(ref, { state: 'always', precision: 'exact', updatedAt: serverTimestamp() }));
    await assertFails(setDoc(ref, { state: 'sharing', precision: 'exact', updatedAt: serverTimestamp(), x: 1 }));
    await assertFails(setDoc(ref, { state: 'sharing', precision: 'exact', updatedAt: T0 }));
  });
});

describe('ubicaciones', () => {
  it('con el consentimiento en pausa no se publica la ubicación', async () => {
    await assertFails(setDoc(doc(as('luis'), 'families/f1/locations/luis'), location(T0)));
  });

  it('activar el consentimiento y publicar en el mismo lote funciona', async () => {
    const db = as('luis');
    const batch = writeBatch(db);
    batch.set(doc(db, 'families/f1/consents/luis'), {
      state: 'sharing', precision: 'exact', updatedAt: serverTimestamp(),
    });
    batch.set(doc(db, 'families/f1/locations/luis'), location(T0));
    await assertSucceeds(batch.commit());
  });

  it('nadie publica la ubicación de otra persona', async () => {
    await assertFails(setDoc(doc(as('luis'), 'families/f1/locations/ana'), location(T0)));
    // Aunque quien escribe SÍ comparte su ubicación (detectado por pruebas
    // de mutación: el caso anterior fallaba por el consentimiento de Luis).
    await assertFails(
      setDoc(doc(as('ana'), 'families/f1/locations/luis'), location(Timestamp.fromMillis(Date.now()))),
    );
  });

  it('descarta actualizaciones fuera de orden; reenviar la misma captura es inocuo', async () => {
    const db = as('ana');
    const older = Timestamp.fromMillis(T0.toMillis() - 60_000);
    const newer = Timestamp.fromMillis(T0.toMillis() + 60_000);
    await assertFails(setDoc(doc(db, 'families/f1/locations/ana'), location(older)));
    await assertSucceeds(setDoc(doc(db, 'families/f1/locations/ana'), location(T0)));
    await assertSucceeds(setDoc(doc(db, 'families/f1/locations/ana'), location(newer)));
    await assertFails(setDoc(doc(db, 'families/f1/locations/ana'), location(T0)));
  });

  it('rechaza coordenadas fuera de rango, campos extra y fechas lejanas', async () => {
    const db = as('ana');
    const ref = doc(db, 'families/f1/locations/ana');
    const later = Timestamp.fromMillis(Date.now());
    await assertFails(setDoc(ref, location(later, { lat: 91 })));
    await assertFails(setDoc(ref, location(later, { lng: -181 })));
    await assertFails(setDoc(ref, location(later, { name: 'Ana' })));
    await assertFails(setDoc(ref, location(later, { accuracyM: -1 })));
    await assertFails(setDoc(ref, location(Timestamp.fromMillis(Date.now() + 3 * 3600_000))));
    await assertFails(setDoc(ref, location(later, { receivedAt: T0 })));
  });

  it('cada persona puede borrar su ubicación (al pausar), no la de otros', async () => {
    await assertFails(deleteDoc(doc(as('luis'), 'families/f1/locations/ana')));
    await assertSucceeds(deleteDoc(doc(as('ana'), 'families/f1/locations/ana')));
  });

  it('pausar y borrar la ubicación en el mismo lote funciona', async () => {
    const db = as('ana');
    const batch = writeBatch(db);
    batch.set(doc(db, 'families/f1/consents/ana'), {
      state: 'paused', precision: 'exact', updatedAt: serverTimestamp(),
    });
    batch.delete(doc(db, 'families/f1/locations/ana'));
    await assertSucceeds(batch.commit());
  });
});

describe('zonas seguras', () => {
  const zone = (extra: Record<string, unknown> = {}) => ({
    name: 'Colegio', lat: 4.65, lng: -74.05, radiusM: 300, createdBy: 'ana', version: 1,
    updatedAt: serverTimestamp(), ...extra,
  });

  it('solo owner o admin crean zonas', async () => {
    await assertSucceeds(setDoc(doc(as('ana'), 'families/f1/geofences/g2'), zone()));
    await assertFails(setDoc(doc(as('luis'), 'families/f1/geofences/g3'), zone({ createdBy: 'luis' })));
  });

  it('valida radio, nombre y versión inicial', async () => {
    const db = as('ana');
    await assertFails(setDoc(doc(db, 'families/f1/geofences/g4'), zone({ radiusM: 50 })));
    await assertFails(setDoc(doc(db, 'families/f1/geofences/g4'), zone({ radiusM: 2500 })));
    await assertFails(setDoc(doc(db, 'families/f1/geofences/g4'), zone({ name: '' })));
    await assertFails(setDoc(doc(db, 'families/f1/geofences/g4'), zone({ name: '   ' })));
    await assertFails(setDoc(doc(db, 'families/f1/geofences/g4'), zone({ name: '\u200B\u200B' })));
    await assertSucceeds(setDoc(doc(db, 'families/f1/geofences/g5'), zone({ name: 'Casa de la abuela 2' })));
    await assertFails(setDoc(doc(db, 'families/f1/geofences/g4'), zone({ version: 3 })));
    await assertFails(setDoc(doc(db, 'families/f1/geofences/g4'), zone({ createdBy: 'luis' })));
  });

  it('las ediciones exigen versión anterior + 1 (concurrencia optimista)', async () => {
    const ref = doc(as('ana'), 'families/f1/geofences/g1');
    const edit = { name: 'Casa nueva', lat: 4.6, lng: -74.08, radiusM: 250, createdBy: 'ana', updatedAt: serverTimestamp() };
    await assertFails(setDoc(ref, { ...edit, version: 1 }));
    await assertFails(setDoc(ref, { ...edit, version: 3 }));
    await assertSucceeds(setDoc(ref, { ...edit, version: 2 }));
  });

  it('un integrante sin rol de gestión no las borra', async () => {
    await assertFails(deleteDoc(doc(as('luis'), 'families/f1/geofences/g1')));
    await assertSucceeds(deleteDoc(doc(as('ana'), 'families/f1/geofences/g1')));
  });
});

describe('eventos (check-ins y zonas)', () => {
  const checkIn = (actorUid: string, extra: Record<string, unknown> = {}) => ({
    type: 'checkIn', actorUid, kind: 'ok', createdAt: serverTimestamp(),
    clientCreatedAt: T0, expireAt: T0, ...extra,
  });

  it('el autor crea su propio check-in', async () => {
    await assertSucceeds(setDoc(doc(as('luis'), 'families/f1/events/e1'), checkIn('luis')));
  });

  it('no se suplanta a otra persona ni se inventan tipos', async () => {
    await assertFails(setDoc(doc(as('luis'), 'families/f1/events/e2'), checkIn('ana')));
    await assertFails(setDoc(doc(as('luis'), 'families/f1/events/e3'), checkIn('luis', { type: 'sos' })));
    await assertFails(setDoc(doc(as('luis'), 'families/f1/events/e4'), checkIn('luis', { kind: 'panic' })));
    await assertFails(setDoc(doc(as('eve'), 'families/f1/events/e5'), checkIn('eve')));
  });

  it('solo se adjunta ubicación si la persona la comparte', async () => {
    await assertFails(
      setDoc(doc(as('luis'), 'families/f1/events/e6'), checkIn('luis', { lat: 4.6, lng: -74.0 })),
    );
    await assertSucceeds(
      setDoc(doc(as('ana'), 'families/f1/events/e7'), checkIn('ana', { lat: 4.6, lng: -74.0 })),
    );
  });

  it('la retención no se alarga más allá de 30 días (+1 de tolerancia)', async () => {
    const inDays = (days: number) => Timestamp.fromMillis(Date.now() + days * 864e5);
    await assertSucceeds(
      setDoc(doc(as('luis'), 'families/f1/events/r1'), checkIn('luis', { expireAt: inDays(30) })),
    );
    await assertFails(
      setDoc(doc(as('luis'), 'families/f1/events/r2'), checkIn('luis', { expireAt: inDays(365) })),
    );
  });

  it('los eventos no se modifican ni se borran', async () => {
    await setDoc(doc(as('luis'), 'families/f1/events/e8'), checkIn('luis'));
    await assertFails(updateDoc(doc(as('luis'), 'families/f1/events/e8'), { kind: 'needHelp' }));
    await assertFails(deleteDoc(doc(as('luis'), 'families/f1/events/e8')));
    await assertFails(deleteDoc(doc(as('ana'), 'families/f1/events/e8')));
  });

  it('un evento de zona exige que la zona exista', async () => {
    const event = (geofenceId: string) => ({
      type: 'geofence', actorUid: 'luis', geofenceId, geofenceName: 'Casa', transition: 'enter',
      createdAt: serverTimestamp(), clientCreatedAt: T0, expireAt: T0,
    });
    await assertSucceeds(setDoc(doc(as('luis'), 'families/f1/events/e9'), event('g1')));
    await assertFails(setDoc(doc(as('luis'), 'families/f1/events/e10'), event('no-existe')));
  });
});

describe('alertas SOS', () => {
  it('ningún cliente crea una alerta directamente (solo raiseSos)', async () => {
    await assertFails(
      setDoc(doc(as('ana'), 'families/f1/emergencies/x'), {
        uid: 'ana', createdAt: serverTimestamp(), notifiedCount: 3, acks: {}, resolvedAt: null,
      }),
    );
  });

  it('otro integrante confirma que la vio, solo por sí mismo', async () => {
    const db = as('ana');
    await assertFails(updateDoc(doc(db, 'families/f1/emergencies/sos1'), { 'acks.luis': serverTimestamp() }));
    await assertFails(updateDoc(doc(db, 'families/f1/emergencies/sos1'), { 'acks.ana': T0 }));
    await assertFails(updateDoc(doc(db, 'families/f1/emergencies/sos1'), { 'acks.ana': serverTimestamp(), notifiedCount: 9 }));
    // Su propio ack junto con el de otra persona en la misma escritura.
    await assertFails(
      updateDoc(doc(db, 'families/f1/emergencies/sos1'), {
        'acks.ana': serverTimestamp(),
        'acks.sofia': serverTimestamp(),
      }),
    );
    await assertSucceeds(updateDoc(doc(db, 'families/f1/emergencies/sos1'), { 'acks.ana': serverTimestamp() }));
  });

  it('quien la envía no puede confirmarla por otros ni inflar el conteo', async () => {
    await assertFails(updateDoc(doc(as('luis'), 'families/f1/emergencies/sos1'), { 'acks.luis': serverTimestamp() }));
    await assertFails(updateDoc(doc(as('luis'), 'families/f1/emergencies/sos1'), { notifiedCount: 10 }));
  });

  it('solo quien la envió la termina, una vez', async () => {
    await assertFails(updateDoc(doc(as('ana'), 'families/f1/emergencies/sos1'), { resolvedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(as('luis'), 'families/f1/emergencies/sos1'), { resolvedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('luis'), 'families/f1/emergencies/sos1'), { resolvedAt: serverTimestamp() }));
  });

  it('otra familia no confirma ni lee la alerta', async () => {
    await assertFails(updateDoc(doc(as('eve'), 'families/f1/emergencies/sos1'), { 'acks.eve': serverTimestamp() }));
  });
});

describe('perfil, dispositivos y auditoría', () => {
  it('cada quien escribe y lee solo su perfil', async () => {
    await assertSucceeds(setDoc(doc(as('mallory'), 'users/mallory'), { displayName: 'M' }));
    await assertFails(setDoc(doc(as('mallory'), 'users/ana'), { displayName: 'M' }));
    await assertFails(getDoc(doc(as('mallory'), 'users/ana')));
    await assertFails(setDoc(doc(as('mallory'), 'users/mallory'), { displayName: 'M', role: 'admin' }));
    await assertFails(setDoc(doc(as('mallory'), 'users/mallory'), { displayName: '\u200B' }));
    await assertSucceeds(setDoc(doc(as('mallory'), 'users/mallory'), { displayName: 'Ñandú 🙂' }));
  });

  it('registra solo sus dispositivos con campos válidos', async () => {
    const ok = { token: 't', platform: 'android', updatedAt: serverTimestamp() };
    await assertSucceeds(setDoc(doc(as('ana'), 'users/ana/devices/d1'), ok));
    await assertFails(setDoc(doc(as('luis'), 'users/ana/devices/d2'), ok));
    await assertFails(setDoc(doc(as('ana'), 'users/ana/devices/d3'), { ...ok, platform: 'web' }));
  });

  it('solo owner o admin leen la auditoría; nadie la escribe', async () => {
    await assertSucceeds(getDoc(doc(as('ana'), 'families/f1/audit/a1')));
    await assertFails(getDoc(doc(as('luis'), 'families/f1/audit/a1')));
    await assertFails(setDoc(doc(as('ana'), 'families/f1/audit/a2'), { action: 'x' }));
  });

  it('rutas no previstas están denegadas', async () => {
    await assertFails(getDoc(doc(as('ana'), 'rateLimits/ana')));
    await assertFails(setDoc(doc(as('ana'), 'cualquier/cosa'), { a: 1 }));
  });
});

it('los datos sembrados son sintéticos', () => {
  expect(T0.toMillis()).toBe(Date.UTC(2026, 0, 1, 12));
});
