import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/features/common/presentation/failure_text.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';
import 'package:nexo_familia/features/geofences/presentation/geofence_editor_logic.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Códigos del repositorio de zonas (contrato de
/// `GeofenceRepositoryImpl`). Se repiten aquí porque la interfaz no puede
/// importar la capa de datos.
abstract final class GeofenceCodes {
  static const limit = 'geofence-limit';
  static const conflict = 'geofence-conflict';
  static const notFound = 'geofence-not-found';
  static const nameRequired = 'geofence-name-required';
  static const nameTooLong = 'geofence-name-too-long';
  static const radiusOutOfRange = 'geofence-radius-out-of-range';
}

/// Mensaje de un código de validación del formulario (null si no es uno).
String? geofenceValidationMessage(AppLocalizations l10n, String code) =>
    switch (code) {
      GeofenceCodes.nameRequired => l10n.geofenceErrorNameRequired,
      GeofenceCodes.nameTooLong => l10n.geofenceErrorNameTooLong(
        GeofenceRules.maxNameLength,
      ),
      GeofenceCodes.radiusOutOfRange => l10n.geofenceErrorRadius(
        GeofenceRules.minRadiusMeters.round(),
        GeofenceRules.maxRadiusMeters.round(),
      ),
      GeofenceEditorCodes.centerRequired => l10n.geofenceErrorCenterRequired,
      _ => null,
    };

/// Mensaje para un fallo al guardar o eliminar una zona. Traduce los
/// códigos propios y recurre al mensaje genérico por categoría.
String geofenceFailureMessage(AppLocalizations l10n, Failure failure) {
  if (geofenceValidationMessage(l10n, failure.code) case final message?) {
    return message;
  }
  return switch (failure) {
    Failure(code: GeofenceCodes.limit) => l10n.geofenceErrorLimit(
      GeofenceRules.maxPerFamily,
    ),
    Failure(code: GeofenceCodes.conflict) => l10n.geofenceErrorConflict,
    Failure(code: GeofenceCodes.notFound) ||
    Failure(kind: FailureKind.notFound) => l10n.geofenceErrorNotFound,
    // Sin conexión, sin respuesta a tiempo o una transacción que no se
    // pudo completar: no se sabe si el servidor lo aplicó, pero reintentar
    // es seguro (el repositorio es idempotente). Nunca se dice "guardado".
    Failure(kind: FailureKind.network || FailureKind.unavailable) ||
    Failure(kind: FailureKind.conflict) => l10n.geofenceErrorUnconfirmed,
    // Las reglas solo permiten gestionar zonas a owner y admin.
    Failure(kind: FailureKind.permissionDenied) => l10n.geofenceErrorNotAllowed,
    _ => failureMessage(l10n, failure),
  };
}

/// Cómo se eligió el centro, sin coordenadas.
String geofenceCenterText(AppLocalizations l10n, ZoneCenter? center) =>
    switch (center) {
      null => l10n.geofenceCenterNone,
      CurrentLocationCenter(:final accuracyMeters) =>
        l10n.geofenceCenterFromLocation(_roundAccuracy(accuracyMeters)),
      MapPickedCenter() => l10n.geofenceCenterFromMap,
      SavedCenter() => l10n.geofenceCenterSaved,
    };

/// Precisión redondeada hacia arriba: nunca se anuncia más exacta de lo
/// que es.
int _roundAccuracy(double meters) =>
    meters.isFinite && meters > 0 ? meters.ceil() : 0;
