# 02 · Modelo de datos inicial

- **Estado:** Propuesta
- Los identificadores generados en el cliente son **UUID v7**: ordenables por tiempo y aptos como claves de idempotencia.
- Las fechas se guardan en UTC. `createdAt` y `receivedAt` los pone el servidor con `serverTimestamp`; `capturedAt` viene del dispositivo.

## Entidades de dominio

| Entidad | Campos principales | Estados / notas |
|---|---|---|
| `UserProfile` | `uid`, `displayName`, `avatarColor`, `createdAt` | Sin teléfono ni fecha de nacimiento en el MVP |
| `FamilyGroup` | `id`, `name`, `createdBy`, `createdAt`, `memberCount` | |
| `FamilyMembership` | `familyId`, `uid`, `role`, `status`, `displayName`, `joinedAt` | `role`: owner / admin / member; `status`: active (las bajas se borran) |
| `Invitation` | `id`, `familyId`, `tokenHash`, `createdBy`, `expiresAt`, `maxUses`, `uses`, `status` | `status`: active / exhausted / revoked / expired. El token en claro **solo se devuelve una vez** al creador |
| `LocationSharingConsent` | `familyId`, `uid`, `state`, `precision`, `updatedAt` | `state`: sharing / paused / never; `precision`: exact / approximate (redondeo ≈ 1 km) |
| `LocationUpdate` (última) | `uid`, `lat`, `lng`, `accuracyM`, `capturedAt`, `receivedAt`, `source` | **Un documento por integrante y se sobrescribe**; no hay historial por defecto |
| `Geofence` | `id`, `familyId`, `name`, `center`, `radiusM`, `createdBy`, `version`, `updatedAt` | `radiusM` entre 100 y 2000; máximo 10 por familia en el MVP |
| `GeofenceEvent` | `id` (clientEventId), `geofenceId`, `uid`, `type`, `occurredAt`, `receivedAt` | `type`: enter / exit; solo inserción |
| `CheckIn` | `id`, `uid`, `kind`, `message?`, `createdAt` | `kind`: ok ("Estoy bien") / needHelp ("Necesito ayuda") |
| `EmergencyEvent` (SOS) | `id`, `uid`, `status`, `location?`, `createdAt`, `notifiedCount`, `acks[]` | Ver la máquina de estados abajo |
| `TrustedContact` | Fuera del MVP (contactos externos a la familia por SMS o correo) | Se pospone: implica costos de SMS y consentimiento de terceros |
| `NotificationPreference` | `uid`, `sos`, `checkIns`, `geofences`, `lockScreenDetail` | `lockScreenDetail`: ocultar el contenido en la pantalla de bloqueo |
| `DeviceRegistration` | `uid`, `deviceId`, `fcmToken`, `platform`, `updatedAt` | Solo visible para el propio usuario y las Functions |
| `AuditEvent` | `id`, `familyId`, `actorUid`, `action`, `targetUid?`, `createdAt` | Solo lo escriben las Functions: altas, bajas, invitaciones, cambios de rol |

## Estructura en Firestore

```text
users/{uid}                                  perfil propio
users/{uid}/devices/{deviceId}               tokens FCM
users/{uid}/private/notificationPrefs
families/{familyId}
families/{familyId}/members/{uid}            ← solo Functions escriben
families/{familyId}/invitations/{invId}      ← solo Functions escriben/leen
families/{familyId}/consents/{uid}           ← solo el propio uid escribe
families/{familyId}/locations/{uid}          ← solo el propio uid escribe, si su consentimiento = sharing
families/{familyId}/geofences/{geofenceId}   ← owner/admin escriben
families/{familyId}/events/{eventId}         ← check-ins y geocercas (solo inserción por el autor)
families/{familyId}/emergencies/{sosId}      ← creación vía Function; acks por miembros
families/{familyId}/audit/{auditId}          ← solo Functions escriben; owner/admin leen
idempotency/{key}                            ← solo Functions
```

## Matriz de acceso (que verificarán las pruebas de reglas)

