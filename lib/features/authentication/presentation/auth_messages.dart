import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/features/common/presentation/failure_text.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Mensaje para un código de validación de `AuthValidators`.
String? authValidationMessage(AppLocalizations l10n, String? code) =>
    switch (code) {
      null => null,
      'email-required' => l10n.validationEmailRequired,
      'email-invalid' => l10n.validationEmailInvalid,
      'password-required' => l10n.validationPasswordRequired,
      'password-too-short' ||
      'password-too-weak' => l10n.validationPasswordTooShort,
      'display-name-required' => l10n.validationNameRequired,
      'display-name-too-long' => l10n.validationNameTooLong,
      'adult-confirmation-required' => l10n.validationAdultRequired,
      'privacy-acceptance-required' => l10n.validationPrivacyRequired,
      _ => l10n.errorValidation,
    };

/// Mensaje para un fallo de autenticación.
String authFailureMessage(AppLocalizations l10n, Failure failure) =>
    switch (failure.code) {
      'invalid-credentials' => l10n.authErrorInvalidCredentials,
      'email-in-use' => l10n.authErrorEmailInUse,
      _ when failure.kind == FailureKind.validation => authValidationMessage(
        l10n,
        failure.code,
      )!,
      _ => failureMessage(l10n, failure),
    };
