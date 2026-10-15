# 05 · Contrato del backend

Este documento es el **contrato único** que cumplen:

- las Cloud Functions (`functions/src/`, TypeScript),
- el backend de demostración (`lib/infrastructure/demo/`, Dart),
- las reglas de Firestore (`firestore/firestore.rules`),
- y los repositorios de la app (`lib/features/*/data/`).

Cualquier cambio aquí exige actualizar las cuatro piezas y sus pruebas.

## Convenciones

- Los campos usan `camelCase`. Las fechas son `Timestamp` en Firestore (`DateTime` UTC en Dart). Las que fija el servidor se escriben con `serverTimestamp()`.
- Los IDs que genera el cliente son UUID v7 y sirven como claves de idempotencia.
- Los errores de las funciones usan los códigos de `HttpsError` (`unauthenticated`, `permission-denied`, `invalid-argument`, `not-found`, `already-exists`, `failed-precondition`, `resource-exhausted`). En `details.reason` va un código estable en `kebab-case`, que la app traduce a un mensaje.
- **Las coordenadas nunca aparecen en registros, notificaciones push ni mensajes de error.**
- Los nombres (familia, zona, perfil) tienen entre 1 y 40 caracteres y al menos una letra o un dígito. El cliente **recorta los espacios antes de escribir**, porque las reglas miden el texto tal cual.
- El cliente envía el código de invitación ya normalizado (`FamilyRules.normalizeCode`).
- `createInvitation` devuelve `expiresAt` en **milisegundos desde la época** (UTC).

## Documentos

```text
users/{uid}                                   { displayName, createdAt, adultConfirmedAt, privacyAcceptedAt, privacyPolicyVersion }
users/{uid}/memberships/{familyId}            { familyId, familyName, role, joinedAt }            ← solo Functions
users/{uid}/devices/{deviceId}                { token, platform, updatedAt }
families/{familyId}                           { name, createdBy, createdAt, memberCount }         ← solo Functions
families/{familyId}/members/{uid}             { uid, displayName, role, joinedAt }                ← solo Functions
families/{familyId}/consents/{uid}            { state, precision, updatedAt }
families/{familyId}/locations/{uid}           { lat, lng, accuracyM, capturedAt, receivedAt, approximate }
families/{familyId}/geofences/{geofenceId}    { name, lat, lng, radiusM, createdBy, version, updatedAt }
families/{familyId}/events/{eventId}          ver "Eventos"
families/{familyId}/emergencies/{alertId}     { uid, createdAt, lat?, lng?, accuracyM?, notifiedCount, acks: { [uid]: Timestamp }, resolvedAt }
families/{familyId}/audit/{auditId}           { action, actorUid, targetUid?, createdAt }         ← solo Functions
invitations/{tokenHash}                       { familyId, createdBy, createdAt, expiresAt, maxUses, uses, status }  ← solo Functions
rateLimits/{uid}                              contadores por ventana                              ← solo Functions
idempotency/{key}                             resultado previo de una llamada                     ← solo Functions
```

Valores enumerados:

- `role`: `owner` | `admin` | `member`
- `consents.state`: `notConfigured` | `sharing` | `paused`
- `consents.precision`: `exact` | `approximate`
- `invitations.status`: `active` | `exhausted` | `revoked`

### Eventos (historial familiar)

| `type` | Campos | Lo crea |
|---|---|---|
| `checkIn` | `actorUid`, `kind` (`ok` / `needHelp`), `message?`, `lat?`, `lng?`, `createdAt`, `clientCreatedAt` | El cliente (autor) |
| `geofence` | `actorUid`, `geofenceId`, `geofenceName`, `transition` (`enter` / `exit`), `createdAt`, `clientCreatedAt` | El cliente (autor) |
| `sos` | `actorUid`, `alertId`, `createdAt` | `raiseSos` |
| `membership` | `actorUid`, `change` (`joined` / `left` / `removed`), `targetUid?`, `createdAt` | Functions |

Todos llevan `expireAt` para la política TTL: 30 días para los eventos y 90 para el SOS. Cuando lo escribe el cliente, las reglas exigen `expireAt <= request.time + 31 días` (1 día de tolerancia para relojes adelantados). Las alertas (`emergencies`), la auditoría (180 días) y las invitaciones (7 días tras vencer) también llevan `expireAt`, que fijan las Functions.

