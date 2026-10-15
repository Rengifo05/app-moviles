# 03 · Estimación de costos y escalabilidad

> Esto es una **estimación de orden de magnitud, no una medición**. Precios de Firestore Standard en us-central1 tomados el 2026-10-15 de resultados que citan `cloud.google.com/firestore/pricing`. La región `southamerica-east1` puede costar más: **hay que reconfirmar** con la calculadora oficial antes de elegir región.

## Supuestos (familia activa de 4 integrantes, Fase 1 en primer plano)

| Operación | Cálculo | Por familia al día |
|---|---|---|
| Escrituras de ubicación | ~60 por integrante (al abrir la app, check-in, refresco manual y movimiento con la app abierta) | 240 escrituras |
| Lecturas en reglas por cada escritura de ubicación | `get(members)` + `get(consents)` | 480 lecturas |
| Apertura del mapa o de Inicio | 5 aperturas × 4 integrantes × (~11 documentos iniciales + ~4 cambios en vivo) | ~300 lecturas |
| Eventos, check-ins y SOS | Bajo volumen | ~20 escrituras, ~100 lecturas |
| **Total** | | **≈ 260 escrituras y ≈ 900 lecturas** |

## Resultado

- **Cuota gratuita diaria** (50 000 lecturas, 20 000 escrituras): alcanza para unas **50 familias activas** al día. El límite lo marcan las lecturas.
- **Por encima de la cuota** (Blaze): 7 800 escrituras/mes × 0,09/100k + 27 000 lecturas/mes × 0,03/100k ≈ **USD 0,015 por familia al mes**. Mil familias ≈ **USD 14–15 al mes** en Firestore, sin contar la cuota gratuita ni la diferencia regional.
- **Cloud Functions:** solo se invocan para invitaciones, SOS, altas y bajas y borrado de cuenta. Con cientos o miles de familias queda muy por debajo de los 2 M de invocaciones gratuitas al mes. Desplegar implica un pequeño costo de almacenamiento de contenedores.
- **FCM:** sin costo por mensaje (reconfirmar).
- **Mapas:** los mapas nativos de Google Maps SDK cuestan USD 0 por carga y no tienen límite según la documentación citada. No usamos Street View, *Map ID* ni Places en el MVP.
- **La Fase 2 (segundo plano) podría multiplicar las escrituras entre 3 y 10 veces.** Se medirá en dispositivo antes de activarla.

## Costos fijos que requieren aprobación

| Concepto | Costo aproximado | Cuándo |
|---|---|---|
| Cuenta de facturación de Google Cloud (Blaze) | USD 0 de base, pago por uso, con tarjeta | Para desplegar Functions (Día 4 o posterior) |
| Apple Developer Program | ~USD 99 al año (reconfirmar) | Para probar en iPhone físico con capacidades como push, y para publicar |
| Cuenta de desarrollador de Google Play | ~USD 25, pago único (reconfirmar) | Para publicar o usar pruebas internas |
| Minutos de CI en macOS (GitHub Actions) | Según el plan de GitHub y la visibilidad del repo | Para compilar iOS en CI |
| Licencia de `flutter_background_geolocation` | Según el proveedor | Solo si la Fase 2 lo justifica (ADR-003) |
| Revisión legal (Ley 1581, menores, términos) | Variable | Antes de publicar |

## Controles de costo (se implementan en el Día 4)

- *Listeners* solo de la familia activa y solo con la app en primer plano; se cancelan en `paused`.
- Consultas siempre con `limit()` y paginación en el historial.
- Sin *triggers* de Functions sobre escrituras de ubicación, porque multiplicarían el costo por cada actualización.
- Alertas de presupuesto en Cloud Billing al 50 %, 90 % y 100 %, más *spend cap* en Cloud Functions. Firestore no se puede limitar, así que se monitorea.
- Panel de uso revisado semanalmente durante el piloto. Si el costo real supera 2× la estimación, se revisa la frecuencia de ubicación.

## Disponibilidad

- Objetivo inicial realista: **depender del SLA del proveedor**, sin prometer un número propio hasta tener monitoreo.
- Modos de fallo documentados: caída de Firestore (la app muestra los datos de Drift con "Sin conexión con el servidor"), caída de FCM (el SOS queda en `sent` sin `notified`, y se indica), permisos revocados (estado explícito) y cuota agotada en Spark (las escrituras fallan: alerta y paso a Blaze).
