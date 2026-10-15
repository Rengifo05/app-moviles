# ADR-004 · Persistencia local y sincronización

- **Estado:** Aceptado (2026-10-15)
- **Fecha:** 2026-10-15

## Contexto

La app debe funcionar sin conexión con datos locales seguros, avisar qué funciones remotas no están disponibles y manejar reintentos, duplicados, desorden y conflictos. El SOS en particular exige un **estado observable por operación**: preparando, en cola, enviando, enviado, notificado, confirmado o fallido. La cola interna de escrituras de Firestore no lo ofrece, y las llamadas a Cloud Functions no se encolan sin conexión.

## Decisión propuesta

1. **Drift + SQLite como fuente local de verdad para la UI.** Los widgets y controladores leen *streams* de Drift, nunca de Firestore.
2. **Bandeja de salida (*outbox*) en Drift** para toda operación remota con efecto: check-in, SOS, evento de geocerca, cambio de consentimiento. Campos: `id`, `kind`, `idempotencyKey` (UUID v7), `payload` (JSON sin datos de más), `status`, `attempts`, `nextAttemptAt`, `lastErrorCode` y `createdAt`.
3. **Sincronizador** (servicio de la capa `data`):
   - Procesa la bandeja en orden de creación, por tipo, y da **prioridad al SOS**.
   - Usa espera exponencial con *jitter*: 2 s, 4 s, 8 s… hasta 5 min, y para el SOS hasta 30 s.
   - Clasifica los errores: **temporales** (red, `unavailable`, `deadline-exceeded`), que se reintentan, y **permanentes** (`permission-denied`, validación), que se marcan como fallidos y se muestran con una acción concreta.
   - **Idempotencia:** el `idempotencyKey` es el ID del documento en Firestore. Los documentos de solo inserción (eventos) se escriben con `RemoteWrite.create`: si el documento ya existe, el reintento se da por entregado (las reglas prohíben modificarlos, así que un `set` repetido sería rechazado). La ubicación admite reenviar la misma captura (`capturedAt >=`). Las funciones *callable* son idempotentes por su propio identificador (p. ej. `alertId` en `raiseSos`).
4. **Lecturas remotas a Drift:** los *listeners* de Firestore (solo de la familia activa y solo con la app en primer plano) actualizan las tablas de caché (`members`, `latest_locations`, `geofences`, `recent_events`). Cada fila guarda `syncedAt` para mostrar si los datos están desactualizados.
5. **Conflictos:**
   - La ubicación usa *last-writer-wins* por `capturedAt`, validado también por las reglas.
   - Los eventos (check-in, SOS, geocerca) son de **solo inserción**, así que no hay conflictos de edición.
   - Las geocercas y los perfiles usan control de versión (`version` entero). La regla exige `request.resource.data.version == resource.data.version + 1`. Si falla, el cliente recarga y muestra "Otro integrante cambió esta zona".
6. **Conectividad:** `connectivity_plus` solo sirve como indicio para la UI. La verdad la da el resultado real de las operaciones: una red disponible no garantiza conexión al backend.
7. **Caché de Firestore:** se mantiene con tamaño acotado como optimización de costo al reanudar *listeners*, pero la UI no depende de ella. Dos ajustes en el adaptador (`FirestoreRemoteStore`):
   - Las escrituras usan **transacciones** con tiempo límite, que fallan sin conexión. Un `WriteBatch` quedaría en la cola interna de Firestore sin fallar y se vería como aplicado antes de que el servidor lo aceptara. Eso bloquearía la bandeja (y el SOS detrás) y permitiría confirmaciones falsas.
   - Las escuchas piden metadatos: una instantánea servida desde la caché local no se trata como dato fresco. Se emite como señal `offlineSignal`, que no es terminal, y el espejo pasa a `offline`. El aviso de la interfaz espera unos segundos antes de mostrarse, para no parpadear al arrancar.
8. **Cierre de sesión o salida del grupo:** se borran las tablas de caché y la bandeja de esa familia. Los SOS pendientes que no se puedan enviar se reportan antes de confirmar el cierre.

## Consecuencias

- La caché queda duplicada (Drift y Firestore), un costo aceptable a cambio de estados honestos y pruebas deterministas sin red.
- El sincronizador es el componente más delicado: tendrá pruebas unitarias con reloj y red simulados (T3.4 y T6.2).
- La base de datos local se excluye del *auto-backup* de Android y se guarda en el directorio de soporte de la app en iOS, excluido de iCloud (ver el modelo de amenazas).
