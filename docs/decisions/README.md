# Registro de decisiones

Los ADR viven en `docs/architecture/adr-*.md`. Este archivo es el índice y la lista de **decisiones pendientes de aprobación**.

## ADR

| ADR | Tema | Estado |
|---|---|---|
| [ADR-001](../architecture/adr-001-backend.md) | Backend: Firebase frente a Supabase | Propuesto |
| [ADR-002](../architecture/adr-002-mapas.md) | Mapas: abstracción y Google Maps en ambas plataformas para el MVP | Propuesto (se aparta del prompt) |
| [ADR-003](../architecture/adr-003-ubicacion-y-geocercas.md) | Ubicación por fases y geocercas del sistema operativo | Propuesto |
| [ADR-004](../architecture/adr-004-persistencia-y-sincronizacion.md) | Drift como fuente local, bandeja de salida e idempotencia | Propuesto |

## Decisiones que requieren aprobación del propietario

| # | Decisión | Propuesta | Bloquea |
|---|---|---|---|
| D1 | Aprobar la arquitectura y la estructura (`01-arquitectura-propuesta.md`) | Sí | Todo el Día 1 |
| D2 | Backend | Firebase (ADR-001) | Día 4 |
| D3 | Mapas | Google Maps en Android e iOS detrás de una abstracción; MapKit con plugin propio como fase posterior opcional (ADR-002) | T5.3 |
| D4 | Ubicación en segundo plano | Fuera de la semana 1; primer plano y geocercas con bandera (ADR-003) | Días 5 y 6 |
| D5 | Público | **Solo adultos (18+) en el MVP** hasta una revisión legal sobre menores | Onboarding y términos |
| D6 | Métodos de inicio de sesión | Solo correo y contraseña en el MVP | Día 4 |
| D7 | Credenciales y costos | Crear un proyecto Firebase de staging con Blaze, presupuesto y *spend cap*; API keys de Maps; clave APNs | T4.4, T5.3, T6.3 |
| D8 | Plugins de Claude Code | Autorizar "Dart and Flutter" (oficial) y "Design" (Anthropic) | Opcional |
| D9 | Retención de datos | La tabla de `02-modelo-de-datos.md` | Día 4 |
| D10 | Identificador de la app | `org` y *bundle ID* (p. ej. `co.nexofamilia.app`); se puede cambiar antes de publicar | T1.1 |
