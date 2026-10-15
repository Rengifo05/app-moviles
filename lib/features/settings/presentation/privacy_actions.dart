import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';

/// Cambio de consentimiento que pidió la persona en Privacidad.
enum ConsentChange {
  /// Empezar o reanudar la compartición.
  share,

  /// Pausar una compartición activa.
  pause,

  /// Decidir no compartir por ahora (desde "Aún no decides").
  keepPaused,

  /// Cambiar entre exacta y aproximada.
  precision,
}

/// Resultado de un cambio de consentimiento. Solo [result] `Ok` significa
/// que el servidor aplicó el cambio: la interfaz nunca lo da por hecho
/// antes.
@immutable
final class ConsentOutcome {
  const new({required this.change, required this.result, this.permission});

  final ConsentChange change;
  final VoidResult result;

  /// Permiso del sistema tras activar la compartición (solo en
  /// [ConsentChange.share]).
  final DeviceLocationPermission? permission;

  bool get applied => result.isOk;

  /// La compartición quedó activa, pero el sistema no deja leer la
  /// ubicación: no se enviará nada hasta conceder el permiso.
  bool get needsPermission =>
      applied &&
      change == ConsentChange.share &&
      !(permission?.isGranted ?? true);
}

/// Operaciones del centro de privacidad sobre **mi** consentimiento en una
/// familia. Nadie puede cambiar la decisión de otra persona: el repositorio
/// y las reglas lo impiden; aquí solo se parte del consentimiento propio.
final class PrivacyActions {
  new({required this._locations, required this._device, required this._logger});

  final LocationRepository _locations;
  final DeviceLocationService _device;
  final SafeLogger _logger;

  /// Activa la compartición. Debe llamarse **después** de la explicación
  /// propia de la app (qué se comparte, con quién y que se puede pausar).
  ///
  /// Si el permiso del sistema no está concedido, lo pide una vez ("mientras
  /// se usa la app"). Aunque quede denegado, la decisión se guarda: la
  /// persona ya eligió compartir, y la interfaz avisa de que no se enviará
  /// nada hasta conceder el permiso.
  Future<ConsentOutcome> share(SharingConsent current) async {
    var permission = await _device.permission();
    if (_canAsk(permission)) {
      permission = await _device.requestWhileInUse();
    }
    final result = await _locations.updateConsent(
      current.copyWith(state: SharingState.sharing),
    );
    _logIfFailed('share', result);
    return ConsentOutcome(
      change: ConsentChange.share,
      result: result,
      permission: permission,
    );
  }

  /// Pausa la compartición. El repositorio borra la ubicación publicada en
  /// la misma operación (amenaza 5).
  Future<ConsentOutcome> pause(SharingConsent current) => _update(
    ConsentChange.pause,
    current.copyWith(state: SharingState.paused),
  );

  /// Deja la decisión en "no compartir" sin haber compartido antes.
  Future<ConsentOutcome> keepPaused(SharingConsent current) => _update(
    ConsentChange.keepPaused,
    current.copyWith(state: SharingState.paused),
  );

  Future<ConsentOutcome> setPrecision(
    SharingConsent current,
    LocationPrecision precision,
  ) => _update(ConsentChange.precision, current.copyWith(precision: precision));

  Future<ConsentOutcome> _update(
    ConsentChange change,
    SharingConsent next,
  ) async {
    final result = await _locations.updateConsent(next);
    _logIfFailed(change.name, result);
    return ConsentOutcome(change: change, result: result);
  }

  /// Solo se pide si el sistema aún puede mostrar su diálogo. Denegado para
  /// siempre o con el servicio apagado, se resuelve en los ajustes.
  static bool _canAsk(DeviceLocationPermission permission) =>
      switch (permission) {
        DeviceLocationPermission.notDetermined ||
        DeviceLocationPermission.denied => true,
        DeviceLocationPermission.whileInUse ||
        DeviceLocationPermission.always ||
        DeviceLocationPermission.deniedForever ||
        DeviceLocationPermission.serviceDisabled => false,
      };

  void _logIfFailed(String operation, VoidResult result) {
    if (result case Err(:final failure)) {
      _logger.warning(
        'settings.consent_failed',
        fields: {'feature': 'settings', 'operation': operation},
        failure: failure,
      );
    }
  }
}

final privacyActionsProvider = Provider<PrivacyActions>(
  (ref) => PrivacyActions(
    locations: ref.watch(locationRepositoryProvider),
    device: ref.watch(deviceLocationServiceProvider),
    logger: ref.watch(loggerProvider),
  ),
);
