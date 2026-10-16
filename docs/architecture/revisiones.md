# Registro de revisiones

Cada incremento pasa por una revisión adversarial antes de darse por terminado:

1. Revisores independientes, cada uno con un enfoque distinto, buscan defectos reales con un escenario de fallo reproducible.
2. Un verificador escéptico intenta refutar cada hallazgo.
3. Solo se corrigen los hallazgos que sobreviven. Los descartados se anotan aquí con su motivo.

## Incremento 1 · Base del proyecto (2026-10-15)

Enfoques: privacidad y seguridad, solidez de la prueba de arquitectura, corrección y compilación. 6 agentes en total.

| Hallazgo | Veredicto | Resolución |
|---|---|---|
| `SafeLogger` dejaba pasar tokens de 128 bits (hex, base64url, UUID v4) y OTP en campos permitidos | Confirmado (medio) | Se reemplazaron las heurísticas por un **esquema cerrado por campo**: listas de valores, vocabularios sin dígitos, enteros acotados y UUID v7 solo en `opId` |
| El nombre del evento admitía dígitos y longitud ilimitada | Confirmado (bajo) | Sin dígitos y ≤ 64 caracteres |
| `SafeLogger` lanzaba excepciones con `double.infinity` | Confirmado (medio) | Se redactan los valores no finitos y el registro nunca lanza (`try/catch`) |
| Enteros (microgrados, teléfonos) en campos numéricos | Descartado (uso deliberado), pero corregido igualmente | Los enteros se acotan por campo (`attempt` ≤ 1000, etc.) |
| La prueba de arquitectura ignoraba las importaciones condicionales | Confirmado (medio) | Las directivas se leen con el AST de `package:analyzer`, incluidas las configuraciones |
| Los archivos fuera de las capas conocidas servían de puente o barril | Confirmado (medio) | **Mundo cerrado**: toda ubicación no reconocida es una violación |
| El dominio podía importar `core/platform`, `l10n` o `flutter_*` | Confirmado (medio/bajo) | Listas de permitidos por capa; desaparece `core/platform` y se crea `infrastructure/` |
| ADR-002 ubicaba el adaptador de Google Maps en `presentation` | Confirmado (bajo) | Contrato en `design_system`, adaptador en `infrastructure/maps` |
| Falsos positivos con importaciones dentro de comentarios | Confirmado (bajo) | Resuelto con el AST |
| La prueba de arquitectura no funcionaba en Windows | Confirmado (bajo) | Rutas normalizadas a POSIX con `package:path` |
| La igualdad de `Ok`/`Err` era asimétrica según el tipo genérico | Confirmado (bajo) | La igualdad ya no depende del argumento de tipo |
| `install_flutter.sh` podía borrar cualquier destino | Confirmado (bajo) | Solo rutas absolutas; nunca `/` ni `$HOME`; solo reemplaza un SDK o un directorio vacío, y lo comprueba antes de descargar |
| `.gitignore` no cubría cuentas de servicio ni configuraciones por flavor | Descartado (sin backend todavía), pero corregido igualmente | Patrones sin anclar y credenciales del backend |
| Una compilación release sin `--dart-define` arrancaba con datos de demostración | Descartado (bajo), pero corregido igualmente | `AppConfig.validate` lo rechaza salvo con `NX_ALLOW_DEMO_RELEASE=true` |
| Comentarios entre `import` y la URI, comillas triples, `.g.dart` escritos a mano, URIs con `%xx` | Descartados: requieren ofuscación deliberada, o ya los detecta `flutter analyze` | El AST también cubre los dos primeros |

## Columna vertebral: dominio, infraestructura y backend (2026-10-15)

Seis agentes trabajaron sobre archivos disjuntos: uno escribía las pruebas de cada área (dominio, backend de demostración, sincronización y Drift) y otro la revisaba de forma adversarial. Cada defecto se demostró primero con una prueba que fallaba.

