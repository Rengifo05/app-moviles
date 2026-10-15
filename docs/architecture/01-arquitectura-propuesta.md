# 01 · Arquitectura propuesta

- **Estado:** Aprobada (2026-10-15). Las secciones reflejan lo implementado; cada desviación se anota aquí.
- **Versiones objetivo:** Flutter 3.47.7 y Dart 3.13.5 (ver `00-descubrimiento.md`)

## Principios aplicados

- Arquitectura **por funcionalidad** con capas `presentation` / `domain` / `data`.
- **El dominio es Dart puro:** no importa Flutter, Firebase, Drift ni widgets. Lo verifica una prueba automática.
- **Los widgets nunca acceden a Firebase ni a SQLite.** Solo hablan con controladores de Riverpod, que usan casos de uso y repositorios.
- Los casos de uso existen solo cuando hay reglas significativas (SOS, invitaciones, consentimiento, geocercas). Los CRUD triviales llaman al repositorio directamente desde el controlador: no habrá abstracciones ceremoniales.
- Errores tipados: `sealed class Failure` y `Result<T>` con *pattern matching* de Dart 3. No se usan excepciones para el flujo normal.
- El reloj (`Clock`) y los identificadores (`IdGenerator`, UUID v7) son inyectables, para tener pruebas deterministas e idempotencia.

## Capas y dependencias

```text
presentation ──▶ domain ◀── data
      │             ▲          │
      └── design_system        └── Firebase / Drift / plugins (solo aquí)
app/ (bootstrap, router, DI) conoce a todas para cablearlas.
```

| Capa | Contiene | Puede importar |
|---|---|---|
| `domain` | Entidades, objetos de valor (`GeoPoint`, `Radius`, `FamilyId`…), contratos de repositorio, casos de uso y `Failure` | `core` (tipos puros) y `meta` |
| `data` | DTO, tablas de Drift, mapeadores, repositorios concretos y fuentes remotas y locales | `domain`, `core`, SDKs |
| `presentation` | Pantallas, widgets, controladores de Riverpod y estado de UI | `domain`, `core`, `design_system` |
| `design_system` | Tokens, `ThemeData`, componentes (`NxButton`, `NxStatusPill`, `NxSosButton`…) | Flutter |
| `core` | `Result`, `Failure` base, `Clock`, `IdGenerator`, logger seguro y utilidades de permisos | Dart, y Flutter solo en `core/platform` |

## Estructura de carpetas propuesta

Se crea **solo lo que tenga contenido real** en cada día del plan; no habrá carpetas vacías.

```text
lib/
  main.dart                    # arranque mínimo; delega en app/bootstrap.dart
  app/
    bootstrap.dart             # inicializa Firebase (o emuladores), Drift y el logger
    app.dart                   # MaterialApp.router + tema + localización
    router.dart                # GoRouter: shell con barra inferior + rutas modales (SOS)
  core/
    result.dart  failure.dart  clock.dart  id_generator.dart
    config/app_config.dart     # nombre de la app, entorno, backend y validación
    di/core_providers.dart     # providers transversales (config, reloj, IDs, logger)
    logging/safe_logger.dart   # redacta coordenadas, tokens y correos
    platform/permissions.dart  # envoltorio de permission_handler
  design_system/
    tokens/{colors,typography,spacing,radii,motion}.dart
    theme/nx_theme.dart
    components/…
  features/
    onboarding/{domain,presentation}/
    authentication/{data,domain,presentation}/
    family/{data,domain,presentation}/          # grupos, miembros, invitaciones
    location_sharing/{data,domain,presentation}/  # consentimiento, ubicación, mapa
    geofences/{data,domain,presentation}/
    check_ins/{data,domain,presentation}/
    emergency/{data,domain,presentation}/       # SOS
    activity/{data,domain,presentation}/        # historial
    settings/{data,domain,presentation}/        # privacidad, permisos, borrado
  l10n/                        # ARB es-CO (principal) y en
test/                          # espejo de lib/; incluye test/architecture/
integration_test/
functions/                     # Cloud Functions (TypeScript) + pruebas
firestore/                     # firestore.rules, índices y pruebas de reglas
docs/{architecture,decisions,privacy,runbooks}/
```

El onboarding no tiene capa `data` propia: solo persiste un indicador local que pertenece a `settings`.

## Inyección de dependencias (Riverpod)

- Cada funcionalidad declara en `presentation/` los *providers* de sus contratos de dominio (repositorios, casos de uso). Por defecto lanzan `UnimplementedError`.
- `app/bootstrap.dart` es la **raíz de composición**: el único lugar que importa la capa `data` y sobrescribe esos *providers* con las implementaciones de Firebase o de demostración (`BackendMode`).
- Las pruebas sobrescriben los mismos *providers* con dobles. Así `presentation` depende solo del dominio, y la prueba `test/architecture/layer_boundaries_test.dart` lo hace cumplir.
- `core/` puede usar `package:riverpod` (Dart puro), pero no Flutter, salvo `core/platform/`.

