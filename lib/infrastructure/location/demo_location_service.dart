import 'dart:math' as math;

import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';

/// [DeviceLocationService] del modo demostración: no usa el GPS ni pide
/// permisos reales.
///
/// Las ubicaciones son **sintéticas**: recorren un pequeño círculo (≈ 30 m)
/// alrededor de un origen ficticio ([defaultOrigin] si no se indica otro),
/// en un espacio público y sin relación con ninguna persona. La variación
/// es determinista (la lectura n siempre da el mismo punto) para que las
/// demostraciones y las pruebas sean reproducibles. Como son simuladas, se
/// marcan `isMocked`.
final class DemoLocationService implements DeviceLocationService {
  new({
    this._clock = const SystemClock(),
    GeoPoint? origin,
    this.simulatedPermission = DeviceLocationPermission.notDetermined,
    this._onRequest = DeviceLocationPermission.whileInUse,
  }) : _origin = origin ?? defaultOrigin;

  /// Punto ficticio por defecto: un parque público de Bogotá (no es el
  /// domicilio de nadie).
  static final GeoPoint defaultOrigin = GeoPoint(4.6584, -74.0937);

  /// Radio del recorrido simulado, en grados (≈ 33 m de latitud).
  static const double _wobbleDegrees = 0.0003;

  /// Lecturas por vuelta completa al círculo.
  static const int _steps = 8;

  final Clock _clock;
  final GeoPoint _origin;

  /// Estado que adopta el permiso al pedirlo (por defecto, concedido).
  final DeviceLocationPermission _onRequest;
  int _fixes = 0;

  /// Permiso simulado; por defecto aún sin decidir. Se puede cambiar, p. ej.
  /// para mostrar el estado denegado o el servicio apagado.
  DeviceLocationPermission simulatedPermission;

  /// Veces que se pidió el permiso (para pruebas y demostraciones).
  int requests = 0;

  /// Veces que se intentó abrir los ajustes.
  int settingsOpened = 0;

  @override
  Future<DeviceLocationPermission> permission() async => simulatedPermission;

  /// Como el sistema: solo pregunta si aún se puede preguntar; si no,
  /// devuelve el estado actual sin cambiarlo.
  @override
  Future<DeviceLocationPermission> requestWhileInUse() async {
    requests++;
    if (simulatedPermission == DeviceLocationPermission.notDetermined ||
        simulatedPermission == DeviceLocationPermission.denied) {
      simulatedPermission = _onRequest;
    }
    return simulatedPermission;
  }

  @override
  Future<Result<DeviceFix>> currentFix() async {
    if (simulatedPermission == DeviceLocationPermission.serviceDisabled) {
      return const Err(
        Failure(
          FailureKind.devicePermissionDenied,
          'location-service-disabled',
        ),
      );
    }
    if (!simulatedPermission.isGranted) {
      return const Err(
        Failure(FailureKind.devicePermissionDenied, 'location-permission'),
      );
    }
    final step = _fixes++ % _steps;
    final angle = 2 * math.pi * step / _steps;
    final point = GeoPoint.tryCreate(
      _origin.latitude + _wobbleDegrees * math.sin(angle),
      _origin.longitude + _wobbleDegrees * math.cos(angle),
    );
    if (point == null) {
      return const Err(Failure.unavailable('location-unavailable'));
    }
    return Ok(
      DeviceFix(
        point: point,
        accuracyMeters: 15 + 5.0 * (step % 3),
        capturedAt: _clock.now(),
        isMocked: true,
      ),
    );
  }

  /// En demostración no hay ajustes del sistema que abrir: se informa con
  /// honestidad que no se abrieron.
  @override
  Future<bool> openSystemSettings() async {
    settingsOpened++;
    return false;
  }
}
