import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/check_ins/domain/submit_check_in.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/remote_json.dart';
import 'package:nexo_familia/infrastructure/sync/outbox.dart';

/// Constantes de los check-ins en la bandeja de salida.
abstract final class CheckInOutbox {
  /// `OutboxEntry.kind` de los check-ins (clave del `OutboxHandler`).
  static const kind = 'checkIn';
}

/// Check-ins propios: se guardan en la bandeja de salida (ADR-004) para que
/// sobrevivan sin conexión y se envíen en orden con reintentos.
///
/// Solo se consideran entregados cuando el servidor confirmó la escritura:
/// en ese momento `OutboxProcessor` los quita de la bandeja y dejan de
/// aparecer en [watchPending].
final class CheckInRepositoryImpl implements CheckInRepository {
  /// `nudge` pide al procesador de la bandeja que envíe ya (sin esperar a su
  /// temporizador). No debe lanzar.
  new({required this._outbox, required this._clock, required this._nudge});

  final OutboxStore _outbox;
  final Clock _clock;
  final void Function() _nudge;

  @override
  Future<Result<CheckIn>> submit(CheckIn checkIn) async {
    if (CheckInRules.message(checkIn.message) case final code?) {
      return Err(Failure.validation(code));
    }
    final message = checkIn.message?.trim();
    final saved = CheckIn(
      id: checkIn.id,
      familyId: checkIn.familyId,
      uid: checkIn.uid,
      kind: checkIn.kind,
      createdAt: checkIn.createdAt.toUtc(),
      delivery: DeliveryState.pending,
      message: message == null || message.isEmpty ? null : message,
      location: checkIn.location,
    );
    try {
      // Idempotente: repetir el mismo id no crea otra entrada.
      await _outbox.enqueue(
        OutboxEntry(
          id: saved.id,
          kind: CheckInOutbox.kind,
          familyId: saved.familyId,
          payload: CheckInPayload.encode(saved),
          createdAt: _clock.now(),
        ),
      );
    } on Object catch (error) {
      return Err(Failure.unexpected(CheckInFailureCodes.notSaved, error));
    }
    _nudge();
    return Ok(saved);
  }

  @override
  Stream<List<CheckIn>> watchPending(String familyId) => _outbox
      .watch(kind: CheckInOutbox.kind, familyId: familyId)
      .map(
        (entries) => [
          for (final entry in entries) ?CheckInPayload.decode(entry),
        ],
      );

  /// Vuelve a intentar ahora un check-in fallido (o en espera de
  /// reintento). Uno que se está enviando no se toca: el procesador ya lo
  /// tiene en curso.
  Future<VoidResult> retry(String checkInId) async {
    final entry = await _outbox.find(checkInId);
    if (entry == null || entry.kind != CheckInOutbox.kind) {
      return const Err(Failure.notFound(CheckInFailureCodes.notFound));
    }
    if (entry.status != OutboxStatus.sending) {
      await _outbox.requeue(checkInId, _clock.now());
    }
    _nudge();
    return const Ok(null);
  }

  /// Quita de la bandeja un check-in que aún no se envió: ya no se enviará.
  /// Uno que se está enviando no se puede descartar (podría llegar igual).
  Future<VoidResult> discard(String checkInId) async {
    final entry = await _outbox.find(checkInId);
    if (entry == null || entry.kind != CheckInOutbox.kind) {
      return const Err(Failure.notFound(CheckInFailureCodes.notFound));
    }
    if (entry.status == OutboxStatus.sending) {
      return const Err(Failure.conflict(CheckInFailureCodes.sending));
    }
    await _outbox.remove(checkInId);
    return const Ok(null);
  }
}

/// Carga mínima de un check-in en la bandeja:
/// `{familyId, uid, kind, message?, lat?, lng?, clientCreatedAt}` con la
/// fecha en milisegundos desde la época (UTC). Sin claves nulas.
abstract final class CheckInPayload {
  static Json encode(CheckIn checkIn) => {
    'familyId': checkIn.familyId,
    'uid': checkIn.uid,
    'kind': checkIn.kind.name,
    'message': ?checkIn.message,
    if (checkIn.location case final point?) ...{
      'lat': point.latitude,
      'lng': point.longitude,
    },
    'clientCreatedAt': checkIn.createdAt.toUtc().millisecondsSinceEpoch,
  };

  /// `null` si la carga no es válida (no debería ocurrir: solo la escribe
  /// [CheckInRepositoryImpl]).
  static CheckIn? decode(OutboxEntry entry) {
    final payload = entry.payload;
    final uid = RemoteJson.string(payload['uid']);
    final kind = kindOf(payload['kind']);
    if (uid == null || kind == null) return null;
    final lat = RemoteJson.number(payload['lat']);
    final lng = RemoteJson.number(payload['lng']);
    return CheckIn(
      id: entry.id,
      familyId: entry.familyId,
      uid: uid,
      kind: kind,
      createdAt: RemoteJson.date(payload['clientCreatedAt']) ?? entry.createdAt,
      delivery: entry.status == OutboxStatus.failed
          ? DeliveryState.failed
          : DeliveryState.pending,
      message: RemoteJson.string(payload['message']),
      location: lat == null || lng == null
          ? null
          : GeoPoint.tryCreate(lat, lng),
    );
  }

  static CheckInKind? kindOf(Object? value) => switch (value) {
    'ok' => CheckInKind.ok,
    'needHelp' => CheckInKind.needHelp,
    _ => null,
  };
}
