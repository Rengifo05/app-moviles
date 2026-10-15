# 00 · Descubrimiento del repositorio y del entorno

Fecha de inspección: 2026-10-15. Todo lo que aparece como "verificado" se ejecutó en esta sesión; lo demás se marca como pendiente o no verificable.

## Estado del repositorio

- `Rengifo05/app-moviles` estaba **vacío**: sin commits, sin ramas remotas y sin archivos. No existe trabajo previo que preservar ni convenciones heredadas.
- Rama de trabajo: `claude/nexo-familia-security-platform-1oxy4n`.
- Este primer entregable contiene **solo documentación**. Ningún código de la app se generará hasta que se apruebe la arquitectura (ver `docs/decisions/README.md`).

## Entorno de ejecución (sesión de Claude Code en la nube)

| Herramienta | Estado | Notas |
|---|---|---|
| Claude Code | 2.1.300 | Sesión remota y contenedor efímero |
| Flutter | **3.47.7 estable** (2026-10-08), instalado en `/opt/flutter` | Se descargó del archivo oficial y se verificó su SHA-256 |
| Dart | **3.13.5** | Incluido en Flutter |
| Java | OpenJDK 21.0.12 | Necesario para el emulador de Firestore |
| Node / npm | 22.22.0 / 10.9.4 | Para Cloud Functions y las pruebas de reglas |
| firebase-tools | 15.34.0 (scratchpad, no en el repo) | `emulators:exec` funcionó con el proyecto `demo-nexo` |
| Emulador de Firestore | v1.22.0 | **Verificado**: arranca y responde HTTP 200 |
| Android SDK | **No disponible** | `dl.google.com` está bloqueado por la política de red; no se pueden generar APK aquí |
| Xcode / iOS | **No disponible** | El contenedor es Linux; las compilaciones de iOS requieren macOS |
| Docker | Cliente 29.8.2, **sin daemon** | El stack local de Supabase no puede verificarse aquí |
| Red | `pub.dev`, `storage.googleapis.com` y `maven.google.com`: OK | `firebase.google.com`, `supabase.com`, `developers.google.com` y `dl.google.com` están bloqueados para `curl` |

### Consecuencias para el plan

1. En esta sesión **sí se pueden** ejecutar `flutter analyze`, `dart format`, `flutter test` (unitarias y de widgets, Drift con SQLite nativo) y las pruebas de reglas de Firestore con el emulador.
2. **No se puede** compilar para Android ni para iOS, ni probar en dispositivos. Esa validación (mapas nativos, permisos, ubicación en segundo plano, push) se tendrá que hacer en una máquina local o en CI, y se documentará como paso manual.
3. Para que las sesiones futuras en la nube puedan ejecutar pruebas, se propone un *SessionStart hook* que instale Flutter 3.47.7 (tarea T1.6 del plan).

## Prueba de compatibilidad de dependencias (spike desechable)

Se creó un proyecto temporal **fuera del repositorio** para comprobar que las dependencias candidatas se resuelven juntas con Flutter 3.47.7. Resultados:

- `flutter pub get` resolvió **todas** las dependencias sin conflictos.
- `build_runner` generó el código de Drift (53 s la primera vez).
- `flutter test` pasó una prueba de inserción y lectura de Drift sobre SQLite en memoria (con `sqlite3` 3.x compilado mediante *build hooks*).

| Paquete | Versión resuelta | Publicador | Puntos pub | Observación |
|---|---|---|---|---|
| flutter_riverpod | 3.4.3 | dash-overflow.net | 140/160 | |
| go_router | 18.1.0 | flutter.dev | 150/160 | Flutter Favorite |
| drift / drift_flutter | 2.35.2 / 0.3.1 | simonbinder.eu | 160/160 | |
| drift_dev / build_runner | 2.35.1 / 2.16.2 | | | El resolvedor no eligió `build_runner` 2.17.1 por las restricciones actuales; se revisará con `flutter pub outdated` |
| sqlite3 | 3.5.2 | | | **`sqlite3_flutter_libs` está marcado como EOL**: no debe añadirse directamente |
| geolocator | 14.0.1 | baseflow.com | 160/160 | Flutter Favorite |
| permission_handler | 13.0.2 | baseflow.com | 160/160 | |
| native_geofence | 1.3.1 | chunkytofustudios.com | 160/160 | Usa geocercas del sistema operativo; requiere validarse en dispositivo |
| flutter_secure_storage | 11.2.0 | steenbakker.dev | 160/160 | |
| connectivity_plus | 7.3.2 | fluttercommunity.dev | 160/160 | Solo como indicio de conectividad, nunca como verdad |
| google_maps_flutter | 2.19.0 | flutter.dev | 150/160 | Android e iOS |
| apple_maps_flutter | 1.4.0 | fluttercommunity.dev | 130/160 | **Último release: 2025-01-23**; sin soporte de Swift Package Manager. Ver ADR-002 |
| firebase_core / auth / cloud_firestore | 4.15.0 / 6.7.0 / 6.10.0 | firebase.google.com | 160/160 | |
| cloud_functions / firebase_messaging / firebase_app_check | 6.5.0 / 16.7.0 / 0.4.8 | firebase.google.com | | |
| very_good_analysis | 11.0.0 | verygood.ventures | 160/160 | Requiere Dart ^3.13 |
| mocktail | 1.0.5 | felangel.dev | 160/160 | |
| flutter_background_geolocation | 5.9.0 | transistorsoft.com | 160/160 | **Requiere licencia de pago para compilaciones *release*** (iOS y Android). Ver ADR-003 |

Backend (npm, consultado el 2026-10-15): `firebase-functions` 7.4.0, `firebase-admin` 14.5.0, `@firebase/rules-unit-testing` 6.0.0, `typescript` 7.0.2 y `vitest` 5.0.4. Se fijarán en el Día 4, tras verificar su compatibilidad.

## Skills, agentes y plugins de Claude Code

**Disponibles en esta sesión:** `code-review`, `security-review`, `simplify`, `run`, `session-start-hook` y agentes `Explore`, `Plan` y `general-purpose`. No hay ninguna skill específica de Flutter instalada.

**Encontrados en el catálogo de plugins (no instalados; requieren autorización):**

| Plugin | Publicador | Utilidad |
|---|---|---|
| Dart and Flutter | partner, oficial (`flutter/agent-plugins`) | Skills de Dart/Flutter y Dart MCP server (análisis, pruebas, layout) |
| Design | Anthropic | Revisión de accesibilidad, crítica de diseño, sistema de diseño, textos de UX |
| Very Good AI Flutter Plugin | Very Good Ventures (community) | Seguridad estática, pruebas, temas, *quality gate*; **incluye hooks** que modifican el flujo |
| firebase (MCP) | Google (partner) | Gestión de Firebase; **requiere credenciales del proyecto** |

Recomendación: autorizar solo **Dart and Flutter** y **Design** al empezar. Los demás se evalúan cuando existan credenciales y un flujo estable.

## Fuentes consultadas y su fiabilidad

La documentación oficial de Firebase, Google Maps y Supabase **no estaba accesible directamente** desde este contenedor. Las cifras de precios provienen de resultados de búsqueda que citan esas páginas, y **deben reconfirmarse** en la página oficial antes de cualquier compromiso de gasto. Las tablas de `03-costos.md` y de los ADR indican la fecha y la fuente.
