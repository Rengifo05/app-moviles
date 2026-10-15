# ADR-001 · Backend administrado: Firebase frente a Supabase

- **Estado:** Propuesto. Pendiente de aprobación, porque implica una cuenta de facturación y credenciales.
- **Fecha:** 2026-10-15
- **Decisores:** propietario del producto y responsable técnico

## Contexto

Nexo Familia necesita: autenticación, grupos familiares con aislamiento estricto, ubicación más reciente por integrante, geocercas, eventos (check-in, entradas y salidas, SOS), notificaciones push, lógica confiable en el servidor (invitaciones, SOS, altas y bajas de miembros) y pruebas automatizadas de las reglas de acceso. No queremos operar servidores propios en esta etapa.

Restricciones verificadas en el entorno (ver `00-descubrimiento.md`): el **emulador de Firestore funciona aquí**; el stack local de Supabase necesita Docker, que no tiene el daemon activo en este contenedor.

## Comparación

> Las cifras de precio se tomaron el 2026-10-15 de resultados de búsqueda que citan las páginas oficiales, porque `firebase.google.com` y `supabase.com` no eran accesibles desde el contenedor. **Hay que reconfirmarlas antes de activar la facturación.**

| Criterio | Firebase (Auth + Firestore + Functions + FCM) | Supabase (Auth + Postgres + Edge Functions) |
|---|---|---|
| Costo sin uso | Plan Spark gratis. Firestore: 50 000 lecturas, 20 000 escrituras y 20 000 borrados al día, más 1 GiB | Plan Free gratis: base de datos de 500 MB y 50 000 MAU. **El proyecto se pausa tras 7 días sin actividad** |
| Costo con uso | Blaze por uso, conservando las cuotas gratuitas. Firestore Standard (us-central1): USD 0,03/100k lecturas, 0,09/100k escrituras y 0,01/100k borrados. Otras regiones cuestan distinto | Pro: USD 25/mes más excedentes. Límite de gasto activado por defecto |
| Lógica en el servidor | Cloud Functions (TypeScript). **Desplegarlas exige Blaze** con cuenta de facturación; emularlas es gratis. Cuota gratuita: 2 M de invocaciones al mes | Edge Functions (Deno) y funciones de Postgres. Incluidas en Free y Pro dentro de sus límites |
| Control de gasto | Las alertas de presupuesto **no detienen el gasto**. Cloud Functions admite *spend caps*; Firestore no | *Spend cap* nativo en Pro |
| Reglas de acceso | Security Rules declarativas, verificables con `@firebase/rules-unit-testing` **en este entorno**. Cada `get()`/`exists()` dentro de una regla se factura como lectura | RLS de Postgres: muy expresiva y basada en SQL estándar. Pruebas con pgTAP o el stack local (Docker) |
| Sin conexión | El SDK trae caché local y cola de escrituras pendientes | Sin sincronización sin conexión integrada en Flutter |
| Tiempo real | Listeners de snapshots | Realtime (cambios de Postgres o broadcast), con límites de conexiones y mensajes |
| Push | FCM nativo | **También requiere FCM**, es decir, un proyecto de Firebase igualmente |
| Exportación y copias | Exportación administrada a Cloud Storage (requiere Blaze). Formato propietario | `pg_dump` estándar; copias diarias en Pro. Más portable |
| Dependencia del proveedor | Alta (modelo de documentos propietario) | Menor (Postgres de código abierto, autoalojable) |
| Consultas geoespaciales | Limitadas (geohash) | PostGIS. No las necesitamos en el MVP: las geocercas se evalúan en el dispositivo (ADR-003) |
| Región de datos | `southamerica-east1` (São Paulo) disponible | `sa-east-1` (São Paulo) disponible |

## Decisión propuesta

**Firebase** para el MVP: Authentication, Cloud Firestore (edición Standard), Cloud Functions (TypeScript, 2.ª generación), Cloud Messaging y, después, App Check.

Motivos:

1. FCM es imprescindible en ambas opciones; con Firebase hay una sola consola, una sola identidad y un solo conjunto de credenciales.
2. Las reglas de acceso y el aislamiento entre familias **se pueden probar en este entorno** con el emulador, que es un requisito del *Definition of Done*.
3. El modelo de datos del MVP es pequeño, centrado en documentos y casi sin consultas relacionales. El costo estimado es bajo (ver `03-costos.md`).
4. El plan Free de Supabase pausa los proyectos inactivos. Aceptable en desarrollo, pero inadecuado para una función de seguridad en producción sin pagar Pro.

## Mitigación de la dependencia del proveedor

- La app no importa `cloud_firestore` ni `firebase_auth` fuera de `features/*/data/` y `app/bootstrap`. Una prueba de arquitectura (T1.4) lo hace cumplir.
- Los contratos de repositorio y los DTO se mapean a entidades de dominio puras.
- Drift es la fuente local de verdad para la UI (ADR-004). El backend se puede sustituir reimplementando la capa `data`.
- El runbook de exportación (`docs/runbooks/`, Día 7) documenta cómo exportar a JSON o CSV y la ruta de migración a Postgres.

## Consecuencias

- **Costo y credenciales (requiere aprobación):** desplegar Cloud Functions (invitaciones, SOS, bajas de miembros) exige plan Blaze con tarjeta. Mientras tanto, todo el desarrollo y las pruebas funcionan con emuladores y proyectos `demo-*`, que no necesitan credenciales.
- Hay que configurar alertas de presupuesto **y** *spend cap* en Cloud Functions, porque Firestore no se puede limitar.
- Las reglas deben evitar `get()` innecesarios, que suman lecturas facturables.
- La autenticación por SMS se factura por mensaje y requiere Blaze. **No se usará en el MVP.** Se usará correo y contraseña; si se añade Google, también Apple (ver la sección de riesgos en `01-arquitectura-propuesta.md`).

## Alternativas descartadas por ahora

- **Supabase:** se reevalúa si aparecen necesidades relacionales o geoespaciales fuertes en el servidor, o si la dependencia del proveedor se vuelve prioritaria.
- **Backend propio:** se descarta hasta que haya una razón operativa clara.
