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
