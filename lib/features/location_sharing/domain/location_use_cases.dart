import 'dart:async';

import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';

/// Ubicación que se puede adjuntar a un check-in o a un SOS respetando el
/// consentimiento: `null` si la persona no comparte su ubicación con esa
/// familia, si no hay permiso del sistema o si no se obtiene a tiempo.
///
/// Nunca pide permisos (eso se hace en pantallas que lo explican antes) ni
/// bloquea el flujo que la usa más allá de `timeout`.
final class ResolveShareableLocation {
  new(this._device);

  final DeviceLocationService _device;

  Future<DeviceFix?> call(
    SharingConsent consent, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!consent.isSharing) return null;
    if (!(await _device.permission()).isGranted) return null;
    final Result<DeviceFix> result;
    try {
      result = await _device.currentFix().timeout(timeout);
    } on TimeoutException {
      return null;
    }
    final fix = result.valueOrNull;
    if (fix == null) return null;
    return consent.precision == LocationPrecision.approximate
        ? DeviceFix(
            point: fix.point.approximate(),
            // La precisión declarada no puede ser mejor que el redondeo.
            accuracyMeters: fix.accuracyMeters < 1000
                ? 1000
                : fix.accuracyMeters,
            capturedAt: fix.capturedAt,
            isMocked: fix.isMocked,
          )
        : fix;
  }
}

/// Publica ahora la ubicación propia en una familia.
///
/// Fallos posibles (códigos): `not-sharing` (validación: la persona no
/// activó la compartición), `location-permission` (permiso del sistema
/// denegado), `location-service-disabled`, `location-unavailable`, y los del
/// repositorio (red, permisos del servidor).
final class ShareMyLocationNow {
  new(this._repository, this._device);

  final LocationRepository _repository;
  final DeviceLocationService _device;

  Future<Result<MemberLocation>> call({
    required String familyId,
    required String uid,
    required SharingConsent consent,
  }) async {
    if (!consent.isSharing) {
      return const Err(Failure.validation('not-sharing'));
    }
    final permission = await _device.permission();
    if (permission == DeviceLocationPermission.serviceDisabled) {
      return const Err(
        Failure(
          FailureKind.devicePermissionDenied,
          'location-service-disabled',
        ),
      );
    }
    if (!permission.isGranted) {
      return const Err(
        Failure(FailureKind.devicePermissionDenied, 'location-permission'),
      );
    }
    final fix = await ResolveShareableLocation(_device)(consent);
    if (fix == null) {
      return const Err(Failure.unavailable('location-unavailable'));
    }
    final location = MemberLocation(
      uid: uid,
      point: fix.point,
      accuracyMeters: fix.accuracyMeters,
      capturedAt: fix.capturedAt,
      isApproximate: consent.precision == LocationPrecision.approximate,
    );
    final published = await _repository.publishMyLocation(familyId, location);
    return published.map((_) => location);
  }
}
