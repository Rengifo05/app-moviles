# Runbook · Entorno de desarrollo

Estado: preparación previa al Día 1. Se actualizará cuando exista el proyecto Flutter.

## Versiones verificadas (2026-10-15)

- Flutter **3.47.7** (stable), Dart **3.13.5**
- Node 22, Java 21 (para los emuladores de Firebase)
- firebase-tools 15.34.0 (emulador de Firestore v1.22.0)

## Instalar Flutter en Linux (como se hizo en la sesión en la nube)

```bash
curl -sSO https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.7-stable.tar.xz
echo "af7455f540df951184c7953fbe3cf884766e7541dacf8571f9f582db03dd6230  flutter_linux_3.47.7-stable.tar.xz" | sha256sum -c -
tar -xJf flutter_linux_3.47.7-stable.tar.xz -C /opt
export PATH=/opt/flutter/bin:$PATH
flutter --disable-analytics && flutter --version
```

En macOS o Windows, usar el instalador oficial de la misma versión. Para compilar en Android hace falta Android Studio o el SDK; para iOS, Xcode en macOS.

## Emuladores de Firebase (sin credenciales)

Se usan proyectos con prefijo `demo-` (p. ej. `demo-nexo`), que **no requieren cuenta ni credenciales** y no pueden tocar recursos reales.

```bash
npx firebase-tools@15.34.0 emulators:exec --only firestore,auth,functions --project demo-nexo "<comando de pruebas>"
```

## Limitaciones conocidas de la sesión en la nube

- Sin Android SDK (`dl.google.com` bloqueado) y sin Xcode: no hay compilaciones ni pruebas en dispositivo.
- Docker sin daemon: el stack local de Supabase no está disponible.
- Las sesiones son efímeras: Flutter debe reinstalarse en cada sesión hasta que exista el *SessionStart hook* (T1.6).
