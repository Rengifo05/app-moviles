import 'dart:async';

import 'package:meta/meta.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';

/// Códigos de validación del editor que no cubre `GeofenceRules`.
abstract final class GeofenceEditorCodes {
  static const centerRequired = 'geofence-center-required';
}

/// Paso del control de radio, en metros.
const double geofenceRadiusStep = 50;

/// Divisiones del control de radio (de 100 a 2000 m, de 50 en 50).
final int geofenceRadiusDivisions =
    ((GeofenceRules.maxRadiusMeters - GeofenceRules.minRadiusMeters) /
            geofenceRadiusStep)
        .round();

/// Radio dentro del rango del control. Una zona creada por otro cliente
/// con un radio fuera del paso se respeta tal cual (no se redondea al
/// abrirla: guardarla sin tocar el radio no debe cambiarlo).
double clampGeofenceRadius(double meters) => meters.isFinite
    ? meters.clamp(GeofenceRules.minRadiusMeters, GeofenceRules.maxRadiusMeters)
    : GeofenceRules.defaultRadiusMeters;

/// Centro elegido para una zona y de dónde salió. Nunca se muestra como
/// coordenadas.
@immutable
sealed class ZoneCenter {
  const new(this.point);

  final GeoPoint point;
}

/// La ubicación actual del teléfono, con su precisión declarada.
final class CurrentLocationCenter extends ZoneCenter {
  const new(super.point, {required this.accuracyMeters});

  final double accuracyMeters;

  /// Por encima de este valor se advierte que el centro puede no coincidir
  /// con el lugar.
  static const double lowAccuracyMeters = 100;

  bool get isLowAccuracy => accuracyMeters > lowAccuracyMeters;
}

/// Un punto elegido tocando el mapa.
final class MapPickedCenter extends ZoneCenter {
  const new(super.point);
}

/// El centro que ya tenía la zona guardada.
final class SavedCenter extends ZoneCenter {
  const new(super.point);
}

/// Validación del formulario: los códigos de `GeofenceRules` (con el
/// nombre recortado) y, además, que haya un centro.
List<String> validateGeofenceDraft({
  required String name,
  required double radiusMeters,
  required ZoneCenter? center,
}) => [
  ...GeofenceRules.validate(name: name, radiusMeters: radiusMeters),
  if (center == null) GeofenceEditorCodes.centerRequired,
];

/// Resultado de intentar usar la ubicación actual como centro.
@immutable
sealed class LocateOutcome {
  const new();
}

final class Located extends LocateOutcome {
  const new(this.center);

  final CurrentLocationCenter center;
}

/// Aún no hay permiso, pero se puede pedir: primero se explica para qué.
final class LocateNeedsPermission extends LocateOutcome {
  const new();
}

/// La persona no concedió el permiso al pedírselo.
final class LocateDeclined extends LocateOutcome {
  const new();
}

/// Permiso denegado de forma permanente: solo se cambia en los ajustes.
final class LocateBlocked extends LocateOutcome {
  const new();
}

/// El servicio de ubicación del teléfono está apagado.
final class LocateServiceOff extends LocateOutcome {
  const new();
}

/// No se obtuvo una lectura a tiempo (o falló).
final class LocateUnavailable extends LocateOutcome {
  const new();
}

/// Obtiene la ubicación actual del teléfono para usarla como centro de una
/// zona.
///
/// No sirve `ResolveShareableLocation`: aquí no se publica la ubicación de
/// la persona (no depende de su consentimiento de compartir), solo se fija
/// un punto que pasa a ser el centro de la zona. Nunca pide el permiso del
/// sistema sin que la interfaz lo haya explicado antes: [locate] devuelve
/// [LocateNeedsPermission] y la interfaz llama a [requestAndLocate] solo
/// si la persona acepta.
final class ZoneCenterLocator {
  new(this._device, {this._timeout = const Duration(seconds: 10)});

  final DeviceLocationService _device;
  final Duration _timeout;

  Future<LocateOutcome> locate() async =>
      await _afterPermission(await _device.permission(), justAsked: false);

  Future<LocateOutcome> requestAndLocate() async => await _afterPermission(
    await _device.requestWhileInUse(),
    justAsked: true,
  );

  Future<bool> openSystemSettings() => _device.openSystemSettings();

  Future<LocateOutcome> _afterPermission(
    DeviceLocationPermission permission, {
    required bool justAsked,
  }) async => switch (permission) {
    DeviceLocationPermission.whileInUse ||
    DeviceLocationPermission.always => await _fix(),
    DeviceLocationPermission.serviceDisabled => const LocateServiceOff(),
    DeviceLocationPermission.deniedForever => const LocateBlocked(),
    DeviceLocationPermission.notDetermined || DeviceLocationPermission.denied =>
      justAsked ? const LocateDeclined() : const LocateNeedsPermission(),
  };

  Future<LocateOutcome> _fix() async {
    final Result<DeviceFix> result;
    try {
      result = await _device.currentFix().timeout(_timeout);
    } on TimeoutException {
      return const LocateUnavailable();
    }
    return switch (result) {
      Ok(value: final fix) => Located(
        CurrentLocationCenter(fix.point, accuracyMeters: fix.accuracyMeters),
      ),
      Err(failure: Failure(code: 'location-service-disabled')) =>
        const LocateServiceOff(),
      Err(failure: Failure(kind: FailureKind.devicePermissionDenied)) =>
        const LocateBlocked(),
      Err() => const LocateUnavailable(),
    };
  }
}

/// Operaciones sobre zonas que dispara el editor: elige entre crear y
/// actualizar y registra los fallos (solo categoría y código; nunca
/// nombres ni coordenadas).
final class GeofenceActions {
  new({required this._repository, required this._logger});

  final GeofenceRepository _repository;
  final SafeLogger _logger;

  /// Crea la zona si [original] es nulo; si no, la actualiza partiendo de
  /// la versión de [original] (control de concurrencia optimista).
  Future<Result<Geofence>> save({
    required String familyId,
    required Geofence? original,
    required String name,
    required GeoPoint center,
    required double radiusMeters,
  }) async {
    final Result<Geofence> result;
    if (original == null) {
      result = await _repository.create(
        familyId: familyId,
        name: name.trim(),
        center: center,
        radiusMeters: radiusMeters,
      );
    } else {
      result = await _repository.update(
        Geofence(
          id: original.id,
          familyId: original.familyId,
          name: name.trim(),
          center: center,
          radiusMeters: radiusMeters,
          createdBy: original.createdBy,
          version: original.version,
          updatedAt: original.updatedAt,
        ),
      );
    }
    if (result case Err(:final failure)) {
      _warn(original == null ? 'create' : 'update', failure);
    }
    return result;
  }

  Future<VoidResult> delete(Geofence geofence) async {
    final result = await _repository.delete(geofence);
    if (result case Err(:final failure)) _warn('delete', failure);
    return result;
  }

  void _warn(String operation, Failure failure) => _logger.warning(
    'geofences.operation_failed',
    fields: {'feature': 'geofences', 'operation': operation},
    failure: failure,
  );
}