| Área | Defectos corregidos (resumen) |
|---|---|
| Dominio | Frescura con reloj adelantado (usa `min(capturedAt, receivedAt)`); el SOS ya no cuenta como «confirmado» el *ack* de la propia autora; `copyWith` arrastraba el código de error; normalización Unicode del código de invitación; **fuga de privacidad** en `approximate()` (signo de `-0.0`, antimeridiano y polos); expresión regular de correo cuadrática que congelaba la interfaz |
| Backend de demostración | Copias superficiales; `merge` superficial; rutas inválidas e inyección de rutas; orden de consultas; estados intermedios visibles (ahora transaccional); códigos de error en kebab-case; heredero no determinista; `deleteAccount` incompleto; colisión de códigos; escuchas que seguían vivas tras un error (Firestore las termina) |
| Sincronización y Drift | Prioridad del SOS durante un envío en curso; recuperación tras fallos del almacén; entradas atascadas en `sending`; **purga que no esperaba escrituras en curso** (fuga de datos de una familia tras salir); reconexión del espejo; `secure_delete` en SQLite; fechas en segundos y hora local; desbordes del *backoff* |
| Coordinador (corregido por el integrador) | Un paso fallido detenía la cadena (incluida la purga al cerrar sesión); purga de la bandeja de salida al cerrar sesión; purga de la familia anterior tras detener su espejo |

### Pruebas de mutación de las reglas de Firestore

`npm run test:mutations` (en `functions/`) debilita una a una 37 condiciones de seguridad. La primera ejecución detectó 35 de 37. Las 2 supervivientes revelaron **pruebas que pasaban por el motivo equivocado**; las reglas estaban bien:

- La escritura de la ubicación de otra persona fallaba por el consentimiento de quien escribía, no por la comprobación de propiedad.
- Faltaba el caso de un *ack* propio combinado con el de otra persona en la misma escritura.

Tras añadir esos casos se detectan **37 de 37**. Este paso forma parte de la CI.

## Incremento 4 · Adaptador de Firebase y retención (2026-10-15)

Revisión del integrador al conectar Firebase. Defectos encontrados y corregidos:

| Hallazgo | Resolución |
|---|---|
| La consulta de invitaciones activas (`familyId` + `status` + rango en `expiresAt`) necesita un índice compuesto. El emulador no lo exige, así que las pruebas pasaban y producción habría fallado con `FAILED_PRECONDITION` | Índice en `firestore.indexes.json`, validado con el validador de `firebase-tools` |
| Las alertas SOS, la auditoría y las invitaciones no tenían `expireAt`: la retención de 90/180/7 días (D9) no se podía aplicar | Las Functions fijan `expireAt`; políticas TTL declaradas en `firestore.indexes.json`; pruebas en el emulador |
| Un cliente podía fijar un `expireAt` lejano y conservar sus eventos indefinidamente | Regla: `expireAt <= request.time + 31 días`, con prueba y una mutación nueva (**38 de 38** detectadas) |
| `deleteAccount` dejaba en las familias los mensajes y lugares de los check-ins, las coordenadas de las alertas y el `uid` en la auditoría (contra lo prometido en la tabla de retención) | Limpieza por familia tras salir; prueba que recorre toda la base buscando restos |
| `batch.commit()` de Firestore no falla sin conexión: queda en la cola interna y las escuchas lo muestran como aplicado. Un check-in en la bandeja habría bloqueado el SOS de detrás, y la interfaz podría confirmar lo que el servidor aún no aceptó | El adaptador escribe con **transacciones** (fallan sin conexión) y un tiempo límite de 15 s |
| El ADR prometía que «un `set` repetido es inocuo», pero las reglas de eventos solo permiten crear: el reintento de un check-in que sí llegó acababa en `permission-denied` (fallo permanente) | `RemoteWrite.create`: si el documento ya existe, el reintento se da por entregado. Las ubicaciones admiten reenviar la misma captura (`capturedAt >=`) |
| Con la caché de Firestore, una escucha sin red entrega datos locales sin error: la app nunca habría mostrado «Sin conexión» | Las instantáneas `isFromCache` se convierten en una señal no terminal; el espejo pasa a `offline` y la interfaz lo muestra tras 3 s de gracia (sin parpadeo al arrancar) |

## Revisión adversarial de la integración (2026-10-15)

Dos revisores (sincronización y adaptador de Firebase; seguridad y privacidad del backend) y un escéptico por hallazgo: 6 confirmados (dos con la misma causa), 1 refutado y 1 que el escéptico no llegó a verificar por el límite de uso (lo comprobó el integrador leyendo FlutterFire).

