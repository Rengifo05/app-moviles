# Nexo Familia

> La seguridad de tu familia, en un solo lugar. *(Nombre provisional y configurable.)*

Aplicación móvil (Flutter, iOS y Android) para compartir ubicación de forma voluntaria, crear zonas seguras, hacer check-ins y avisar a la familia en una emergencia. **No garantiza la seguridad de nadie ni sustituye a los servicios oficiales de emergencia.**

## Estado actual

**MVP funcional con el backend de demostración; no listo para producción.**
- **Funcionalidades:** bienvenida, cuenta, familias con invitaciones, ubicación compartida con consentimiento, zonas, check-ins, SOS con confirmación de lectura, actividad y ajustes de privacidad.
- **Pruebas:** 1196 de la app (incluidos 6 escenarios de extremo a extremo) y 94 del backend en el emulador; las reglas detectan 41 de 41 mutaciones.
- **Pendiente:**
  - proyecto Firebase real, mapas y push (decisión D7);
  - verificación en dispositivos.

Detalle en el [informe de calidad](docs/architecture/06-informe-de-calidad.md) y en el [plan por incrementos](docs/architecture/04-plan-y-criterios.md).

## Cómo empezar

Requisitos: Flutter **3.47.7** (Dart 3.13.5). En Linux, `tool/install_flutter.sh` instala exactamente esa versión y verifica su SHA-256.

```bash
tool/install_flutter.sh            # opcional: instala Flutter en /opt/flutter
export PATH=/opt/flutter/bin:$PATH
flutter pub get                    # dependencias + localización generada
tool/check.sh                      # formato, análisis estricto y pruebas (igual que CI)
```

Para ejecutar la app en un dispositivo o emulador (requiere Android Studio o Xcode):

```bash
cp config/env.example.json config/env.dev.json   # no se versiona
flutter run --dart-define-from-file=config/env.dev.json
```

Con `NX_BACKEND=demo` la app funciona sin red ni credenciales, con datos en memoria y ubicaciones sintéticas (nunca usa el GPS). Con `NX_BACKEND=firebase` y `NX_USE_EMULATORS=true` usa los emuladores locales de Firebase (proyecto `demo-nexo`, sin credenciales): ver [el runbook](docs/runbooks/entorno-de-desarrollo.md#app-contra-los-emuladores-de-firebase). Un proyecto real de Firebase está pendiente de la decisión D7.

Backend (reglas y Cloud Functions), con Node 22 y Java 21:

```bash
tool/check_backend.sh              # tipos, índices, compilación y pruebas en el emulador
(cd functions && npm run test:mutations)   # pruebas de mutación de las reglas
```

## Documentación

| Documento | Contenido |
|---|---|
| [docs/architecture/00-descubrimiento.md](docs/architecture/00-descubrimiento.md) | Estado del repositorio y del entorno, versiones verificadas, prueba de compatibilidad de dependencias y herramientas de Claude Code |
| [docs/architecture/01-arquitectura-propuesta.md](docs/architecture/01-arquitectura-propuesta.md) | Capas, estructura de carpetas, estado, navegación, dirección visual y riesgos |
| [docs/architecture/02-modelo-de-datos.md](docs/architecture/02-modelo-de-datos.md) | Entidades, estructura en Firestore, matriz de acceso, máquina de estados del SOS y retención |
| [docs/architecture/03-costos.md](docs/architecture/03-costos.md) | Estimación de costos por familia, costos fijos y controles |
| [docs/architecture/04-plan-y-criterios.md](docs/architecture/04-plan-y-criterios.md) | Plan por incrementos con tareas y criterios de aceptación |
| [docs/architecture/05-api-backend.md](docs/architecture/05-api-backend.md) | Contrato del backend: documentos, funciones y reglas |
| [docs/architecture/06-informe-de-calidad.md](docs/architecture/06-informe-de-calidad.md) | Qué está probado, qué es manual y por qué no está listo para producción |
| [docs/architecture/revisiones.md](docs/architecture/revisiones.md) | Revisiones adversariales y defectos corregidos |
| [docs/architecture/adr-00*.md](docs/architecture/) | Decisiones: backend, mapas, ubicación y sincronización |
| [docs/privacy/](docs/privacy/) | Modelo de amenazas; datos, permisos y marco legal |
| [docs/decisions/README.md](docs/decisions/README.md) | Índice de ADR y **decisiones pendientes de aprobación** |
| [docs/runbooks/entorno-de-desarrollo.md](docs/runbooks/entorno-de-desarrollo.md) | Cómo preparar el entorno |
| [docs/runbooks/incidentes-y-operacion.md](docs/runbooks/incidentes-y-operacion.md) | Incidentes, interruptores, reversión de versiones y solicitudes de datos |

## Stack propuesto (versiones verificadas el 2026-10-15)

Flutter 3.47.7 / Dart 3.13.5 · Riverpod 3.4 · GoRouter 18.1 · Drift 2.35 · Firebase (Auth, Firestore, Functions, FCM) · Google Maps detrás de una abstracción propia. Detalles y justificación en los documentos anteriores.
