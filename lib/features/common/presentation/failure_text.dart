import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Mensaje genérico para un fallo según su categoría. Cada pantalla puede
/// traducir antes los códigos específicos que conoce (p. ej.
/// `invitation-invalid`) y recurrir a este como respaldo.
String failureMessage(AppLocalizations l10n, Failure failure) =>
    switch (failure.kind) {
      FailureKind.network => l10n.errorNetwork,
      FailureKind.unavailable => l10n.errorUnavailable,
      FailureKind.rateLimited => l10n.errorRateLimited,
      FailureKind.unauthenticated => l10n.errorUnauthenticated,
      FailureKind.permissionDenied => l10n.errorPermissionDenied,
      FailureKind.devicePermissionDenied => l10n.errorPermissionDenied,
      FailureKind.notFound => l10n.errorNotFound,
      FailureKind.conflict => l10n.errorConflict,
      FailureKind.validation => l10n.errorValidation,
      FailureKind.unexpected => l10n.errorUnexpected,
    };
