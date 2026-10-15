# ADR-002 · Proveedor de mapas y abstracción

- **Estado:** Propuesto. **Requiere aprobación**, porque se aparta parcialmente del prompt maestro, que pedía MapKit en iOS.
- **Fecha:** 2026-10-15

## Contexto

El prompt maestro propone MapKit nativo en iOS y Google Maps en Android, detrás de una abstracción propia, sin duplicar lógica de negocio y con justificación si el costo de mantenimiento es desproporcionado.

## Hallazgos verificados (pub.dev, 2026-10-15)

| Opción | Estado |
|---|---|
| `google_maps_flutter` 2.19.0 | Mantenido por `flutter.dev`; publicado el 2026-10-14; Android, iOS y web. Usa el Google Maps SDK nativo en ambas plataformas |
| `apple_maps_flutter` 1.4.0 | `fluttercommunity.dev`; **último release el 2025-01-23** (21 meses sin actualizar); 130/160 puntos; sin soporte de Swift Package Manager (*legacy native build*). Es el único *wrapper* de MapKit con uso relevante |
| `platform_maps_flutter` | Combina las dos anteriores; **último release en 2021**. Descartado |
| `flutter_map` 8.3.2 | Mantenido (160/160), pero requiere un proveedor de teselas. Los servidores públicos de OpenStreetMap no admiten uso intensivo, así que haría falta uno comercial (costo adicional) |

Precios (fuente: páginas de *usage and billing* de Google citadas en buscadores; **hay que reconfirmar**): el SKU *Mobile Native Dynamic Maps* de los Maps SDK para Android e iOS cuesta **USD 0 por carga y no tiene límite**. Sí se facturan Street View dinámico y los mapas dinámicos con *Map ID* o estilos en la nube, que no usaremos. Se requiere una API key restringida por paquete y bundle ID, y una cuenta de facturación en Google Cloud.

MapKit nativo se incluye con la membresía del Apple Developer Program; Apple publica cuotas para MapKit JS y la Maps Server API, que no usaríamos. No encontramos un límite publicado para el framework nativo; queda **pendiente de confirmar** en los términos del programa.

## Opciones

1. **A. Google Maps en Android e iOS** con `google_maps_flutter`. Un solo plugin mantenido por el equipo de Flutter y un comportamiento uniforme. Contras: añade el SDK de Google en iOS, que debe declararse en las etiquetas de privacidad de App Store y en el manifiesto de privacidad.
2. **B. MapKit en iOS** con `apple_maps_flutter`. Cumple el prompt, pero depende de un paquete sin mantenimiento reciente: riesgo de rotura con nuevas versiones de Flutter o iOS y de la migración a Swift Package Manager.
3. **C. MapKit en iOS con un plugin propio** (*platform view* mínimo en Swift). Cumple el prompt y tenemos control total. Costo: código nativo Swift que mantener, probar en dispositivo y actualizar en cada versión de iOS. Esto no se puede verificar en este entorno, que no tiene macOS.
4. **D. `flutter_map`** con teselas comerciales. Interfaz idéntica, pero añade un proveedor y un costo nuevos, y no es nativo.

## Decisión propuesta

**Abstracción desde el día 1, implementación inicial con la opción A, y la opción C como fase posterior opcional.**

```text
lib/features/location_sharing/presentation/map/
  family_map.dart              # widget público: FamilyMap(markers, zones, onTap…)
  family_map_controller.dart   # contrato: moveTo(), fitBounds(), selectMember()
  adapters/
    google_family_map.dart     # implementación con google_maps_flutter
    list_family_map.dart       # implementación sin mapa (pruebas, accesibilidad, sin API key)
```

- Los tipos del contrato (`GeoPoint`, `MemberMarker`, `ZoneOverlay` y `CameraTarget`) son de dominio y no importan nada del proveedor.
- El adaptador `list_family_map` permite probar los widgets en el host (los *platform views* no se renderizan en `flutter test`). También sirve como vista accesible alternativa ("Ver como lista") y como respaldo si no hay API key.
- Si se aprueba la opción C más adelante, `apple_family_map.dart` implementará el mismo contrato sin tocar la lógica de negocio.

## Consecuencias

- **Credenciales (requieren aprobación):** API keys de Google Maps para Android e iOS, restringidas por *package name* y SHA-1, y por *bundle ID*. Una key de SDK móvil viaja dentro del binario y **no es un secreto**: su protección real son esas restricciones y las cuotas. Aun así, no se versiona. En Android se inyecta con `manifestPlaceholders` desde `local.properties` o una variable de entorno; en iOS, con un `.xcconfig` ignorado por git. En CI se usan secretos del repositorio.
- La revisión visual del mapa real solo es posible en un dispositivo o emulador. En este entorno se valida con el adaptador de lista y pruebas *golden*.
