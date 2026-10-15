import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/check_ins/data/check_in_repository_impl.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/outbox.dart';

/// Envía un check-in de la bandeja como evento de la familia
/// (`families/{f}/events/{id}`, contrato en
/// `docs/architecture/05-api-backend.md`).
///
/// Idempotente: el id del documento es el de la operación y se escribe con
/// [RemoteWrite.create], así que un reintento de algo que el servidor ya
/// aceptó no duplica el evento ni choca con las reglas (los eventos nunca se
/// modifican desde el cliente).
final class CheckInOutboxHandler implements OutboxHandler {
  new({required this._remote, required this._clock});

  final RemoteStore _remote;
  final Clock _clock;

  /// Retención de los eventos (TTL de Firestore sobre `expireAt`). Las
  /// reglas aceptan hasta 31 días.
  static const retention = Duration(days: 30);

  /// Carga que no se puede convertir en evento: reintentar no sirve.
  static const invalidPayload = 'check-in-payload-invalid';

  @override
  Future<VoidResult> send(OutboxEntry entry) {
    final checkIn = CheckInPayload.decode(entry);
    if (checkIn == null) {
      return Future.value(const Err(Failure.validation(invalidPayload)));
    }
    return _remote.commit([
      RemoteWrite.create(BackendPaths.event(entry.familyId, entry.id), {
        'type': 'checkIn',
        'actorUid': checkIn.uid,
        'kind': checkIn.kind.name,
        'message': ?checkIn.message,
        if (checkIn.location case final point?) ...{
          'lat': point.latitude,
          'lng': point.longitude,
        },
        'createdAt': serverTimestamp,
        'clientCreatedAt': checkIn.createdAt,
        'expireAt': _clock.now().add(retention),
      }),
    ]);
  }
}
