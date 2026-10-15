# ADR-003 · Ubicación, segundo plano y geocercas

- **Estado:** Propuesto. La opción de pago queda pendiente de aprobación.
- **Fecha:** 2026-10-15

## Contexto y restricciones de plataforma (fuentes oficiales citadas en buscadores; reconfirmar)

- **Android:** las geocercas exigen `ACCESS_FINE_LOCATION` y `ACCESS_BACKGROUND_LOCATION` (API 29+). El límite es de **100 geocercas por app y usuario del dispositivo**. En segundo plano, los eventos pueden llegar **con minutos de retraso** (Android 8+). La ubicación continua en segundo plano requiere un *foreground service* de tipo `location` con notificación visible.
- **Google Play:** el acceso en segundo plano requiere un **formulario de declaración**, un **video** que muestre la función, una **divulgación destacada** dentro de la app y una política de privacidad. Solo se aprueba si la función es central para la app.
- **iOS:** el monitoreo de regiones admite como máximo **20 regiones por app**, y CLMonitor también tiene un límite de 20 según los foros de Apple. Requiere autorización "Siempre" para recibir eventos con la app cerrada. iOS muestra indicadores de uso de ubicación y le recuerda periódicamente al usuario que la app la usa.
- Ninguna de estas conductas se puede verificar en este contenedor (sin dispositivos). **No se promete funcionamiento continuo** hasta validarlo en dispositivos reales.

## Opciones evaluadas

| Opción | Pros | Contras |
|---|---|---|
| `geolocator` 14 (primer plano y *foreground service* en Android) | Flutter Favorite, MIT, mantenido | El segundo plano en iOS es limitado; hay que diseñar cuidadosamente la batería y la frecuencia |
| `native_geofence` 1.3.1 (geocercas del SO) | Eficiente en batería: el SO despierta la app; MIT; 160/160 | Paquete pequeño (45 likes); la ejecución con la app cerrada **debe validarse en dispositivo** |
| `flutter_background_geolocation` 5.9 | El más completo (detección de movimiento, geocercas, persistencia) | **Requiere licencia de pago para builds release en iOS y Android**: decisión de costo |
| Evaluar geocercas en el servidor | No depende de las APIs de geocercas del SO | Necesita actualizaciones de ubicación frecuentes: más batería, más escrituras y más costo |

## Decisión propuesta (por fases)

**Fase 1 del MVP (esta semana): sin ubicación continua en segundo plano.**

- La ubicación se comparte **en primer plano**: al abrir la app, al hacer check-in o SOS, y con un "Actualizar mi ubicación" explícito.
- La UI siempre muestra **"Ubicación actualizada hace X min"** o **"Sin actualización reciente"**, nunca "a salvo".
- Las geocercas y su UI (crear y editar) se implementan completas. Los eventos de entrada y salida se generan con `native_geofence` **detrás de una bandera de función desactivada por defecto** hasta validarlos en dispositivo.
- Permisos graduales: primero "Mientras se usa la app"; "Siempre" solo cuando el usuario active zonas seguras y tras una explicación propia.

**Fase 2 (tras validar en dispositivos y aprobar la declaración de Play):**

- Compartición en segundo plano con frecuencia adaptativa: se publica al moverse más de ~150 m o, como máximo, cada 15 min en movimiento, y nunca mientras está quieto. En Android usa un *foreground service* con notificación persistente; en iOS, cambios significativos de ubicación y regiones.
- Si las pruebas en dispositivo muestran que las opciones gratuitas no son fiables, se presentará la licencia de `flutter_background_geolocation` como **propuesta de costo** para aprobar.

## Reglas transversales

- Cada actualización incluye `capturedAt` (reloj del dispositivo) y `receivedAt` (servidor). Se descartan las que llegan **fuera de orden** (`capturedAt` menor o igual al almacenado), en la regla de Firestore y en el cliente.
- Los eventos de geocerca llevan un `clientEventId` (UUID v7) como ID del documento: un reenvío no duplica el evento.
- Se aplica antirrebote en el cliente: no se emiten dos eventos de la misma zona y tipo en menos de 3 min.
- No se registran coordenadas en logs ni en analítica (ver el modelo de amenazas).
- Tope de zonas por familia en el MVP: **10**, por debajo del límite de 20 regiones de iOS para dejar margen.
