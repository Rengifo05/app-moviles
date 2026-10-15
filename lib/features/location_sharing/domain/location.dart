import 'package:meta/meta.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/result.dart';

/// Decisión de cada persona sobre compartir su ubicación con una familia.
/// Nadie puede cambiar la decisión de otra persona.
enum SharingState {
  /// Aún no decidió. Equivale a no compartir.
  notConfigured,
  sharing,
  paused,
}

enum LocationPrecision {
  exact,

  /// Redondeada a ≈ 1 km antes de salir del dispositivo.
  approximate,
}

@immutable
final class SharingConsent {
  const new({
    required this.familyId,
    required this.uid,
    required this.state,
    required this.precision,
    this.updatedAt,
  });

  const new initial({required this.familyId, required this.uid})
    : state = SharingState.notConfigured,
      precision = LocationPrecision.exact,
      updatedAt = null;

  final String familyId;
  final String uid;
  final SharingState state;
  final LocationPrecision precision;
  final DateTime? updatedAt;

  bool get isSharing => state == SharingState.sharing;

  SharingConsent copyWith({
    SharingState? state,
    LocationPrecision? precision,
    DateTime? updatedAt,
  }) => SharingConsent(
    familyId: familyId,
    uid: uid,
    state: state ?? this.state,
    precision: precision ?? this.precision,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// Última ubicación conocida de un integrante, tal como la reportó su
/// dispositivo.
@immutable
final class MemberLocation {
  const new({
    required this.uid,
    required this.point,
    required this.accuracyMeters,
    required this.capturedAt,
    required this.isApproximate,
    this.receivedAt,
  });

  final String uid;
  final GeoPoint point;
  final double accuracyMeters;

  /// Hora del dispositivo al capturarla.
  final DateTime capturedAt;

  /// Hora en que la recibió el servidor (null si aún no se sincronizó).
  final DateTime? receivedAt;
  final bool isApproximate;

  /// Frescura relativa a [now]. Nunca implica que la persona esté "a salvo".
  ///
  /// Solo es [LocationFreshness.recent] si la antigüedad está acotada por
  /// [staleAfter] (límite incluido). Ante relojes desajustados se elige la
  /// opción que no exagera la frescura:
  /// * La captura no pudo ocurrir después de que el servidor la recibiera:
  ///   si [capturedAt] es posterior a [receivedAt] (reloj del emisor
  ///   adelantado), manda [receivedAt].
  /// * Una fecha futura respecto a [now] se trata como recién capturada solo
  ///   si el desfase cabe en [staleAfter]. Con un desfase mayor la hora no
  ///   es fiable, y darla por reciente mostraría como nuevo, hasta que el
  ///   reloj alcanzara esa fecha, un dato que puede tener horas o días.
  LocationFreshness freshnessAt(DateTime now, Duration staleAfter) {
    final received = receivedAt;
    final captured = received != null && received.isBefore(capturedAt)
        ? received
        : capturedAt;
    final age = now.difference(captured);
    return age.abs() > staleAfter
        ? LocationFreshness.stale
        : LocationFreshness.recent;
  }
}

enum LocationFreshness { recent, stale }

/// Lectura del GPS del propio dispositivo.
@immutable
final class DeviceFix {
  const new({
    required this.point,
    required this.accuracyMeters,
    required this.capturedAt,
    this.isMocked = false,
  });

  final GeoPoint point;
  final double accuracyMeters;
  final DateTime capturedAt;

  /// El sistema indica que la ubicación es simulada (si lo expone).
  final bool isMocked;
}

/// Estado del permiso de ubicación del sistema operativo.
enum DeviceLocationPermission {
  /// Aún no se ha pedido.
  notDetermined,
  whileInUse,
  always,
  denied,

  /// Denegado de forma permanente: solo se puede cambiar en Ajustes.
  deniedForever,

  /// El servicio de ubicación del dispositivo está apagado.
  serviceDisabled;

  bool get isGranted => this == whileInUse || this == always;
}

/// Acceso a la ubicación del propio dispositivo (implementado con
/// geolocator en `infrastructure/`).
abstract interface class DeviceLocationService {
  Future<DeviceLocationPermission> permission();

  /// Pide "mientras se usa la app". Debe llamarse solo tras la explicación
  /// propia de la app.
  Future<DeviceLocationPermission> requestWhileInUse();

  Future<Result<DeviceFix>> currentFix();

  Future<bool> openSystemSettings();
}

abstract interface class LocationRepository {
  /// Últimas ubicaciones compartidas en la familia (incluida la propia).
  Stream<List<MemberLocation>> watchFamilyLocations(String familyId);

  Stream<SharingConsent> watchMyConsent(String familyId);

  /// Al pausar, el servidor borra la ubicación publicada en la misma
  /// operación (amenaza 5 del modelo de amenazas).
  Future<VoidResult> updateConsent(SharingConsent consent);

  /// Publica la ubicación propia. Falla con `permission-denied` si el
  /// consentimiento no está activo.
  Future<VoidResult> publishMyLocation(
    String familyId,
    MemberLocation location,
  );
}
