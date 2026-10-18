# 06 · Informe de calidad

> Estado al 2026-10-16 (commit `280aa01` y posteriores). Las cifras salen de ejecuciones reales (`tool/check.sh`, `tool/check_backend.sh`, `npm run test:mutations`) en la sesión de desarrollo y en la CI de GitHub Actions. **Nada de esta app está listo para producción** (ver §4).

## 1. Qué está probado de forma automática

| Área | Cómo | Resultado |
|---|---|---|
| Formato y análisis estático | `dart format` y `flutter analyze --fatal-infos` con very_good_analysis 11 en modo estricto | 0 avisos |
| Límites entre capas | Prueba de arquitectura de mundo cerrado sobre el AST | En verde |
| App Flutter (unitarias, integración y widgets) | `flutter test`: 90 archivos de prueba | **1239** en verde |
| Capturas *golden* | 97 imágenes, claro al 100 % y oscuro al 200 %, revisadas una por una | En verde |
| De extremo a extremo en el host | App completa con el backend de demostración y Drift en memoria: 6 escenarios | En verde |
| Reglas de Firestore | Emulador con `@firebase/rules-unit-testing` | En verde |
| Calidad de las pruebas de reglas | Pruebas de mutación: 41 condiciones debilitadas una a una | **41/41** detectadas |
| Cloud Functions | Emulador de Firestore, proyecto `demo-nexo`, sin credenciales | **99** en verde (incluye las reglas) |
| Índices y TTL | Validador de `firebase-tools` (`npm run check:indexes`) | Válidos |
| Dependencias del backend | `npm audit --omit=dev` | 0 vulnerabilidades |
| Licencias de la app | Archivo `LICENSE` de los 163 paquetes de `package_config.json` | BSD, MIT y Apache-2.0. Sin GPL. `dbus`, `geoclue` y `gsettings` son MPL-2.0 y solo los usa `geolocator` en Linux de escritorio, que no es un objetivo de la app |
| Licencias del backend | `license-checker --production` | MIT, Apache-2.0, ISC, BSD, BlueOak-1.0.0 y 0BSD (todas permisivas) |

Los 6 escenarios de extremo a extremo:
1. Primer uso: bienvenida, registro con mayoría de edad y privacidad, y configuración de la familia.
2. Credenciales incorrectas con un error genérico.
3. Crear una familia, invitar y unirse desde otra cuenta.
4. Un código de invitación inexistente no confirma nada.
5. Un check-in sin conexión queda guardado y se envía una sola vez al volver la red.
6. Un SOS se activa manteniendo presionado, tiene cuenta atrás, informa con honestidad (en el modo demo, sin push, «Nadie pudo ser notificado») y solo cuenta como confirmado con el «Lo vi» de otra persona.

Garantías que cubren las pruebas, en resumen:
- **Honestidad:**
  - Ningún texto dice «a salvo», «seguro», «recibido» ni «ayuda en camino». Varias pruebas lo buscan con expresiones regulares.
  - «Enviado» o «confirmado» solo aparece con respuesta del servidor o con el *ack* de otra persona.
  - «Sin conexión» se muestra a partir de datos reales, con 3 s de gracia.
- **Privacidad:**
  - Pausar borra la ubicación en la misma operación.
  - Pasar a «aproximada» borra la exacta. La ubicación se ajusta al consentimiento vigente en el cliente, en las reglas y en `raiseSos`.
  - Al cerrar sesión, o al dejar de ser integrante, se purgan la copia local y la bandeja.
  - Los registros no contienen coordenadas, tokens ni mensajes, porque el esquema es cerrado por campo.
  - Al eliminar la cuenta se borra lo identificable en todas las familias.
- **Resiliencia:**
  - La bandeja de salida tiene prioridad para el SOS e idempotencia (`RemoteWrite.create`, `alertId`).
  - Las escrituras fallan sin conexión en lugar de quedar en espera.
  - El espejo reconecta, y un ámbito solo está «en vivo» con todas sus colecciones.
- **Accesibilidad:**
  - Contraste WCAG en 61 pares de colores.
  - Guías de Flutter de tamaño táctil y etiquetas.
  - Texto al 200 % sin desbordes en los *goldens*.

Las revisiones adversariales y los defectos que encontraron están en [revisiones.md](revisiones.md).

## 2. Qué solo se puede verificar a mano (📱)

| Qué | Por qué no se automatizó | Cómo verificarlo |
|---|---|---|
| Compilar y ejecutar en Android e iOS | En la sesión en la nube no hay SDK de Android ni Xcode | `flutter run` en un dispositivo; runbook de entorno |
| Permiso de ubicación del sistema (geolocator) | Necesita el sistema operativo real | Conceder, denegar y denegar dos veces; comprobar la explicación previa |
| Lector de pantalla (TalkBack y VoiceOver) | Las guías de Flutter no sustituyen una prueba real | Recorrer Inicio, SOS y Privacidad con el lector |
| Llamar al 123 | Abre el marcador del sistema | Pulsar «Llamar al 123» en un teléfono |
| Notificaciones push del SOS | Requieren un proyecto real, la clave APNs (D7) y un teléfono. El cliente está probado en el host con dobles | Runbook de entorno, pasos 4 y 5 de iOS y Android |
| Firebase real (Auth, Firestore, Functions) | Requiere el proyecto real, pendiente de D7 | Desplegar en *staging* según el runbook |

## 3. Pendientes conocidos

- **D7 (credenciales y pagos):**
  - proyecto Firebase de *staging* con Blaze, presupuesto y *spend cap*;
  - API key de Google Maps (hoy el mapa es la lista accesible);
  - clave APNs y App Check.
- **Notificaciones push:** el cliente está implementado (permiso en contexto, registro del dispositivo, renovación del token, baja al cerrar sesión y apertura de la alerta), pero nunca se ha recibido un aviso real (D7). Falta un canal de Android propio para el SOS.
- **Geocercas nativas:** desactivadas por diseño (ADR-003). El editor de zonas funciona, pero no hay monitoreo de entradas y salidas.
- **Banderas remotas para apagar funciones sin publicar** una versión.
- **Límite de 10 zonas por familia:** solo se aplica en el cliente, porque las reglas no pueden contar documentos.
- **FlutterFire:** hay versiones mayores nuevas (`cloud_firestore` 7, `firebase_core` 5). Actualizar es una decisión aparte, con su revisión de cambios incompatibles.
- **Reloj del teléfono adelantado más de 1 día:** las reglas rechazan los check-ins (retención con `expireAt`). Se ve como fallido; no se finge el envío.

## 4. Por qué no está listo para producción

1. Nunca se ha ejecutado contra un proyecto Firebase real ni en un teléfono.
2. Las notificaciones push nunca se han probado de verdad: sin proyecto real ni clave APNs, un SOS solo llega a quien tiene la app abierta. La interfaz lo dice («Nadie pudo ser notificado»), pero es la limitación principal de un producto de seguridad.
3. Falta una revisión legal: privacidad, tratamiento de datos de ubicación según la Ley 1581 de 2012 y términos de uso.
4. No hay pruebas con usuarios reales de la experiencia del SOS ni de los textos.
