# Runbook · Incidentes y operación

> **Estado:** borrador para cuando exista el proyecto real de Firebase (decisión D7). Hoy no hay producción. Los comandos de despliegue requieren credenciales del propietario y nunca se ejecutan desde una sesión automática sin su aprobación.

## 1. Primera respuesta

| Severidad | Ejemplos | Respuesta |
|---|---|---|
| **S1** | Una persona ve datos de otra familia; ubicaciones expuestas; el SOS no se registra para nadie | Contener en minutos (sección 3), avisar al propietario y documentar la línea de tiempo |
| **S2** | Las notificaciones SOS no llegan; los check-ins no se envían; picos de costo | Diagnóstico (sección 2) y corrección en horas |
| **S3** | Errores visuales, textos incorrectos o lentitud | Siguiente versión |

Reglas que no cambian durante un incidente:
- **No** pedir a nadie su ubicación, capturas con mapas ni datos personales para depurar. Los registros solo tienen operación y código de error (`SafeLogger` en la app y `callable.failed` en las Functions).
- **No** anunciar a las familias nada que no esté verificado. El aviso debe decir qué falló, desde cuándo y qué hacer mientras tanto (p. ej., «llama al 123»).

## 2. Diagnóstico por síntoma

### El SOS se registra pero no notifica

- **Qué ve la persona:** «Alerta registrada», pero sin «Aviso enviado a N dispositivos». Si el envío falló, un error transitorio que la app reintenta sola.
- **Qué revisar:**
  1. Registros de Functions: `callable.failed` con `operation: raiseSos` y su `code`.
  2. Estado de FCM y de la clave APNs (en iOS, una clave vencida o revocada corta todos los avisos).
  3. Que los demás integrantes tengan documentos en `users/{uid}/devices`. Sin documentos, la persona no activó los avisos (Inicio se lo pide) o los denegó en el teléfono.
  4. En Firestore, la alerta con `notifiedCount: null` y `notifyStartedAt` reciente indica un envío en curso o fallido. El reintento del cliente la completa cuando pasa el *lease* de 60 s.
- **Qué no hacer:** marcar alertas como notificadas a mano. `notifiedCount` cuenta los mensajes **aceptados** por FCM.

### Los check-ins o eventos de zona no se envían

- Se acumulan en la bandeja local con su estado visible en la app.
- Si fallan con `permission-denied`, se marcan como fallidos (permanente): revisar si un despliegue de reglas cambió las condiciones de `families/{f}/events`. Las pruebas de reglas y de mutación (`npm test`, `npm run test:mutations`) deben pasar antes de cualquier despliegue.

### Pico de costos

- Las alertas de presupuesto están al 50/90/100 %. Las Functions tienen `maxInstances: 10`.
- Firestore no se puede limitar: revisar lecturas por colección. La causa probable es un cliente que reabre escuchas en bucle. El espejo reconecta con espera exponencial, así que un bucle indica un defecto nuevo.

## 3. Contención (interruptores)

Del más rápido al más lento:

1. **Reglas de Firestore.** Es el interruptor inmediato y aplica a todos los clientes en ~1 min. Por ejemplo, para cortar escrituras de eventos, cambiar en `families/{f}/events` `allow create: if ...` por `allow create: if false;` y desplegar solo las reglas:
   ```bash
   npx firebase deploy --only firestore:rules
   ```
   Cualquier cambio de reglas se hace en una rama, con las pruebas de reglas en verde, aunque sea urgente.
2. **Functions.** Desplegar la versión anterior desde su commit (sección 4). Para apagar una sola función, quitar su `export` en `functions/src/index.ts` y desplegar: la app recibe `not-found` / `unavailable`, que trata como error honesto.
3. **App.** Las banderas de la app son de compilación (`--dart-define`, ver `config/env.example.json`): cambiarlas exige publicar una versión. **Pendiente:** banderas remotas (p. ej. Remote Config) si se necesitan interruptores sin publicar.

Exposición de datos (S1):
- Revocar sesiones de las cuentas afectadas con el Admin SDK (`revokeRefreshTokens(uid)`).
- Si una persona salió de una familia y aún ve datos, comprobar que `leaveFamily` borró su membresía. Las reglas niegan el acceso al instante y la app purga su caché al recibir `permission-denied`.

## 4. Reversión de versión

| Pieza | Cómo revertir |
|---|---|
| Reglas e índices | `git checkout <commit-bueno> -- firestore/` y `npx firebase deploy --only firestore:rules,firestore:indexes` |
| Functions | `git checkout <commit-bueno>` en un *worktree*, `npm ci && npm run build` en `functions/` y `npx firebase deploy --only functions` |
| App Android | Detener el despliegue escalonado en Play Console y publicar la versión anterior con un `versionCode` mayor |
| App iOS | Pausar la publicación por fases en App Store Connect; una versión anterior no se puede «reinstalar», hay que publicar una corrección |

Compatibilidad: el contrato (`docs/architecture/05-api-backend.md`) solo admite cambios **aditivos** mientras haya versiones de la app en circulación. Una función o un campo nuevo no puede ser obligatorio para clientes antiguos.

## 5. Solicitudes de datos personales

La app permite **eliminar la cuenta** (`deleteAccount`):
- borra al instante perfil, dispositivos, membresías, ubicación y consentimientos;
- borra los check-ins y eventos de zona de la persona;
- quita las coordenadas de sus alertas;
- anonimiza la auditoría.

El resto vence por TTL (ver `02-modelo-de-datos.md`).

**Pendiente:** exportación de datos en la app (derecho de acceso, Ley 1581 de 2012 en Colombia). Mientras no exista, una solicitud se atiende manualmente con el Admin SDK, leyendo solo estas rutas de la persona:

- `users/{uid}` y sus subcolecciones;
- `families/{f}/members/{uid}`, `consents/{uid}` y `locations/{uid}`;
- los eventos y alertas con `actorUid` / `uid` igual a su identificador.

Se entrega por un canal seguro y no se conserva copia.

## 6. Después del incidente

- Una nota breve en `docs/architecture/revisiones.md` con causa raíz, prueba que lo habría detectado y corrección.
- Si faltaba una prueba, añadirla antes de cerrar (reglas: también una mutación nueva en `functions/scripts/mutate_rules.mjs`).
