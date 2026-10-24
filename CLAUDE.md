# Nexo Familia: guía para Claude Code

App Flutter de seguridad familiar (Android e iOS), privada por diseño. Estado, decisiones y pendientes: `README.md`, `docs/architecture/06-informe-de-calidad.md`, `docs/architecture/04-plan-y-criterios.md` y `docs/decisions/README.md`. Léelos antes de proponer trabajo nuevo.

## Reglas del proyecto (obligatorias)

- **No afirmes que algo funciona si no lo has ejecutado o probado.** Si algo no se pudo verificar (p. ej., código nativo sin compilar), dilo y márcalo como 📱.
- **No inventes** skills, comandos, paquetes, APIs ni funciones. Comprueba versiones y APIs en el código fuente o en pub.dev o npm.
- **Pide aprobación** antes de cualquier decisión que añada costos, cambie significativamente el alcance o requiera credenciales (D7: Firebase Blaze, Maps, APNs, App Check; D8: plugins de Claude Code).
- **Sin secretos** en el cliente ni en el repositorio. `.env.example` y `config/env.example.json` llevan solo nombres y valores de ejemplo.
- **Sin coordenadas precisas, tokens, contraseñas ni mensajes en los registros.** `SafeLogger` tiene un esquema cerrado por campo.
- **Pruebas con datos sintéticos**, nunca ubicaciones reales.
- **Honestidad en la interfaz:**
  - nunca digas «seguro», «a salvo», «recibido» ni «ayuda en camino»;
  - «enviado» o «confirmado» solo con respuesta del servidor o con el *ack* de otra persona;
  - no afirmes cifrado de extremo a extremo (no existe).
- **El SOS nunca se apaga en remoto** y no da confirmaciones falsas.
- **Accesibilidad:** contraste WCAG, áreas táctiles, etiquetas y texto al 200 % sin desbordes.

## Stack y arquitectura

- Flutter 3.47.7 / Dart 3.13.5 (sintaxis nueva de constructores: `new(...)`, `const new`, `factory name`, parámetros formales privados `this._x`).
- Riverpod 3, go_router 18, Drift y FlutterFire (cloud_firestore 6, firebase_core 4, firebase_auth 6, cloud_functions 6, firebase_messaging 16), share_plus 13 y package_info_plus.
- Capas: `lib/features/<f>/{domain,data,presentation}`, `lib/infrastructure`, `lib/app` (raíz de composición: `composition.dart` y `bootstrap.dart`) y `lib/core`. Una prueba de arquitectura de mundo cerrado vigila los límites entre capas.
- Backend: `firestore/firestore.rules` y `functions/src/*.ts` (TypeScript, región southamerica-east1). Contrato en `docs/architecture/05-api-backend.md`.
- Backend de demostración (`lib/infrastructure/demo/`): debe comportarse igual que las Functions. Cada Function nueva tiene su equivalente y sus pruebas de conformidad.
- Textos: fragmentos en `lib/l10n/fragments/<grupo>.<es|en>.json` → `dart run tool/merge_arb.dart` → `flutter gen-l10n`. Nunca edites los `.arb` a mano.

## Comandos (las puertas de calidad de la CI)

```bash
export PATH=/opt/flutter/bin:$PATH
tool/check.sh                         # formato, merge_arb --check, analyze --fatal-infos, todas las pruebas
tool/check_backend.sh                 # tipos, índices, build y pruebas de reglas y Functions en el emulador
(cd functions && npm run test:mutations)   # mutaciones de las reglas: todas deben detectarse
flutter test --update-goldens <archivo>    # solo si el cambio visual es intencional; revisa la imagen
```

Cada cambio de reglas añade su prueba y, si debilitarla no se detecta, una mutación en `functions/scripts/mutate_rules.mjs`.

## Forma de trabajar

- Rama: `claude/nexo-familia-security-platform-1oxy4n`. Push con `git push -u origin <rama>`. No abras PR salvo que se pida.
- Commits en español, descriptivos, con las líneas de atribución que indique la sesión.
- Antes de cada commit: `tool/check.sh` (y `tool/check_backend.sh` si cambió el backend) en verde. Actualiza las cifras de pruebas en `README.md`, `04-plan-y-criterios.md` y `06-informe-de-calidad.md`.
- Para un fallo, primero una prueba que lo reproduzca; después la corrección.
- Los cambios grandes pasan por una revisión adversarial (enfoques: privacidad, honestidad, datos e integración). Los hallazgos se verifican en el código y se registran en `docs/architecture/revisiones.md`.
- Al terminar, comprueba la CI de GitHub del último commit.

## Estado y pendientes (2026-10-20)

- MVP completo y probado en el host con el backend de demostración: 1258 pruebas de la app (7 escenarios E2E), 106 del backend y 44/44 mutaciones. La CI está en verde.
- **Bloqueado por el usuario:**
  - D7: proyecto Firebase real, Maps, APNs y App Check;
  - D8: plugins de Claude Code;
  - verificaciones 📱 en teléfonos (runbook `docs/runbooks/entorno-de-desarrollo.md`), incluida la compilación de `MainActivity.kt`, el canal «Alertas SOS»;
  - la revisión legal (Ley 1581).
- **Programado:** actualizar FlutterFire a sus versiones mayores (core 5, firestore 7, auth 7, functions 7, messaging 17) **a partir del 2026-10-29**, en un cambio aparte, revisando los cambios incompatibles.
- **Limitación aceptada:** con el reloj del teléfono adelantado más de 1 día, las reglas rechazan los check-ins (`expireAt`); se muestra como fallido.
