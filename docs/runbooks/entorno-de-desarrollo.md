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

Después: configurar la política TTL de Firestore sobre `expireAt` en `events` (30 días) y en las alertas, y las alertas de presupuesto (ver `docs/architecture/03-costos.md`).

## Pasos manuales en macOS (iOS) — no verificables en la sesión en la nube

1. `flutter build ios --debug --no-codesign` genera el `Podfile`. En su `post_install`, habilita el permiso de ubicación de `permission_handler`: `'PERMISSION_LOCATION=1'` en `GCC_PREPROCESSOR_DEFINITIONS`.
2. Comprueba que `AppDelegate.swift` excluye `Application Support` de las copias (`isExcludedFromBackup`).
3. Revisa en el dispositivo el texto de `NSLocationWhenInUseUsageDescription`.

## Limitaciones conocidas de la sesión en la nube

- Sin Android SDK (`dl.google.com` bloqueado) y sin Xcode: no hay compilaciones ni pruebas en dispositivo.
- Docker sin daemon: el stack local de Supabase no está disponible.
- Las sesiones son efímeras: el *SessionStart hook* reinstala Flutter y las dependencias al iniciar cada sesión remota.
