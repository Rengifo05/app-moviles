import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/features/common/presentation/failure_text.dart';
import 'package:nexo_familia/features/common/presentation/relative_time.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_view_logic.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Nombre visible de un integrante en el mapa ("Tú" para la persona actual).
String locationMemberName(
  AppLocalizations l10n,
  FamilyMember member, {
  required bool isSelf,
}) {
  if (isSelf) return l10n.locationSelf;
  final name = member.displayName.trim();
  return name.isEmpty ? l10n.locationUnnamedMember : name;
}

/// Estado de una ubicación, p. ej. "Ubicación actualizada hace 3 min" o
/// "Sin actualización reciente. Última ubicación hace 3 h". Nunca afirma que
/// la persona esté bien ni da coordenadas.
String locationStatusText(
  AppLocalizations l10n,
  LocationStatus status, {
  required DateTime now,
}) {
  final reportedAt = status.reportedAt;
  final time = reportedAt == null
      ? null
      : _keepNumberWithUnit(relativeTime(l10n, reportedAt, now));
  return switch ((status.freshness, status.isApproximate, time)) {
    (LocationFreshness.recent, false, final t?) => l10n.locationStatusRecent(t),
    (LocationFreshness.recent, true, final t?) =>
      l10n.locationStatusRecentApprox(t),
    (_, false, final t?) => l10n.locationStatusStale(t),
    (_, true, final t?) => l10n.locationStatusStaleApprox(t),
    (_, false, null) => l10n.locationStatusStaleNoTime,
    (_, true, null) => l10n.locationStatusStaleNoTimeApprox,
  };
}

/// "hace 3 h" no se parte entre el número y la unidad con texto grande.
String _keepNumberWithUnit(String text) =>
    text.replaceAllMapped(_numberSpace, (m) => '${m[1]}\u00A0');

final RegExp _numberSpace = RegExp(r'(\d) ');

/// Descripción completa de un marcador para lectores de pantalla, p. ej.
/// "Ana. Ubicación actualizada hace 3 min".
String locationMarkerDescription(
  AppLocalizations l10n, {
  required String name,
  required LocationStatus status,
  required DateTime now,
}) =>
    l10n.locationMarkerLabel(name, locationStatusText(l10n, status, now: now));

/// Motivo de un fallo al compartir la ubicación (códigos de
/// `ShareMyLocationNow` y del repositorio); recurre al mensaje genérico.
String locationFailureReason(AppLocalizations l10n, Failure failure) =>
    switch (failure.code) {
      'location-permission' => l10n.locationErrorPermission,
      'location-service-disabled' => l10n.locationErrorServiceDisabled,
      'location-unavailable' => l10n.locationErrorUnavailable,
      'not-sharing' => l10n.locationErrorNotSharing,
      _ when failure.kind == FailureKind.permissionDenied =>
        l10n.locationErrorRejected,
      _ => failureMessage(l10n, failure),
    };

/// Si el fallo se resuelve en los ajustes del sistema.
bool locationFailureNeedsSettings(Failure failure) =>
    failure.code == 'location-permission' ||
    failure.code == 'location-service-disabled';
