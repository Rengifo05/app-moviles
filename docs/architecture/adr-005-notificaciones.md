# ADR-005 · Notificaciones push (SOS)

- **Estado:** Aceptado (2026-10-15). La verificación real depende de D7 (proyecto Firebase real y clave APNs) y de un dispositivo 📱.
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
