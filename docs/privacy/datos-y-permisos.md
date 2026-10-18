# Datos, permisos y marco legal (borrador)

> **No es asesoría legal.** Resume obligaciones aparentes para orientar el diseño. Antes de publicar hace falta una revisión con un profesional en Colombia y en cada país de publicación.

## Inventario de datos (MVP)

| Dato | Para qué | ¿Se puede evitar? | Retención |
|---|---|---|---|
| Correo y contraseña (Auth) | Identidad | No | Mientras exista la cuenta |
| Nombre visible | Que la familia te reconozca | Puede ser un apodo | Mientras exista la cuenta |
| Última ubicación (lat, lng, precisión, hora) | Mapa familiar | El usuario puede no compartirla o pausarla | Se sobrescribe; se borra al pausar o salir |
| Eventos de geocercas y check-ins | Historial familiar | Las geocercas son opcionales | 30 días |
| Eventos SOS | Emergencias | No, si se usa el SOS | 90 días |
| Token FCM | Enviar avisos | Sin él no hay push (se indica) | Hasta cerrar sesión o rotar el token |
| Auditoría de pertenencia | Seguridad | No | 180 días |

**No se recopilan** en el MVP: contactos del teléfono, historial de ubicación, teléfono, fecha de nacimiento, analítica de comportamiento ni identificadores publicitarios.

## Permisos por plataforma y momento de solicitud

| Permiso | Plataforma | Cuándo se pide | Si se deniega |
|---|---|---|---|
| Ubicación "mientras se usa" | iOS `NSLocationWhenInUseUsageDescription`; Android `ACCESS_FINE_LOCATION` y `ACCESS_COARSE_LOCATION` | Al activar "Compartir mi ubicación" por primera vez, **después** de una pantalla explicativa propia | La app funciona (ver a otros, check-in sin ubicación, SOS sin ubicación) y muestra "No compartes tu ubicación" con un botón a Ajustes |
| Ubicación "siempre" | iOS `NSLocationAlwaysAndWhenInUseUsageDescription`; Android `ACCESS_BACKGROUND_LOCATION` | Solo al activar zonas seguras (Fase 2 o con bandera activada), con divulgación destacada | Las zonas se ven en el mapa, pero sin avisos automáticos; se indica claramente |
| Notificaciones | iOS (autorización de notificaciones); Android 13+ `POST_NOTIFICATIONS` | Al terminar de unirse o crear una familia, explicando que sirven para SOS y avisos | Banner persistente: "No recibirás alertas SOS" |
| *Foreground service* de ubicación | Android `FOREGROUND_SERVICE_LOCATION` | Solo en la Fase 2 | No aplica |

Divulgación destacada (requisito de Google Play para el segundo plano): debe aparecer en el flujo principal y mencionar que la ubicación se usa "incluso cuando la app está cerrada o no se usa" (fuente secundaria; reconfirmar con la política vigente).

## Colombia: puntos a revisar con asesoría legal

- **Ley 1581 de 2012 (Habeas Data):** autorización previa, expresa e informada; finalidad; derechos de conocer, actualizar, rectificar y suprimir; política de tratamiento publicada.
  - Cómo se ejercen en la app: **conocer**, con Cuenta → «Descargar mis datos» (archivo JSON con lo de la persona en todas sus familias, sin datos de otras personas); **actualizar y rectificar**, editando el perfil y las decisiones de ubicación; **suprimir**, con «Eliminar mi cuenta». La revisión legal sigue pendiente.
- **Menores:** el art. 7 de la Ley 1581 restringe el tratamiento de datos de niños, niñas y adolescentes. El reglamento (Decreto 1377 de 2013, compilado en el Decreto 1074 de 2015) lo permite si responde al interés superior del menor y respeta sus derechos fundamentales, con autorización del representante legal y la opinión del menor valorada según su madurez. **Por eso se propone un MVP solo para adultos.**
- **Registro Nacional de Bases de Datos (SIC):** verificar si aplica según el tipo y tamaño del responsable.
- **Transferencia internacional:** los datos se alojarían fuera de Colombia (p. ej. São Paulo o EE. UU.). Revisar los requisitos de la SIC.

## Tiendas

- **Google Play:** declaración de ubicación en segundo plano (formulario y video), sección *Data safety* y, si la app se dirige a menores, política *Families*.
- **App Store:** etiquetas de privacidad, manifiesto de privacidad (incluidos los SDK de terceros, como Google Maps y Firebase), justificación del permiso "Siempre" y la guía 4.8 si se ofrece inicio de sesión de terceros.
