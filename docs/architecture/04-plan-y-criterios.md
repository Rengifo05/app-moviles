# 04 · Plan de trabajo por incrementos y criterios de aceptación

Leyenda: 🔒 = requiere aprobación (alcance, costo o credenciales). 📱 = solo verificable en dispositivo o máquina local. Lo que no esté marcado se puede verificar en la sesión en la nube.

Cada tarea sigue la rutina: leer → enfoque → criterios → cambio mínimo → `dart format` + `flutter analyze` → pruebas → revisión de UI (si aplica) → documentación → informe.

## Estado (actualizado el 2026-10-16)

Se marca ✅ solo lo verificado con pruebas ejecutadas en esta sesión y en la CI. ⏳ = en curso. 🔒/📱 = bloqueado por una decisión o por un dispositivo.

| Incremento | Estado | Evidencia |
|---|---|---|
| 1 · Base | ✅ | Análisis estricto, prueba de arquitectura en mundo cerrado, CI en GitHub Actions, *hook* de sesión |
| 2 · Diseño y navegación | ✅ (T2.4 se completa con cada funcionalidad) | Contraste WCAG de 61 pares, guías de accesibilidad, galería *golden* al 100 % y 200 % |
| 3 · Dominio y persistencia | ✅ | Drift (caché, bandeja, preferencias), bandeja con prioridad SOS, espejo con reconexión; revisión adversarial con 39 defectos corregidos |
| 4 · Identidad, grupos y reglas | ✅ en emulador · 🔒 despliegue (D7) | Reglas con 41/41 mutaciones detectadas; Functions y reglas con 94 pruebas en el emulador; adaptador Firebase de la app con pruebas sobre dobles; retención con TTL e índices validados |
| 5 · Ubicación, mapa, geocercas y check-ins | ✅ (mapa como lista accesible; Google Maps 🔒 D7; geocercas nativas desactivadas por ADR-003) | Familia, ubicación, zonas, check-ins, inicio y actividad; E2E de familia y de check-in sin conexión |
| 6 · SOS y resiliencia | ✅ en el host · 🔒📱 push real (D7; cliente diseñado en ADR-005, sin implementar) | E2E del SOS con confirmación entre dos cuentas; `raiseSos` idempotente con el consentimiento vigente |
| 7 · Endurecimiento | ⏳ Revisiones adversariales (`revisiones.md`), runbook de incidentes, revisión de dependencias e [informe de calidad](06-informe-de-calidad.md) | 1196 pruebas de la app, 94 del backend, 41/41 mutaciones |

## Incremento 1 · Base del proyecto (tras aprobar la arquitectura)

| ID | Tarea | Criterios de aceptación |
|---|---|---|
| T1.1 | `flutter create` (org configurable; Android e iOS) con Flutter 3.47.7 | El proyecto compila en el host: `flutter test` pasa con una prueba inicial. `pubspec.yaml` declara `environment: { sdk: ^3.13.0, flutter: ">=3.47.7" }` |
| T1.2 | Análisis estricto: `very_good_analysis` 11, `strict-casts`, `strict-inference` y `strict-raw-types` | `flutter analyze` da 0 *issues*; `dart format --set-exit-if-changed .` pasa |
| T1.3 | `core/`: `Result`, `Failure` (sellada), `Clock`, `IdGenerator` (UUID v7) y `SafeLogger` | Pruebas unitarias: el redactor elimina coordenadas, tokens y correos (≥ 6 casos); `Result` cubre los caminos de éxito y fallo |
| T1.4 | Prueba de arquitectura en `test/architecture/` | Falla si un archivo en `features/*/domain/` importa `package:flutter`, `cloud_firestore`, `firebase_*` o `drift`, o si `presentation/` importa `cloud_firestore` o `drift`. Se demuestra con un caso que falla a propósito y luego se revierte |
| T1.5 | `app/`: `AppConfig` (nombre configurable y entorno) y `bootstrap` sin Firebase todavía | El nombre "Nexo Familia" sale de la configuración y una prueba de widget lo verifica. Existe `config/env.example.json` sin valores sensibles |
| T1.6 | *SessionStart hook* para sesiones en la nube (instala Flutter 3.47.7 con checksum) | Una sesión nueva puede ejecutar `flutter test` sin pasos manuales; documentado en el runbook |
| T1.7 | CI básica (GitHub Actions): formato, análisis y pruebas en Linux | El workflow pasa en la rama. 🔒 Los *runners* de macOS y Android quedan para cuando se aprueben sus minutos |
| T1.8 | `.gitignore` de secretos y README de instalación | `git check-ignore` confirma `env.*.json`, `google-services.json`, `GoogleService-Info.plist` y `*.keystore` |

**Resultado del incremento 1:** estructura compilable, análisis estricto en verde y límites entre capas verificados automáticamente.

## Incremento 2 · Sistema de diseño y navegación

