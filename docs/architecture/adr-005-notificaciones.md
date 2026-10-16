# ADR-005 · Notificaciones push (SOS)

- **Estado:** Aceptado (2026-10-15). Cliente implementado y probado en el host (2026-10-16). La verificación real depende de D7 (proyecto Firebase real y clave APNs) y de un dispositivo 📱.
- **Fecha:** 2026-10-15

## Contexto

El SOS debe avisar a los demás integrantes aunque no tengan la app abierta. El servidor ya hace su parte: `raiseSos` envía por FCM un texto **genérico y sin ubicación**, cuenta solo los mensajes aceptados (`notifiedCount`) y olvida los tokens inválidos (`05-api-backend.md`). Falta el cliente: pedir el permiso, registrar el dispositivo y abrir la alerta al tocar el aviso.

## Decisión

1. **FCM con `firebase_messaging`**, la misma familia de paquetes que el resto de Firebase. No se usan notificaciones locales en el MVP: el aviso lo pinta el sistema con el texto del servidor.
2. **Contenido:** título «Alerta SOS» y cuerpo «Un integrante de tu familia pidió ayuda. Abre Nexo Familia.». Los datos solo llevan `type`, `familyId` y `alertId`. Nunca nombres, mensajes ni coordenadas: el texto se ve en la pantalla de bloqueo. La preferencia «Ocultar detalles en la pantalla de bloqueo» ya se cumple por diseño.
3. **Permiso en contexto:** no se pide al abrir la app. Se pide la primera vez que la persona tiene una familia activa, con una explicación propia («Para enterarte si alguien de tu familia pide ayuda…») antes del diálogo del sistema. Esto aplica a iOS y a Android 13 o superior (`POST_NOTIFICATIONS`). Si se deniega, Inicio y Ajustes muestran «Las alertas SOS no te llegarán con la app cerrada», con «Abrir ajustes». Nunca se afirma que alguien será avisado.
4. **Registro del dispositivo:** `users/{uid}/devices/{installId}` con `{ token, platform, updatedAt }`. Las reglas ya lo permiten solo al dueño. `installId` es un UUID guardado en las preferencias locales.
   - El token se actualiza al iniciar sesión y cuando FCM lo renueva.
   - Al cerrar sesión se borra el documento **antes** de cerrar la sesión: un teléfono que ya no es tuyo no debe recibir alertas de tu familia.
   - «Cerrar sesión en todos los dispositivos» (`signOutEverywhere`) borra todos.
5. **Al tocar el aviso:** se abre la pantalla SOS de esa alerta (`familyId` y `alertId`). Si la persona ya no es integrante, se muestra un error honesto, sin datos.
6. **Abstracción:** `PushService` en la capa de dominio (permiso, token y aperturas), con una implementación FCM en `infrastructure/` y otra de demostración que nunca dice que haya avisos activos. Así las pantallas se prueban en el host.

## Consecuencias

- Sin D7 no hay avisos reales. El modo demo y los emuladores muestran el estado «avisos no configurados» y no fingen entregas.
- En iOS hace falta la *capability* Push Notifications, un `GoogleService-Info.plist` o las opciones por `--dart-define`, y la clave APNs en Firebase. Son pasos 📱 que irán al runbook.
- Un aviso aceptado por FCM no garantiza que alguien lo vea. Por eso la app muestra «Aviso enviado a N dispositivos» y solo cuenta como confirmación el *ack* explícito («Lo vi»).

## Implementación (2026-10-16)

Qué hay en el código y en qué se aparta de la decisión:

- **Piezas:**
  - dominio: `PushService`, `DeviceRegistry` y `PushRegistration` (`lib/features/notifications/domain/`);
  - datos: `DeviceRegistryImpl` sobre el almacén remoto;
  - infraestructura: `FirebasePushService` (FCM) y `sosOpenOf`, que valida los datos del aviso;
  - presentación: `PushPromptCard` en Inicio y `pushBindingProvider`, que une los avisos con la sesión.
- **Cuándo hay servicio:** solo con Firebase real en Android o iOS. En el modo demostración y con los emuladores (FCM no tiene emulador) la app no pide permiso ni registra nada, y Ajustes dice que los avisos no están configurados.
- **Id del registro (cambio respecto al punto 4):** en lugar de un `installId` guardado en el teléfono, el id es un hash SHA-256 truncado del token. Registrar dos veces es inocuo, el documento no revela el token en su ruta y el teléfono puede borrar exactamente su registro sin guardar nada más. Cuando FCM renueva el token, se registra el nuevo y se borra el anterior; si eso falla, el anterior lo limpia el servidor cuando FCM lo declare inválido.
- **Cierre de sesión:** el registro se borra antes de cerrar la sesión, con un límite de 5 s. Sin red, la sesión se cierra igual; el servidor olvida el token cuando FCM lo rechace, o con «Cerrar sesión en todos los dispositivos». Si la sesión termina desde otro teléfono, la siguiente vuelve a registrar.
- **Al tocar el aviso (cambio respecto al punto 5):** se activa esa familia y se abre Inicio, donde la alerta activa ya se ve con «Lo vi». Si la familia no es de la cuenta, la sesión la ignora y sigue con la activa: no se muestra ningún dato.
- **Permiso denegado:** Inicio lo dice y remite a los ajustes del teléfono. Todavía no hay botón «Abrir ajustes».
- **Canal de Android:** el aviso usa el canal por defecto de FCM. Un canal propio de alta importancia para el SOS necesita notificaciones locales o código nativo; queda pendiente.
