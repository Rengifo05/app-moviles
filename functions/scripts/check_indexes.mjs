// Valida firestore/firestore.indexes.json con el mismo validador que usa
// `firebase deploy` (sin proyecto ni credenciales). El emulador no exige
// índices, así que este paso evita descubrir un error al desplegar.
//
// Uso (dentro de functions/): npm run check:indexes
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';

const require = createRequire(import.meta.url);
const { FirestoreApi } = require('firebase-tools/lib/firestore/api.js');

const spec = JSON.parse(readFileSync(new URL('../../firestore/firestore.indexes.json', import.meta.url), 'utf8'));
const api = new FirestoreApi();
const parsed = api.upgradeOldSpec(spec);
api.validateSpec(parsed);
console.log(`Índices válidos: ${parsed.indexes.length} compuestos, ${parsed.fieldOverrides.length} overrides.`);
