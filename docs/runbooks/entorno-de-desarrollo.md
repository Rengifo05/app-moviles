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

## Emuladores de Firebase (sin credenciales)

Se usan proyectos con prefijo `demo-` (p. ej. `demo-nexo`), que **no requieren cuenta ni credenciales** y no pueden tocar recursos reales.

```bash
npx firebase-tools@15.34.0 emulators:exec --only firestore,auth,functions --project demo-nexo "<comando de pruebas>"
```

## Limitaciones conocidas de la sesión en la nube

- Sin Android SDK (`dl.google.com` bloqueado) y sin Xcode: no hay compilaciones ni pruebas en dispositivo.
- Docker sin daemon: el stack local de Supabase no está disponible.
- Las sesiones son efímeras: el *SessionStart hook* reinstala Flutter y las dependencias al iniciar cada sesión remota.
