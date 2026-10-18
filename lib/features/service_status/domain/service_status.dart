import 'package:meta/meta.dart';

/// Avisos de servicio que el equipo puede activar sin publicar una versión.
/// Son textos traducidos en la app: el servidor solo elige el código, nunca
/// envía texto libre.
enum ServiceNotice {
  /// Los avisos push fallan: las alertas SOS podrían no llegar con la app
  /// cerrada.
  pushDegraded,

  /// El servicio funciona con problemas (lentitud, envíos que tardan).
  serviceDegraded,
}

/// Banderas del servicio (`config/app`). Por defecto todo está activo: sin
/// conexión o sin el documento la app funciona igual (el corte inmediato
/// son las reglas de Firestore; ver el runbook de incidentes).
///
/// El SOS no tiene interruptor a propósito: nunca se apaga en remoto.
@immutable
final class ServiceFlags {
  const new({
    this.checkInsEnabled = true,
    this.geofenceEditingEnabled = true,
    this.notice,
    this.minBuild,
  });

  static const defaults = ServiceFlags();

  final bool checkInsEnabled;
  final bool geofenceEditingEnabled;
  final ServiceNotice? notice;

  /// Compilación mínima recomendada (p. ej., una versión con un fallo
  /// conocido). La app pide actualizar; no bloquea nada.
  final int? minBuild;

  /// `true` si [build] es anterior a [minBuild]. Sin dato, nunca.
  bool updateRecommended(int? build) {
    final min = minBuild;
    return min != null && build != null && build < min;
  }

  @override
  bool operator ==(Object other) =>
      other is ServiceFlags &&
      other.checkInsEnabled == checkInsEnabled &&
      other.geofenceEditingEnabled == geofenceEditingEnabled &&
      other.notice == notice &&
      other.minBuild == minBuild;

  @override
  int get hashCode =>
      Object.hash(checkInsEnabled, geofenceEditingEnabled, notice, minBuild);
}

abstract interface class ServiceStatusRepository {
  /// Banderas vigentes. Nunca termina con error: ante un fallo, los valores
  /// por defecto.
  Stream<ServiceFlags> watchFlags();
}
