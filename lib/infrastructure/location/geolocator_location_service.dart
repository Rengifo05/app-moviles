import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// [DeviceLocationService] con geolocator y permission_handler.
///
/// * geolocator: estado del servicio y del permiso, la solicitud, la lectura
///   del GPS y los ajustes de ubicación del sistema. Su solicitud pide
///   "mientras se usa la app" (nunca "siempre": la fase 1 es solo en primer
///   plano, ADR-003): en iOS porque `Info.plist` declara
///   `NSLocationWhenInUseUsageDescription`, y en Android porque el manifiesto
///   no declara `ACCESS_BACKGROUND_LOCATION`. Además funciona sin
///   configuración nativa adicional, a diferencia de la solicitud de
///   permission_handler en iOS, que exige activar la macro
///   `PERMISSION_LOCATION_WHENINUSE` en el Podfile (sin ella, la solicitud
///   se rechazaría sin mostrar el diálogo).
/// * permission_handler: saber si Android aún permite volver a preguntar y
///   abrir los ajustes de la app.
///
/// Nunca pide permisos por su cuenta: [currentFix] falla si no hay permiso
/// en lugar de provocar el diálogo del sistema. Nunca registra coordenadas.
final class GeolocatorLocationService implements DeviceLocationService {
  const new({this.fixTimeout = const Duration(seconds: 15)});

  /// Tiempo máximo para obtener una lectura.
  final Duration fixTimeout;

  /// Margen sobre [fixTimeout] por si la plataforma no respeta su límite.
  static const Duration _timeoutSlack = Duration(seconds: 2);

  static const Failure _permissionFailure = Failure(
    FailureKind.devicePermissionDenied,
    'location-permission',
  );
  static const Failure _serviceFailure = Failure(
    FailureKind.devicePermissionDenied,
    'location-service-disabled',
  );

  // Se lee en cada llamada: las pruebas sustituyen la instancia.
  GeolocatorPlatform get _geolocator => GeolocatorPlatform.instance;

  @override
  Future<DeviceLocationPermission> permission() async {
    try {
      if (!await _geolocator.isLocationServiceEnabled()) {
        return DeviceLocationPermission.serviceDisabled;
      }
      return switch (await _geolocator.checkPermission()) {
        LocationPermission.whileInUse => DeviceLocationPermission.whileInUse,
        LocationPermission.always => DeviceLocationPermission.always,
        LocationPermission.deniedForever =>
          DeviceLocationPermission.deniedForever,
        LocationPermission.unableToDetermine =>
          DeviceLocationPermission.notDetermined,
        // Ni iOS ni Android distinguen "nunca se pidió" de "se negó pero se
        // puede volver a pedir". En Android, la justificación pendiente
        // indica que ya se negó una vez; en iOS una negación se informa como
        // `deniedForever`, así que aquí solo puede ser "sin decidir".
        LocationPermission.denied =>
          await _deniedBefore()
              ? DeviceLocationPermission.denied
              : DeviceLocationPermission.notDetermined,
      };
    } on Object {
      // Sin poder consultarlo, lo prudente es no usar la ubicación.
      return DeviceLocationPermission.denied;
    }
  }

  Future<bool> _deniedBefore() async {
    try {
      return await ph.Permission.locationWhenInUse.shouldShowRequestRationale;
    } on Object {
      return false;
    }
  }

  @override
  Future<DeviceLocationPermission> requestWhileInUse() async {
    try {
      if (!await _geolocator.isLocationServiceEnabled()) {
        return DeviceLocationPermission.serviceDisabled;
      }
      return switch (await _geolocator.requestPermission()) {
        LocationPermission.denied => DeviceLocationPermission.denied,
        LocationPermission.deniedForever =>
          DeviceLocationPermission.deniedForever,
        LocationPermission.unableToDetermine =>
          DeviceLocationPermission.notDetermined,
        // Concedido: se vuelve a leer para comprobar también el servicio.
        LocationPermission.whileInUse ||
        LocationPermission.always => await permission(),
      };
    } on Object {
      // P. ej. otra solicitud en curso: se informa el estado real.
      return await permission();
    }
  }

  @override
  Future<Result<DeviceFix>> currentFix() async {
    final current = await permission();
    if (current == DeviceLocationPermission.serviceDisabled) {
      return const Err(_serviceFailure);
    }
    if (!current.isGranted) return const Err(_permissionFailure);
    try {
      final position = await _geolocator
          .getCurrentPosition(
            locationSettings: LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: fixTimeout,
            ),
          )
          .timeout(fixTimeout + _timeoutSlack);
      return _toFix(position);
    } on LocationServiceDisabledException {
      return const Err(_serviceFailure);
    } on PermissionDeniedException {
      return const Err(_permissionFailure);
    } on Object catch (error) {
      // Tiempo agotado (`TimeoutException`), error de la plataforma o
      // lectura imposible: no hay ubicación que ofrecer.
      return Err(Failure.unavailable('location-unavailable', error));
    }
  }

  static Result<DeviceFix> _toFix(Position position) {
    final point = GeoPoint.tryCreate(position.latitude, position.longitude);
    final accuracy = position.accuracy;
    if (point == null || !accuracy.isFinite || accuracy < 0) {
      return const Err(Failure.unavailable('location-unavailable'));
    }
    return Ok(
      DeviceFix(
        point: point,
        accuracyMeters: accuracy,
        capturedAt: position.timestamp.toUtc(),
        isMocked: position.isMocked,
      ),
    );
  }

  /// Con el servicio apagado abre los ajustes de ubicación del sistema; si
  /// no, los ajustes de la app (donde se cambia el permiso).
  @override
  Future<bool> openSystemSettings() async {
    try {
      if (!await _geolocator.isLocationServiceEnabled()) {
        return await _geolocator.openLocationSettings();
      }
      return await ph.openAppSettings();
    } on Object {
      return false;
    }
  }
}