| Hallazgo | Resolución |
|---|---|
| `deleteAccount` solo limpiaba las familias de las membresías **actuales**: si la persona había salido antes, o el borrado fallaba a mitad y se reintentaba, quedaban sus mensajes, lugares y coordenadas | La limpieza busca en **todas** las familias con consultas de grupo de colecciones (índices `COLLECTION_GROUP` declarados y validados). Es idempotente y tolera una expulsión concurrente (`not-member`) |
| El `uid` de la cuenta borrada quedaba sin TTL en `createdBy` de familias y zonas, y sus invitaciones seguían existiendo | Se anonimiza `createdBy` (la zona sube de versión) y se borran sus invitaciones |
| La limpieza de tokens FCM inválidos podía borrar un dispositivo que acababa de renovar su token | Se borra con la precondición `lastUpdateTime` |
| El registro con Firebase podía dejar la cuenta sin perfil y con la sesión abierta (fallo de red, falla de `updateDisplayName`, app cerrada a mitad), sin forma de repararla | Perfil primero, todo lo demás sin bloquear. Repetir el registro con el mismo correo y contraseña lo completa, y al iniciar sesión sin perfil se pide completarlo |
| La caché en disco de Firestore conservaba datos de la familia tras cerrar sesión, salir o borrar la cuenta | Caché solo en memoria (ADR-004 §7) |
| El tiempo límite de las transacciones no acotaba la confirmación nativa | Se acota también en Dart |
| Refutado como defecto de este cambio: `signOutEverywhere` no corta lo que dura más que el ID token (≤ 1 h) | Mejora de todos modos: revoca las invitaciones activas que creó la cuenta |
| Encontrado al integrar (la suite completa lo reproducía): el ámbito del espejo pasaba a «en vivo» en cuanto **una** de sus colecciones reconectaba, aunque las demás siguieran mostrando datos guardados | Un ámbito solo está `live` cuando todas sus colecciones recibieron datos del servidor tras arrancar o tras su último error; prueba determinista que falla sin la corrección |

## Revisión adversarial de las funcionalidades (2026-10-16)

Cuatro enfoques: honestidad, privacidad, datos e integración. El límite de uso cortó la verificación escéptica y dos de los revisores, así que el integrador verificó cada hallazgo contra el código y escribió primero una prueba que lo reproduce.

| Hallazgo | Resolución |
|---|---|
| Un SOS o check-in en la bandeja salía con las coordenadas capturadas antes de pausar o de pasar a «aproximada» | Los *handlers* aplican el consentimiento vigente de la copia local al enviar. `raiseSos` lo vuelve a leer en el servidor. Las reglas exigen la rejilla de 0,01° para check-ins y ubicaciones cuando la precisión es aproximada (3 mutaciones nuevas: **41/41**) |
| Un envío de ubicación exacta en curso se publicaba después de pasar a «aproximada» | `publishMyLocation` aplica el consentimiento vigente (aproximada → redondea; en pausa → no publica) y las reglas lo garantizan |
| Pasar a «aproximada» solo borraba la ubicación exacta si la copia local la tenía | Se borra siempre en el mismo lote |
| Al cambiar de familia sin conexión, la copia vacía de la otra familia se mostraba como cierta («Aún no compartes tu ubicación», sin integrantes, sin SOS activos) | Cambiar de familia ya no purga la anterior: solo detiene su escucha y se ven los últimos datos guardados |
| Al salir de una familia (o si te quitan) su bandeja de salida (check-ins y SOS con ubicación) quedaba en el teléfono indefinidamente | El coordinador purga copia local y bandeja de las familias que ya no están entre las membresías, solo cuando el servidor las confirmó en esta ejecución |
| La hora del aviso SOS de otro integrante se congelaba («hace un momento» 40 min después) y con el reloj atrasado siempre decía «hace un momento» | Se recalcula cada 30 s; si la hora del servidor queda en el futuro se muestra la hora absoluta |
| La ficha del integrante decía a la vez «Sin actualización reciente» y «hace un momento» con el reloj atrasado | Misma regla que Inicio y Mapa: una hora no fiable no se muestra |
| Cancelar el envío de un SOS cuyo intento fue ambiguo ocultaba para siempre la alerta si el servidor sí la había registrado | Solo se cierran las confirmadas; si aparece registrada, vuelve como activa para terminarla, y el aviso lo advierte |

Quedan sin revisar los enfoques de datos e integración (el límite de uso cortó a esos revisores): se cubren en la revisión de endurecimiento.

