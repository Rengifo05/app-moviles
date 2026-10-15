// Pruebas de mutación de las reglas de Firestore: debilita cada condición
// por separado y comprueba que alguna prueba de test/rules lo detecta.
// Una mutación que "sobrevive" es un hueco en las pruebas.
//
// Uso (dentro de functions/): npm run test:mutations
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const original = readFileSync(new URL('../../firestore/firestore.rules', import.meta.url), 'utf8');

/** [descripción, texto original, texto mutado] */
const mutations = [
  ['isMember no comprueba la membresía', 'return signedIn() && exists(memberPath(familyId));', 'return signedIn();'],
  ['isManager no comprueba el rol', "&& get(memberPath(familyId)).data.role in ['owner', 'admin'];", ';'],
  ['perfil legible por cualquiera con sesión', 'allow read: if signedIn() && me() == userId;', 'allow read: if signedIn();'],
  ['perfil con campos libres', "&& onlyKeys(['displayName', 'createdAt', 'adultConfirmedAt',\n                     'privacyAcceptedAt', 'privacyPolicyVersion'])", ''],
  ['membresías legibles por otros', "match /memberships/{familyId} {\n        allow read: if signedIn() && me() == userId;", "match /memberships/{familyId} {\n        allow read: if signedIn();"],
  ['dispositivos de otros', "allow create, update: if signedIn() && me() == userId\n          && onlyKeys(['token', 'platform', 'updatedAt'])", "allow create, update: if signedIn()\n          && onlyKeys(['token', 'platform', 'updatedAt'])"],
  ['plataforma de dispositivo libre', "&& data().platform in ['android', 'ios']", ''],
  ['integrantes editables', "match /members/{memberId} {\n        allow read: if isMember(familyId);", "match /members/{memberId} {\n        allow read, write: if isMember(familyId);"],
  ['consentimiento de otros', "allow create, update: if isMember(familyId) && me() == memberId\n          && onlyKeys(['state', 'precision', 'updatedAt'])", "allow create, update: if isMember(familyId)\n          && onlyKeys(['state', 'precision', 'updatedAt'])"],
  ['estado de consentimiento libre', "&& data().state in ['notConfigured', 'sharing', 'paused']", ''],
  ['fecha de consentimiento del cliente', "&& data().precision in ['exact', 'approximate']\n          && data().updatedAt == request.time;", "&& data().precision in ['exact', 'approximate'];"],
  ['ubicación sin consentimiento', '&& sharingAfter(familyId)\n          && onlyKeys([\'lat\'', "&& onlyKeys(['lat'"],
  ['ubicación de otros', "allow create, update: if isMember(familyId) && me() == memberId\n          && sharingAfter(familyId)", "allow create, update: if isMember(familyId)\n          && sharingAfter(familyId)"],
  ['coordenadas sin validar', '&& validLatLng(data().lat, data().lng)\n          && data().accuracyM is number', '&& data().accuracyM is number'],
  ['precisión negativa', '&& data().accuracyM >= 0 && data().accuracyM < 100000', ''],
  ['receivedAt del cliente', '&& data().receivedAt == request.time\n          && data().capturedAt is timestamp', '&& data().capturedAt is timestamp'],
  ['capturedAt en el futuro', "&& data().capturedAt < request.time + duration.value(1, 'h')", ''],
  ['actualizaciones fuera de orden', '&& (resource == null || data().capturedAt > resource.data.capturedAt);', ';'],
  ['borrar ubicaciones ajenas', 'allow delete: if isMember(familyId) && me() == memberId;', 'allow delete: if isMember(familyId);'],
  ['zonas creadas por cualquier integrante', "allow create: if isManager(familyId) && validGeofence()\n          && data().version == 1", "allow create: if isMember(familyId) && validGeofence()\n          && data().version == 1"],
  ['radio de zona libre', '&& data().radiusM >= 100 && data().radiusM <= 2000', ''],
  ['versión de zona libre', '&& data().version == resource.data.version + 1', ''],
  ['zonas borradas por cualquiera', 'allow delete: if isManager(familyId);\n      }\n\n      match /events', 'allow delete: if isMember(familyId);\n      }\n\n      match /events'],
  ['nombres invisibles', "&& name.matches('.*[\\\\p{L}\\\\p{N}].*');", ';'],
  ['suplantar al autor de un evento', '&& data().actorUid == me()\n          && data().createdAt == request.time', '&& data().createdAt == request.time'],
  ['retención de eventos ilimitada', "&& data().expireAt <= request.time + duration.value(31, 'd')", ''],
  ['tipo de evento libre', "&& ((data().type == 'checkIn' && validCheckIn())\n              || (data().type == 'geofence' && validGeofenceEvent()));", ';'],
  ['ubicación en check-in sin compartir', '&& sharingAfter(familyId)));', '));'],
  ['evento de zona inexistente', "&& validName(data().geofenceName)\n            && exists(", "&& validName(data().geofenceName)\n            || exists("],
  ['eventos editables', "// Nunca se modifican ni se borran desde el cliente.", "allow update, delete: if isMember(familyId);"],
  ['la autora confirma su propia alerta', 'return resource.data.uid != me()\n            && !(me() in resource.data.acks)', 'return !(me() in resource.data.acks)'],
  ['confirmar por otros', ".hasOnly([me()])\n            && data().acks[me()] == request.time;", ".size() > 0\n            && data().acks[me()] == request.time;"],
  ['ack que cambia otros campos', "&& data().diff(resource.data).affectedKeys().hasOnly(['acks'])", ''],
  ['terminar alertas ajenas', 'return resource.data.uid == me()\n            && resource.data.resolvedAt == null', 'return resource.data.resolvedAt == null'],
  ['terminar dos veces', '&& resource.data.resolvedAt == null\n            && data().diff', '&& data().diff'],
  ['crear alertas desde el cliente', 'allow update: if isMember(familyId) && (isAck() || isResolve());', 'allow create, update: if isMember(familyId);'],
  ['auditoría para todos', "match /audit/{auditId} {\n        allow read: if isManager(familyId);", "match /audit/{auditId} {\n        allow read: if isMember(familyId);"],
  ['invitaciones legibles', 'match /{document=**} {\n      allow read, write: if false;', 'match /invitations/{id} {\n      allow read: if signedIn();\n    }\n    match /{document=**} {\n      allow read, write: if false;'],
];

const dir = mkdtempSync(join(tmpdir(), 'nx-rules-'));
let survived = 0;
for (const [name, from, to] of mutations) {
  if (!original.includes(from)) {
    console.log(`??  ${name}: el patrón ya no existe en las reglas (actualiza la mutación)`);
    survived++;
    continue;
  }
  const path = join(dir, 'mutant.rules');
  writeFileSync(path, original.replace(from, to));
  let killed = false;
  try {
    execFileSync('npx', ['vitest', 'run', 'test/rules', '--reporter=dot'], {
      env: { ...process.env, RULES_PATH: path },
      stdio: 'pipe',
    });
  } catch {
    killed = true; // alguna prueba falló: la mutación fue detectada
  }
  console.log(`${killed ? 'OK ' : 'XX '} ${name}`);
  if (!killed) survived++;
}
console.log(`\n${mutations.length - survived}/${mutations.length} mutaciones detectadas`);
process.exit(survived === 0 ? 0 : 1);