| Recurso | Leer | Crear o modificar |
|---|---|---|
| `families/{f}` y subcolecciones | Solo **miembros activos de f** | Según la fila |
| `members` | Miembros de f | **Nunca desde el cliente** (Functions: aceptar invitación, salir, expulsar) |
| `invitations` | Nadie desde el cliente | Function `createInvitation` (owner/admin) y `acceptInvitation` (token) |
| `consents/{uid}` | Miembros de f | Solo `uid == auth.uid` y miembro de f |
| `locations/{uid}` | Miembros de f | Solo `uid == auth.uid`, miembro, consentimiento `sharing` y `capturedAt` posterior al almacenado. Coordenadas en rango válido |
| `geofences` | Miembros de f | owner/admin; `version` incremental; radio en rango |
| `events` | Miembros de f | Crear: `actorUid == auth.uid`, tipo permitido, ID = clientEventId. Nunca modificar ni borrar desde el cliente |
| `emergencies` | Miembros de f | Crear: Function `raiseSos`. Cliente: solo añadir su propio *ack* |
| `users/{uid}` y sus subcolecciones | Solo el propio uid | Solo el propio uid (los campos de rol no existen aquí) |

Casos negativos obligatorios: usuario sin sesión, usuario de otra familia, ex miembro, miembro intentando escribir la ubicación de otro, ubicación con consentimiento en pausa, ubicación con `capturedAt` antiguo y miembro intentando modificar `members`.

## Máquina de estados del SOS

```text
preparing ──(cancelar)──▶ cancelled
    │ confirmación deliberada (mantener pulsado 2 s + cuenta atrás de 5 s cancelable)
    ▼
queued ──(sin conexión: se muestra "No enviado: sin conexión" + botón "Llamar al 123")
    │ hay conexión
    ▼
sending ──(error permanente)──▶ failed (con motivo y acción)
    │ la Function confirma que guardó el evento
    ▼
sent ("Alerta registrada")
    │ FCM aceptó N mensajes (aceptado ≠ entregado)
    ▼
notified ("Aviso enviado a N dispositivos"; si N = 0 → "Nadie pudo ser notificado")
    │ un integrante pulsa "Lo vi"
    ▼
acknowledged ("Ana confirmó que lo vio a las 14:32")
```

- Nunca se muestra "recibido" ni "ayuda en camino" sin un *ack* explícito.
- La app **no contacta a servicios de emergencia**. Siempre ofrece "Llamar al 123" (línea única de emergencias de Colombia), configurable por país.
- Idempotencia: el `sosId` se genera en el cliente. Si se pulsa dos veces o se reintenta, la Function devuelve el mismo evento sin notificar de nuevo.
- Antiabuso: como máximo un SOS activo por usuario; un límite de frecuencia en la Function (p. ej. 5 por hora) y registro en `audit`.

## Retención (decisión D9, aplicada)

| Dato | Retención | Mecanismo |
|---|---|---|
| Última ubicación | Hasta que el usuario pause, salga del grupo o borre su cuenta | Se borra en la misma operación |
| Historial de ubicación | **No se guarda** en el MVP | Si se activa en el futuro: consentimiento explícito y política TTL de Firestore |
| Eventos (check-in, geocercas, membresía) | 30 días | Política TTL de Firestore sobre `expireAt`. Las reglas rechazan un `expireAt` del cliente posterior a `request.time` + 31 días |
| SOS (alerta y su evento) | 90 días | TTL sobre `expireAt` (lo fija `raiseSos`) |
| Auditoría | 180 días | TTL sobre `expireAt` (lo fijan las Functions) |
| Invitaciones | 7 días tras vencer (vencen a las 48 h) | TTL sobre `expireAt` |
| Cuenta eliminada | Inmediato para lo identificable; el resto, según su TTL | `deleteAccount`: sale de todas las familias (borra membresía, ubicación y consentimiento), **borra ya** sus check-ins y eventos de zona, quita las coordenadas de sus alertas SOS (la alerta sin ubicación queda para la familia hasta su TTL), anonimiza la auditoría (`deleted-user`) y borra perfil, dispositivos y usuario de Auth |

Las políticas TTL y el índice compuesto de invitaciones están en `firestore/firestore.indexes.json` y se despliegan con `firebase deploy --only firestore:indexes`. Firestore borra los documentos vencidos normalmente dentro de las 24 h siguientes, no en el instante exacto.
