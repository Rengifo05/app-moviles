import 'package:meta/meta.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/features/common/presentation/failure_text.dart';
import 'package:nexo_familia/features/emergency/domain/emergency.dart';
import 'package:nexo_familia/features/emergency/domain/sos_codes.dart';
import 'package:nexo_familia/features/emergency/presentation/sos_view_logic.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Cómo se presenta un paso de la línea de estados.
enum SosStepKind {
  /// Ocurrió y está verificado.
  done,

  /// En curso ahora mismo (p. ej. enviando).
  inProgress,

  /// Aún no ocurre; se espera (no es un error).
  waiting,

  /// Ocurrió pero no como se esperaba (nadie notificado).
  warning,

  /// Falló.
  error,
}

/// Un paso de la línea de estados de la alerta propia.
@immutable
final class SosStep {
  const new(this.kind, this.text, {this.note});

  final SosStepKind kind;
  final String text;

  /// Aclaración secundaria (p. ej. "Enviado no significa que lo hayan
  /// visto").
  final String? note;
}

/// Título principal de la alerta propia según su estado.
String sosTitle(AppLocalizations l10n, EmergencyAlert alert) =>
    switch (alert.status) {
      SosStatus.queued => l10n.emergencyTitleQueued,
      SosStatus.sending => l10n.emergencyTitleSending,
      SosStatus.sent ||
      SosStatus.notified ||
      SosStatus.acknowledged => l10n.emergencyTitleActive,
      SosStatus.failed => l10n.emergencyTitleFailed,
      SosStatus.resolved => l10n.emergencyTitleResolved,
    };

/// Línea de estados **honesta**: solo lo verificado aparece como hecho. Nunca
/// dice "recibido" ni "ayuda en camino"; "la vio" solo con un "Lo vi"
/// explícito de otro integrante.
List<SosStep> sosSteps(
  AppLocalizations l10n,
  EmergencyAlert alert, {
  required String emergencyNumber,
  required String Function(String uid) nameOf,
}) {
  final status = alert.status;
  switch (status) {
    case SosStatus.queued:
      return [SosStep(SosStepKind.waiting, l10n.emergencyStepQueued)];
    case SosStatus.sending:
      return [
        SosStep(SosStepKind.done, l10n.emergencyStepSaved),
        SosStep(SosStepKind.inProgress, l10n.emergencyStepSending),
      ];
    case SosStatus.failed:
      return [
        SosStep(SosStepKind.done, l10n.emergencyStepSaved),
        SosStep(
          SosStepKind.error,
          sosFailureCodeMessage(l10n, alert.failureCode),
        ),
      ];
    case SosStatus.sent ||
        SosStatus.notified ||
        SosStatus.acknowledged ||
        SosStatus.resolved:
      final acks = acksFromOthers(alert);
      final count = alert.notifiedCount;
      return [
        SosStep(SosStepKind.done, l10n.emergencyStepSaved),
        SosStep(SosStepKind.done, l10n.emergencyStepSent),
        switch (count) {
          null => SosStep(SosStepKind.waiting, l10n.emergencyStepNotifyUnknown),
          0 => SosStep(
            SosStepKind.warning,
            l10n.emergencyStepNobodyNotified(emergencyNumber),
          ),
          _ => SosStep(
            SosStepKind.done,
            l10n.emergencyStepNotified(count),
            note: l10n.emergencyStepNotifiedNote,
          ),
        },
        if (acks.isEmpty && status != SosStatus.resolved)
          SosStep(SosStepKind.waiting, l10n.emergencyStepWaitingAck),
        for (final ack in acks)
          SosStep(
            SosStepKind.done,
            l10n.emergencyStepAck(nameOf(ack.uid), ack.at.toLocal()),
          ),
        if (alert.resolvedAt case final at?)
          SosStep(SosStepKind.done, l10n.emergencyStepResolved(at.toLocal())),
      ];
  }
}

/// Mensaje de un fallo del flujo SOS (códigos propios y del servidor), con
/// el mensaje genérico por categoría como respaldo.
String sosFailureMessage(AppLocalizations l10n, Failure failure) =>
    _knownCode(l10n, failure.code) ?? failureMessage(l10n, failure);

/// Motivo de una alerta fallida, de la que solo se conserva el código.
String sosFailureCodeMessage(AppLocalizations l10n, String? code) =>
    _knownCode(l10n, code) ??
    switch (code) {
      'network' => l10n.errorNetwork,
      'unavailable' => l10n.errorUnavailable,
      'unauthenticated' => l10n.errorUnauthenticated,
      'permission-denied' || 'not-allowed' => l10n.errorPermissionDenied,
      _ => l10n.errorUnexpected,
    };

String? _knownCode(AppLocalizations l10n, String? code) => switch (code) {
  SosCodes.cannotAckOwn => l10n.emergencyErrorCannotAckOwn,
  SosCodes.notAuthor => l10n.emergencyErrorNotAuthor,
  SosCodes.notFound => l10n.emergencyErrorNotFound,
  SosCodes.notSaved => l10n.emergencyErrorNotSaved,
  SosCodes.sending => l10n.emergencyErrorSending,
  SosCodes.notMember => l10n.emergencyErrorNotMember,
  SosCodes.rateLimited => l10n.errorRateLimited,
  _ => null,
};