## Funciones *callable*

| Función | Entrada | Resultado | Reglas y errores (`details.reason`) |
|---|---|---|---|
| `createFamily` | `{ name }` | `{ familyId }` | Nombre de 1 a 40 caracteres (`family-name-invalid`). Máximo 5 familias por usuario (`too-many-families`). Crea la familia, la membresía `owner`, el consentimiento `notConfigured` y la auditoría |
| `createInvitation` | `{ familyId }` | `{ invitationId, code, expiresAt, maxUses }` | Solo `owner` o `admin` (`not-allowed`). El código es de 10 caracteres del alfabeto `ABCDEFGHJKMNPQRSTUVWXYZ23456789`; se guarda solo su SHA-256. Vence a las 48 h y admite un uso. Máximo 10 invitaciones activas por familia (`too-many-invitations`) |
| `acceptInvitation` | `{ code }` | `{ familyId }` | Máximo 10 intentos por hora por usuario (`rate-limited`). Si el código no existe, venció, está agotado o revocado, responde siempre `invitation-invalid`, para no confirmar si existe. También: `already-member` y `family-full` (12 integrantes). La transacción incrementa `uses` |
| `leaveFamily` | `{ familyId }` | `{}` | Borra la membresía, la ubicación y el consentimiento en una transacción. Si sale el `owner`, el integrante más antiguo pasa a `owner`. Si sale el último, se borra la familia |
| `removeMember` | `{ familyId, uid }` | `{}` | El `owner` puede expulsar a cualquiera menos a sí mismo; un `admin` solo a `member` (`not-allowed`). Mismo borrado que `leaveFamily` |
| `raiseSos` | `{ familyId, alertId, lat?, lng?, accuracyM? }` | `{ alertId, notifiedCount, alreadyExisted }` | Exige ser miembro. Idempotente: si `alertId` ya existe y es del mismo usuario, devuelve el resultado guardado sin volver a notificar. Máximo 5 por hora (`rate-limited`). Notifica por FCM a los dispositivos de los demás integrantes con un texto **genérico y sin ubicación**; `notifiedCount` cuenta los mensajes **aceptados** por FCM |
| `deleteAccount` | `{}` | `{}` | Ejecuta `leaveFamily` en todas sus familias; en cada una borra sus check-ins y eventos de zona, quita `lat`/`lng`/`accuracyM` de sus alertas y cambia su `uid` en la auditoría por `deleted-user`. Después borra `users/{uid}` con sus subcolecciones y elimina el usuario de Auth |

## Escrituras directas del cliente (validadas por reglas)

| Ruta | Operación | Condiciones |
|---|---|---|
| `users/{uid}` | crear/actualizar | `uid == auth.uid`; solo campos del perfil |
| `users/{uid}/devices/{id}` | crear/actualizar/borrar | `uid == auth.uid` |
| `families/{f}/consents/{uid}` | actualizar | `uid == auth.uid`, miembro de `f`; `state` y `precision` válidos; `updatedAt == request.time` |
| `families/{f}/locations/{uid}` | crear/actualizar | `uid == auth.uid`, miembro; consentimiento `sharing` (después del lote); coordenadas en rango; `accuracyM` entre 0 y 100 000; `capturedAt` igual o posterior al almacenado (reenviar la misma captura es inocuo) y anterior a `request.time + 1 h` (tolera relojes adelantados, no fechas absurdas); `receivedAt == request.time` |
| `families/{f}/locations/{uid}` | borrar | `uid == auth.uid` (al pausar, en el mismo lote que el consentimiento) |
| `families/{f}/geofences/{id}` | crear/actualizar/borrar | `owner` o `admin`; radio entre 100 y 2000 m; nombre de 1 a 40 caracteres; `version` = anterior + 1 |
| `families/{f}/events/{id}` | crear | Miembro; `actorUid == auth.uid`; `type` en `checkIn` o `geofence`; `createdAt == request.time`. Nunca se actualiza ni se borra desde el cliente |
| `families/{f}/emergencies/{id}` | actualizar | Otro miembro: solo añade `acks.{auth.uid} = request.time`. El autor: solo fija `resolvedAt = request.time` |

Todo lo demás queda **denegado por defecto**.
