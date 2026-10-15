# Registro de decisiones

Los ADR viven en `docs/architecture/adr-*.md`. Este archivo es el índice y la lista de **decisiones pendientes de aprobación**.

## ADR

| ADR | Tema | Estado |
|---|---|---|
| [ADR-001](../architecture/adr-001-backend.md) | Backend: Firebase frente a Supabase | Aceptado (2026-10-15) |
| [ADR-002](../architecture/adr-002-mapas.md) | Mapas: abstracción y Google Maps en ambas plataformas para el MVP | Aceptado (2026-10-15; se aparta del prompt) |
| [ADR-003](../architecture/adr-003-ubicacion-y-geocercas.md) | Ubicación por fases y geocercas del sistema operativo | Aceptado (2026-10-15) |
| [ADR-004](../architecture/adr-004-persistencia-y-sincronizacion.md) | Drift como fuente local, bandeja de salida e idempotencia | Aceptado (2026-10-15) |

## Decisiones del propietario

El 2026-10-15 el propietario aprobó la arquitectura y pidió avanzar de forma progresiva, sin plan por días. Las decisiones D2–D6, D9 y D10 se aplican con la propuesta por defecto. D7 y D8 siguen **pendientes** porque requieren credenciales, pagos o instalar herramientas; mientras tanto se trabaja con emuladores y proyectos `demo-*`.

| # | Decisión | Propuesta | Estado |
|---|---|---|---|
| D1 | Aprobar la arquitectura y la estructura (`01-arquitectura-propuesta.md`) | Sí | Aprobada |
| D2 | Backend | Firebase (ADR-001) | Aplicada |
| D3 | Mapas | Google Maps en Android e iOS detrás de una abstracción; MapKit con plugin propio como fase posterior opcional (ADR-002) | Aplicada |
| D4 | Ubicación en segundo plano | Fuera del MVP inicial; primer plano y geocercas con bandera (ADR-003) | Aplicada |
| D5 | Público | **Solo adultos (18+) en el MVP** hasta una revisión legal sobre menores | Aplicada |
| D6 | Métodos de inicio de sesión | Solo correo y contraseña en el MVP | Aplicada |
| D7 | Credenciales y costos | Crear un proyecto Firebase de staging con Blaze, presupuesto y *spend cap*; API keys de Maps; clave APNs | **Pendiente** (credenciales y pagos) |
| D8 | Plugins de Claude Code | Autorizar "Dart and Flutter" (oficial) y "Design" (Anthropic) | **Pendiente** (instalación de plugins) |
| D9 | Retención de datos | La tabla de `02-modelo-de-datos.md` | Aplicada |
| D10 | Identificador de la app | `org` y *bundle ID* (p. ej. `co.nexofamilia.app`); se puede cambiar antes de publicar | Aplicada: `co.nexofamilia.app` |
