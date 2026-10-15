# Modelo de amenazas (v0, propuesta)

- **Activos:** ubicación (sensible), membresía familiar, eventos SOS, identidad y sesión, tokens de invitación y tokens FCM.
- **Actores:** integrante legítimo, ex integrante, usuario de otra familia, atacante con credenciales robadas, persona con el dispositivo en la mano y familiar con intención de control.
- **Fronteras de confianza:** dispositivo ↔ Firebase (reglas y Functions). **El cliente Flutter no es frontera de seguridad.**

| # | Amenaza | Impacto | Mitigaciones | Verificación |
|---|---|---|---|---|
| 1 | **Acceso entre familias** (leer o escribir datos de otra familia cambiando el `familyId`) | Crítico | Las reglas exigen membresía activa en `families/{f}/members/{auth.uid}` para toda subcolección. Denegación por defecto (`match /{document=**} { allow read, write: if false; }`). Las Functions validan la membresía en el servidor y nunca confían en el `familyId` del cliente | Pruebas de reglas con dos familias y usuarios cruzados (T4.3) |
| 2 | **Cuenta comprometida** | Alto | Contraseñas robustas; verificación de correo; Auth revoca *refresh tokens* al cambiar la contraseña; "Cerrar sesión en todos los dispositivos" (Function que revoca tokens); aviso a la familia cuando cambia la pertenencia; App Check (Fase 2) | Prueba de la Function de revocación en el emulador |
| 3 | **Invitación robada** | Alto | Token aleatorio de 128 bits; solo se guarda su hash (SHA-256); expira en 48 h; un solo uso por defecto; revocable; aceptarla notifica a owner y admins, que pueden expulsar; el enlace no contiene datos personales | Pruebas de la Function: expirada, agotada, revocada, token inválido y reutilización |
| 4 | **Dispositivo perdido** | Alto | Sesión en almacenamiento seguro (Keychain / Keystore); bloqueo opcional con biometría para abrir la app (Fase 2); "cerrar sesión remota" desde otro dispositivo; la base de datos local se excluye de copias en la nube | Revisión de la configuración de `allowBackup` y exclusiones; prueba manual |
| 5 | **Revocación del consentimiento** | Alto | Pausar compartición borra `locations/{uid}` **en la misma operación**; la regla rechaza escrituras con consentimiento en pausa; el cliente detiene el servicio de ubicación; la UI lo refleja | Prueba de reglas: escritura con `paused` → denegada. Prueba unitaria del caso de uso |
| 6 | **Suplantación de eventos** (crear un check-in o SOS a nombre de otro) | Alto | `actorUid == request.auth.uid` en las reglas; el SOS solo se crea vía Function; los eventos son de solo inserción | Pruebas de reglas negativas |
| 6b | **Ubicación falsificada** (GPS *spoofing*) | Medio | No se puede impedir del todo. La UI dice "ubicación reportada por el dispositivo"; se registra `isMocked` si la plataforma lo expone; no se promete exactitud | Documentado como riesgo residual |
| 7 | **Exposición en logs** | Alto | `SafeLogger` con lista blanca de campos: nunca coordenadas, tokens, correos ni contenido de mensajes; las Functions registran solo IDs técnicos y códigos de error; sin analítica de ubicación | Prueba unitaria del redactor y revisión de código (`security-review`) |
| 8 | **Abuso del SOS** (spam o activación accidental) | Medio | Mantener pulsado más cuenta atrás cancelable; límite de frecuencia en la Function; un SOS activo por usuario; auditoría; los miembros pueden silenciar a alguien temporalmente (Fase 2) | Pruebas de widget del flujo y prueba de la Function |
| 9 | **Vigilancia no consentida / control coercitivo** | Crítico (ético) | Cada persona decide **su propia** compartición; nadie puede activarla por otro; no existe modo oculto; indicador persistente "Compartiendo con N personas"; recordatorio periódico configurable; notificación a todos cuando alguien se une; salir del grupo es siempre posible y no requiere aprobación; **MVP solo para adultos** | Revisión de UX en el Día 2 y pruebas de widget del consentimiento |
| 10 | **Acceso después de abandonar el grupo** | Alto | La Function `leaveFamily` o `removeMember` borra en una transacción la membresía, la ubicación y el consentimiento; las reglas niegan de inmediato; el cliente purga la caché de Drift de esa familia; los *listeners* activos reciben `permission-denied` y la UI lo maneja | Prueba de reglas: un ex miembro no lee. Prueba de integración del purgado |
| 11 | **Contenido sensible en notificaciones** | Medio | Las notificaciones no incluyen coordenadas; preferencia de "ocultar detalle en la pantalla de bloqueo"; la app consulta los detalles tras autenticarse | Revisión de los *payloads* en las pruebas de Functions |
| 12 | **Secretos en el repositorio** | Alto | `.gitignore` para archivos de entorno, `google-services.json` y `GoogleService-Info.plist` reales; `.env.example` solo con nombres; *secret scanning* en CI | Revisión en el Día 7 |

## Riesgos residuales aceptados (por confirmar)

- La exactitud de la ubicación depende del dispositivo y del sistema operativo.
- Un integrante legítimo puede ver la ubicación de quienes la comparten con él. Es el propósito de la app, pero se comunica con claridad.
- Sin cifrado de extremo a extremo: los datos están cifrados en tránsito (TLS) y en reposo por el proveedor, pero **el proveedor técnicamente puede acceder**. No se afirmará E2EE.

## Proceso de revocación (resumen)

1. El usuario pulsa "Pausar" → se borra su ubicación remota y se detiene la captura → la UI confirma solo **después** de que el servidor responde (o muestra "Pendiente: sin conexión").
2. El usuario sale del grupo → Function transaccional → purga local → auditoría.
3. Owner o admin expulsan a alguien → lo mismo, y se notifica a la persona expulsada.
4. Borrado de cuenta → Function `deleteAccount` (≤ 30 días para eliminar todo, incluidas las copias que gestione el proveedor según su política).
