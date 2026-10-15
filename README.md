# Nexo Familia

> La seguridad de tu familia, en un solo lugar. *(Nombre provisional y configurable.)*

Aplicación móvil (Flutter, iOS y Android) para compartir ubicación de forma voluntaria, crear zonas seguras, hacer check-ins y avisar a la familia en una emergencia. **No garantiza la seguridad de nadie ni sustituye a los servicios oficiales de emergencia.**

## Estado actual

**Fase 0: descubrimiento y propuesta de arquitectura.** Este repositorio todavía no contiene código de la aplicación. El primer paso fue inspeccionar el entorno, verificar versiones y dependencias, y documentar la arquitectura, los riesgos y el plan para su aprobación.

| Documento | Contenido |
|---|---|
| [docs/architecture/00-descubrimiento.md](docs/architecture/00-descubrimiento.md) | Estado del repositorio y del entorno, versiones verificadas, prueba de compatibilidad de dependencias y herramientas de Claude Code |
| [docs/architecture/01-arquitectura-propuesta.md](docs/architecture/01-arquitectura-propuesta.md) | Capas, estructura de carpetas, estado, navegación, dirección visual y riesgos |
| [docs/architecture/02-modelo-de-datos.md](docs/architecture/02-modelo-de-datos.md) | Entidades, estructura en Firestore, matriz de acceso, máquina de estados del SOS y retención |
| [docs/architecture/03-costos.md](docs/architecture/03-costos.md) | Estimación de costos por familia, costos fijos y controles |
| [docs/architecture/04-plan-y-criterios.md](docs/architecture/04-plan-y-criterios.md) | Plan de 7 días con tareas y criterios de aceptación |
| [docs/architecture/adr-00*.md](docs/architecture/) | Decisiones: backend, mapas, ubicación y sincronización |
| [docs/privacy/](docs/privacy/) | Modelo de amenazas; datos, permisos y marco legal |
| [docs/decisions/README.md](docs/decisions/README.md) | Índice de ADR y **decisiones pendientes de aprobación** |
| [docs/runbooks/entorno-de-desarrollo.md](docs/runbooks/entorno-de-desarrollo.md) | Cómo preparar el entorno |

## Stack propuesto (versiones verificadas el 2026-10-15)

Flutter 3.47.7 / Dart 3.13.5 · Riverpod 3.4 · GoRouter 18.1 · Drift 2.35 · Firebase (Auth, Firestore, Functions, FCM) · Google Maps detrás de una abstracción propia. Detalles y justificación en los documentos anteriores.
