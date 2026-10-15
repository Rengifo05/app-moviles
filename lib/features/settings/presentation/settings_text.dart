import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/features/common/presentation/failure_text.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/settings/presentation/privacy_actions.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Motivo de un fallo al cambiar el consentimiento. Un rechazo del servidor
/// suele significar que la persona ya no pertenece a la familia.
String consentFailureReason(AppLocalizations l10n, Failure failure) =>
    failure.kind == FailureKind.permissionDenied
    ? l10n.settingsPrivacyRejected
    : failureMessage(l10n, failure);

/// Mensaje de un cambio de consentimiento que **no** se aplicó: dice qué
/// sigue igual (p. ej. que la familia aún ve la última ubicación).
String consentFailureMessage(
  AppLocalizations l10n,
  ConsentChange change,
  Failure failure,
) {
  final reason = consentFailureReason(l10n, failure);
  return switch (change) {
    ConsentChange.share => l10n.settingsPrivacyShareFailed(reason),
    ConsentChange.pause => l10n.settingsPrivacyPauseFailed(reason),
    ConsentChange.keepPaused => l10n.settingsPrivacyKeepPausedFailed(reason),
    ConsentChange.precision => l10n.settingsPrivacyPrecisionFailed(reason),
  };
}

/// Confirmación de un cambio que el servidor ya aplicó. `null` si no hay
/// nada que añadir a lo que ya muestra el estado (p. ej. activar compartir
/// sin permiso: lo explica el aviso del permiso).
String? consentSuccessMessage(
  AppLocalizations l10n,
  ConsentOutcome outcome,
  SharingConsent consent,
) => switch (outcome.change) {
  ConsentChange.share =>
    outcome.needsPermission ? null : l10n.settingsPrivacySharedOk,
  ConsentChange.pause => l10n.settingsPrivacyPausedOk,
  ConsentChange.keepPaused => l10n.settingsPrivacyKeptPausedOk,
  ConsentChange.precision => switch ((consent.precision, consent.isSharing)) {
    (LocationPrecision.exact, _) => l10n.settingsPrivacyPrecisionOkExact,
    (LocationPrecision.approximate, true) =>
      l10n.settingsPrivacyPrecisionOkApproxSharing,
    (LocationPrecision.approximate, false) =>
      l10n.settingsPrivacyPrecisionOkApprox,
  },
};

/// Título del estado de mi compartición.
String consentStateTitle(AppLocalizations l10n, SharingConsent consent) =>
    switch (consent.state) {
      SharingState.sharing =>
        consent.precision == LocationPrecision.approximate
            ? l10n.settingsPrivacyStateSharingApprox
            : l10n.settingsPrivacyStateSharingExact,
      SharingState.paused => l10n.settingsPrivacyStatePaused,
      SharingState.notConfigured => l10n.settingsPrivacyStateNotConfigured,
    };

String consentStateDetail(AppLocalizations l10n, SharingConsent consent) =>
    switch (consent.state) {
      SharingState.sharing => l10n.settingsPrivacyStateSharingDetail,
      SharingState.paused => l10n.settingsPrivacyStatePausedDetail,
      SharingState.notConfigured =>
        l10n.settingsPrivacyStateNotConfiguredDetail,
    };
