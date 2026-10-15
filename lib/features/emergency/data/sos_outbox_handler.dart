import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/emergency/data/emergency_repository_impl.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/outbox.dart';

/// Envía las alertas SOS de la bandeja de salida (`kind` = `'sos'`) con la
/// función `raiseSos` (contrato: `docs/architecture/05-api-backend.md`).
///
/// Idempotente por [OutboxEntry.id] (= `alertId`): si la alerta ya existe,
/// el servidor devuelve lo guardado sin volver a notificar.
///
/// Los fallos del servidor se devuelven tal cual y `OutboxProcessor` decide
/// por su categoría: `network` y `unavailable` (también
/// `notification-unavailable`: la alerta quedó registrada pero el aviso no
/// salió) se reintentan con `BackoffPolicy.sos`; el resto se marca fallido
/// y la interfaz lo muestra con su motivo.
final class SosOutboxHandler implements OutboxHandler {
  new(this._functions);

  final FunctionsClient _functions;

  @override
  Future<VoidResult> send(OutboxEntry entry) async {
    final result = await _functions.call(
      BackendFunctions.raiseSos,
      SosCall.payload(entry),
    );
    return result.map((_) {});
  }
}

/// Entrada de `raiseSos` a partir de una entrada de la bandeja.
abstract final class SosCall {
  /// `{familyId, alertId, lat?, lng?, accuracyM?}`. La familia y el id salen
  /// de la entrada (no de la carga): son la clave de idempotencia. La
  /// ubicación solo viaja completa y válida, y la precisión solo con ella.
  static Json payload(OutboxEntry entry) {
    final (point, accuracy) = SosPayload.location(entry.payload);
    return {
      'familyId': entry.familyId,
      'alertId': entry.id,
      if (point != null) ...{
        'lat': point.latitude,
        'lng': point.longitude,
        'accuracyM': ?accuracy,
      },
    };
  }
}
