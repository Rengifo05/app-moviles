import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/check_ins/domain/submit_check_in.dart';
import 'package:nexo_familia/features/common/presentation/failure_text.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Nombre visible de cada tipo de check-in.
String checkInKindLabel(AppLocalizations l10n, CheckInKind kind) =>
    switch (kind) {
      CheckInKind.ok => l10n.checkInOptionOk,
      CheckInKind.needHelp => l10n.checkInOptionHelp,
    };

/// Mensaje para un fallo de los check-ins; los códigos propios primero y,
/// si no, el mensaje genérico por categoría.
String checkInFailureMessage(AppLocalizations l10n, Failure failure) =>
    switch (failure.code) {
      CheckInFailureCodes.messageTooLong => l10n.checkInMessageTooLong(
        CheckInRules.maxMessageLength,
      ),
      CheckInFailureCodes.noFamily => l10n.checkInNoFamily,
      CheckInFailureCodes.notSaved => l10n.checkInErrorNotSaved,
      CheckInFailureCodes.notFound => l10n.checkInErrorNotFound,
      CheckInFailureCodes.sending => l10n.checkInErrorSending,
      _ => failureMessage(l10n, failure),
    };