## Convenciones de código

- Dart 3.13 con `very_good_analysis` 11 y modos estrictos. Los constructores usan la sintaxis nueva `new(...)` / `const new(...)` que exige el lint `unnecessary_type_name_in_constructor`. `dart fix --apply .` la aplica automáticamente.
- `tool/check.sh` ejecuta las mismas puertas que CI: formato, `flutter analyze --fatal-infos` y pruebas.
- Los textos de UI se escriben en `lib/l10n/arb/*.arb`. `flutter pub get` genera `lib/l10n/gen/`, que no se versiona.

## Estado, navegación y entorno

- **Riverpod 3 sin generación de código** al inicio. Solo Drift usa `build_runner`, y así la cadena de herramientas es más simple. Se reevaluará `riverpod_generator` si el código manual crece.
- **GoRouter** con `StatefulShellRoute`: Inicio, Mapa, Actividad, Familia y Ajustes. El SOS es una ruta modal a pantalla completa, accesible desde Inicio y Mapa.
- Las redirecciones por estado (sin sesión → login; sin familia → crear o unirse; onboarding pendiente) se hacen en un único `redirect` probado.
- **Entornos:** `dev` (emuladores, proyecto `demo-nexo`, sin credenciales), `staging` y `prod`, configurados con `--dart-define-from-file`. Los archivos con valores reales están en `.gitignore`; solo se versiona `config/env.example.json`.
- **Localización:** español de Colombia como idioma principal; ningún texto de UI va escrito en el código.

## Dirección visual (borrador para el incremento 2)

Minimalismo funcional y cálido. Tipografía del sistema (SF Pro en iOS, Roboto en Android) para máxima legibilidad y escalado. Los estados se comunican con **texto, ícono y color**, nunca solo con color.

Contraste calculado con la fórmula WCAG 2.x (fondo marfil `#FAF7F0`):

| Token | Uso | Color | Contraste | Mínimo AA |
|---|---|---|---|---|
| `ink` | Texto principal | `#14284B` azul marino | 13,68:1 | 4,5:1 ✔ |
| `inkMuted` | Texto secundario | `#4B5568` | 7,01:1 | 4,5:1 ✔ |
| `positive` | Estado positivo (texto o ícono) | `#4F6F55` salvia | 5,25:1 | 4,5:1 ✔ |
| `positiveContainer` | Fondo de *pill* con texto `#24402B` | `#DCE7D8` | 8,93:1 | 4,5:1 ✔ |
| `secondary` | Acciones secundarias | `#3F64A0` azul suave | 5,54:1 | 4,5:1 ✔ |
| `warning` | Advertencia (texto o ícono) | `#8A5A00` ámbar | 5,54:1 | 4,5:1 ✔ |
| `warningContainer` | Fondo con texto `#5C3D00` | `#F7E6C1` | 8,03:1 | 4,5:1 ✔ |
| `emergency` | Solo para SOS: texto blanco sobre coral | `#C2413A` | 5,11:1 | 4,5:1 ✔ |
| `outline` | Bordes decorativos (no texto) | `#D9D3C7` | 1,39:1 | No aplica (decorativo) |

El modo oscuro, la escala tipográfica, los espaciados (base de 4 pt), los radios y el movimiento (con `MediaQuery.disableAnimations`) se definen y revisan con capturas en el incremento 2.

## Riesgos principales

| Riesgo | Tipo | Mitigación |
|---|---|---|
| Ubicación en segundo plano no fiable o rechazada por las tiendas | Producto y plataforma | Fase 1 en primer plano; declaración de Play y validación en dispositivo antes de la Fase 2 (ADR-003) |
| Vigilancia no consentida o control coercitivo | Privacidad y ética | Consentimiento por persona, pausa visible, sin modo oculto, avisos periódicos y notificaciones al unirse un integrante (modelo de amenazas) |
| Menores de edad | Legal | **Propuesta: MVP solo para adultos (18+)** hasta una revisión legal (Ley 1581 de 2012, art. 7; Decreto 1074 de 2015; políticas *Families* de Play). Requiere aprobación |
| Costos inesperados de Firestore | Costos | Lecturas acotadas, *listeners* solo en primer plano, sin historial por defecto, alertas de presupuesto y *spend cap* en Functions (`03-costos.md`) |
| Paquete de MapKit sin mantenimiento | Técnico | Abstracción y Google Maps en ambas plataformas para el MVP (ADR-002) |
| Inicio de sesión de terceros | Tiendas | Si se ofrece Google, también hay que ofrecer Sign in with Apple (guía 4.8 de App Store, según citas en foros oficiales; reconfirmar). En el MVP: solo correo y contraseña |
| No se puede compilar ni probar en dispositivo desde la nube | Proceso | Pasos manuales documentados y CI con *runners* de Android y macOS (costo de minutos por aprobar) |
| Confirmaciones falsas en el SOS | Seguridad | Máquina de estados explícita: "confirmado" solo cuando un integrante pulsa "Lo vi" (ver `02-modelo-de-datos.md`) |
