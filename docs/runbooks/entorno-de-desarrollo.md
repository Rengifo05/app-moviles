# Runbook · Entorno de desarrollo

Estado: vigente desde el incremento 1.

## Versiones verificadas (2026-10-15)

- Flutter **3.47.7** (stable), Dart **3.13.5**
- Node 22, Java 21 (para los emuladores de Firebase)
- firebase-tools 15.34.0 (emulador de Firestore v1.22.0)

## Instalar Flutter en Linux

```bash
tool/install_flutter.sh [destino]   # por defecto /opt/flutter; verifica el SHA-256
export PATH=/opt/flutter/bin:$PATH
```

El script es idempotente y lo usan tanto la CI (`.github/workflows/ci.yml`) como el *SessionStart hook* de Claude Code (`.claude/hooks/session-start.sh`). Para actualizar Flutter, cambia `FLUTTER_VERSION` y `FLUTTER_SHA256` en el script; el hash se toma de `releases_linux.json` del archivo oficial.

## Puertas de calidad

```bash
tool/check.sh   # pub get → dart format (verificación) → flutter analyze --fatal-infos → flutter test
```

## Configuración por entorno

`config/env.example.json` lista las claves (`NX_APP_NAME`, `NX_ENV`, `NX_BACKEND`, `NX_USE_EMULATORS` y `NX_EMERGENCY_NUMBER`). Copia el archivo a `config/env.<entorno>.json`, que git ignora, y ejecuta con `--dart-define-from-file`. La app valida la configuración al arrancar y se niega a iniciar si, por ejemplo, producción usa el backend de demostración o los emuladores.

### App contra los emuladores de Firebase

Con `NX_BACKEND=firebase` y `NX_USE_EMULATORS=true`, la app usa Auth, Firestore y Functions locales. `NX_FIREBASE_PROJECT_ID` debe empezar por `demo-` (la app lo exige). Las claves `NX_FIREBASE_API_KEY`, `NX_FIREBASE_APP_ID` y `NX_FIREBASE_SENDER_ID` pueden quedar vacías. `NX_EMULATOR_HOST` es `127.0.0.1` en iOS y escritorio, y `10.0.2.2` desde el emulador de Android.

```bash
cd functions && npx firebase emulators:start --project demo-nexo --config ../firebase.json
# en otra terminal:
flutter run --dart-define-from-file=config/env.emulators.json
```

Con un proyecto real (pendiente de D7), esas tres claves son identificadores **públicos** del cliente, no secretos: la protección viene de las reglas, App Check y las restricciones de la API key. Aun así no se versionan, porque dependen del proyecto.

En macOS o Windows, usar el instalador oficial de la misma versión. Para compilar en Android hace falta Android Studio o el SDK; para iOS, Xcode en macOS.

## Backend: reglas y Cloud Functions (sin credenciales)

Requisitos: Node 22 y Java 21 (para el emulador de Firestore). El proyecto `demo-nexo` (prefijo `demo-`) **no requiere cuenta ni credenciales** y no puede tocar recursos reales.

```bash
tool/check_backend.sh        # npm install → typecheck → build → pruebas en el emulador
# o, por partes, dentro de functions/:
npm run typecheck
npm test                     # emulators:exec + vitest (reglas y funciones)
```

- `firestore/firestore.rules`: reglas (denegación por defecto). Pruebas: `functions/test/rules/`.
- `functions/src/`: lógica de las funciones *callable* con nombres del contrato (`docs/architecture/05-api-backend.md`). Pruebas contra el emulador: `functions/test/functions/`.
- Región: `southamerica-east1` (`functions/src/config.ts`).

### Desplegar (pendiente: decisión D7)

Requiere un proyecto real de Firebase con plan Blaze, presupuesto y *spend cap* en Functions. Cuando esté aprobado:

```bash
npx firebase login
npx firebase use --add <id-del-proyecto>      # crea el alias; no se versiona ningún secreto
npx firebase deploy --only firestore:rules,firestore:indexes,functions
```

`firestore:indexes` despliega también las políticas TTL sobre `expireAt` (eventos, alertas, auditoría e invitaciones) y el índice compuesto de invitaciones. El emulador no exige índices, así que una consulta nueva con varios filtros debe añadir su índice a `firestore/firestore.indexes.json`. Para validar el archivo sin proyecto: `npm run check:indexes` (también en la CI).

Después: las alertas de presupuesto (ver `docs/architecture/03-costos.md`).

## Pasos manuales en macOS (iOS) — no verificables en la sesión en la nube

1. `flutter build ios --debug --no-codesign` genera el `Podfile`. En su `post_install`, habilita el permiso de ubicación de `permission_handler`: `'PERMISSION_LOCATION=1'` en `GCC_PREPROCESSOR_DEFINITIONS`.
2. Comprueba que `AppDelegate.swift` excluye `Application Support` de las copias (`isExcludedFromBackup`).
3. Revisa en el dispositivo el texto de `NSLocationWhenInUseUsageDescription`.
4. Avisos push (ADR-005, requiere D7):
   - en Xcode, añade la *capability* **Push Notifications** al target `Runner` (crea el *entitlement* `aps-environment`);
   - sube la clave APNs (`.p8`) en la consola de Firebase, en Configuración del proyecto → Cloud Messaging;
   - en un iPhone real (el simulador no recibe avisos de APNs de forma fiable): inicia sesión con una familia, pulsa «Activar avisos», acepta el diálogo y comprueba que aparece `users/{uid}/devices/{id}` en Firestore;
   - con la app cerrada, lanza un SOS desde otra cuenta: debe llegar «Alerta SOS» sin nombres ni ubicación, y al tocarlo se abre Inicio con la alerta;
   - cierra sesión y comprueba que el documento del dispositivo desaparece.
5. Android 13 o superior: repite la prueba anterior; el diálogo de `POST_NOTIFICATIONS` debe aparecer solo al pulsar «Activar avisos».

## Limitaciones conocidas de la sesión en la nube

- Sin Android SDK (`dl.google.com` bloqueado) y sin Xcode: no hay compilaciones ni pruebas en dispositivo.
- Docker sin daemon: el stack local de Supabase no está disponible.
- Las sesiones son efímeras: el *SessionStart hook* reinstala Flutter y las dependencias al iniciar cada sesión remota.