| ID | Tarea | Criterios |
|---|---|---|
| T2.1 | Tokens (color claro y oscuro, tipografía, espaciado, radios, elevación y movimiento) y `NxTheme` | Prueba automática de contraste: todos los pares texto/fondo ≥ 4,5:1 (≥ 3:1 en texto grande), en claro y oscuro |
| T2.2 | Componentes: botón, *pill* de estado (ícono + texto), tarjeta de integrante, estado vacío, banner de error o desconexión y botón SOS | Pruebas *golden* en claro y oscuro con escala de texto 1,0 y 2,0; área táctil ≥ 48×48 (`meetsGuideline(androidTapTargetGuideline)` e `iOSTapTargetGuideline`); `labeledTapTargetGuideline` y `textContrastGuideline` |
| T2.3 | Shell de GoRouter con 5 pestañas y la ruta modal de SOS | Pruebas de navegación: cada pestaña conserva su estado; el SOS abre un modal; el botón atrás funciona |
| T2.4 | Las 10 pantallas con datos ficticios, incluidos sus estados (carga, vacío, sin conexión, permiso denegado, datos antiguos, error, éxito) | Capturas de cada pantalla y estado revisadas; ninguna pantalla dice "a salvo" ni "seguro" como estado de una persona |

## Incremento 3 · Dominio y persistencia local

| ID | Tarea | Criterios |
|---|---|---|
| T3.1 | Entidades y objetos de valor (`GeoPoint` valida rangos; `Radius` entre 100 y 2000 m) | Pruebas unitarias de las invariantes |
| T3.2 | Casos de uso: consentimiento, check-in, crear y editar geocerca (límite de 10) y SOS (máquina de estados) | Pruebas de todas las transiciones válidas e inválidas del SOS |
| T3.3 | Drift: esquema v1, cachés, bandeja de salida y migraciones probadas | Pruebas con `NativeDatabase.memory()`; prueba de migración generada con `drift_dev` |
| T3.4 | Sincronizador con espera exponencial, clasificación de errores e idempotencia | Pruebas con reloj falso: reintentos, prioridad del SOS, error permanente → `failed`, duplicado → una sola operación |

## Incremento 4 · Identidad, grupos y reglas (🔒 credenciales para desplegar; el emulador no las necesita)

| ID | Tarea | Criterios |
|---|---|---|
| T4.1 | Auth con correo (emulador) y repositorio | Pruebas de repositorio contra el emulador de Auth |
| T4.2 | Functions: `createFamily`, `createInvitation`, `acceptInvitation`, `leaveFamily`, `removeMember` y `deleteAccount` | Pruebas con el emulador: token expirado, agotado, revocado, reutilizado e inválido; idempotencia |
| T4.3 | `firestore.rules` y pruebas de aislamiento | Todos los casos negativos de la matriz de `02-modelo-de-datos.md` están **denegados** y los positivos permitidos; se ejecutan en CI |
| T4.4 | 🔒 Proyecto Firebase real (staging), plan Blaze, presupuesto y *spend cap* | Solo con aprobación y credenciales del propietario |

## Incremento 5 · Ubicación, mapa, geocercas y check-ins

| ID | Tarea | Criterios |
|---|---|---|
| T5.1 | Permisos graduales y explicados (`permission_handler`) | Pruebas de widget de cada estado de permiso (simulado); 📱 verificación manual en Android e iOS |
| T5.2 | Compartir ubicación en primer plano y "hace X min" | Prueba unitaria del formateo relativo y del umbral de "sin actualización reciente" (configurable; por defecto 30 min) |
| T5.3 | `FamilyMap` con el adaptador de lista y 🔒📱 el de Google Maps (API key) | Pruebas de widget con el adaptador de lista; 📱 captura del mapa real |
| T5.4 | UI de geocercas, eventos con bandera desactivada y check-in | Pruebas de widget y de casos de uso; flujo sin conexión → bandeja de salida |

## Incremento 6 · SOS y resiliencia

| ID | Tarea | Criterios |
|---|---|---|
| T6.1 | Flujo SOS completo con "Llamar al 123" | Pruebas de widget: la activación accidental (toque corto) no inicia el SOS; se puede cancelar durante la cuenta atrás; cada estado tiene su texto; **nunca** dice "recibido" sin *ack* |
| T6.2 | Function `raiseSos` (idempotente, límite de frecuencia, *payload* FCM sin coordenadas) y *ack* | Pruebas en el emulador: doble envío → una notificación; sin tokens → `notified` con N = 0 |
| T6.3 | 📱 Push real (requiere la clave APNs 🔒) | Verificación manual documentada |

## Incremento 7 · Endurecimiento y entrega

| ID | Tarea | Criterios |
|---|---|---|
| T7.1 | `security-review`, `code-review` y revisión de dependencias (`flutter pub outdated`, licencias) | Hallazgos corregidos o documentados |
| T7.2 | Runbooks: incidentes, desactivar funciones (banderas), reversión de versión y exportación de datos | Documentos revisados |
| T7.3 | README reproducible desde cero y lista de defectos conocidos | Otra sesión limpia sigue el README y pasa todas las pruebas |
| T7.4 | Informe de calidad: qué está probado, qué es manual y qué no está listo para producción | Coincide con los resultados reales de CI |

## Definition of Done del MVP

Es la del prompt maestro. Aquí se añade: **"compila en los entornos disponibles"** significa host Linux más CI. Las compilaciones de Android e iOS se marcan 📱 hasta que exista una máquina con esos SDK o *runners* aprobados.
