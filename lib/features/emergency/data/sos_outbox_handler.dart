import 'dart:math' as math;

import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/emergency/data/emergency_repository_impl.dart';
import 'package:nexo_familia/features/location_sharing/data/location_repository_impl.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/document_cache.dart';
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
  new(this._functions, {required this._cache, required this._currentUid});

  final FunctionsClient _functions;
  final DocumentCache _cache;
  final String? Function() _currentUid;

  @override
  Future<VoidResult> send(OutboxEntry entry) async {
    final uid = _currentUid();
    final consent = uid == null
        ? null
        : await cachedConsent(_cache, entry.familyId, uid);
    final result = await _functions.call(
      BackendFunctions.raiseSos,
      SosCall.payload(entry, consent: consent),
    );
    return result.map((_) {});
  }
}

/// Entrada de `raiseSos` a partir de una entrada de la bandeja.
abstract final class SosCall {
  /// `{familyId, alertId, lat?, lng?, accuracyM?}`. La familia y el id salen
  /// de la entrada (no de la carga): son la clave de idempotencia. La
  /// ubicación solo viaja completa y válida, y la precisión solo con ella.
  ///
  /// Con [consent] se aplica la decisión VIGENTE (el servidor lo vuelve a
  /// comprobar): sin compartir no viaja la ubicación; con "aproximada", va
  /// redondeada y con una precisión declarada de al menos 1 km.
  static Json payload(OutboxEntry entry, {SharingConsent? consent}) {
    final (captured, capturedAccuracy) = SosPayload.location(entry.payload);
    final point = captured == null ? null : shareablePoint(captured, consent);
    final approximate = consent?.precision == LocationPrecision.approximate;
    final accuracy = approximate && point != null
        ? math.max(capturedAccuracy ?? 0, 1000).toDouble()
        : capturedAccuracy;
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
