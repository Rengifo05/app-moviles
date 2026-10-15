import 'dart:async';

import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/emergency/domain/emergency.dart';
import 'package:nexo_familia/features/emergency/domain/sos_codes.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/remote_json.dart';
import 'package:nexo_familia/infrastructure/sync/document_cache.dart';
import 'package:nexo_familia/infrastructure/sync/outbox.dart';

/// Constantes de las alertas SOS en la bandeja de salida.
abstract final class SosOutbox {
  /// `OutboxEntry.kind` de las alertas (clave del `OutboxHandler` y de la
  /// política `BackoffPolicy.sos`).
  static const kind = 'sos';

  /// Por delante de cualquier otra operación pendiente (ADR-004).
  static const priority = 100;
}

/// Alertas SOS (máquina de estados de `docs/architecture/02-modelo-de-datos.md`).
///
/// * Crear una alerta la guarda en la bandeja de salida (sobrevive sin
///   conexión y a un cierre de la app) y la envía `SosOutboxHandler` con la
///   función `raiseSos`, idempotente por el id de la alerta.
/// * [watchAlerts] combina lo que el servidor confirmó (caché local de
///   `families/{f}/emergencies`, reflejada por `RemoteMirror`) con las
///   alertas propias que aún no confirmó (bandeja de salida). Solo lo
///   confirmado por el servidor se muestra como enviado.
/// * "Lo vi" y "Terminar" son escrituras directas validadas por las reglas:
///   necesitan conexión y solo se dan por hechas con `Ok`.
///
/// Nunca registra coordenadas.
final class EmergencyRepositoryImpl implements EmergencyRepository {
  /// `nudge` pide al procesador de la bandeja que envíe ya, sin esperar a su
  /// temporizador. No debe lanzar.
  new({
    required this._outbox,
    required this._cache,
    required this._remote,
    required this._currentUid,
    required this._clock,
    required this._nudge,
  });

  final OutboxStore _outbox;
  final DocumentCache _cache;
  final RemoteStore _remote;
  final String? Function() _currentUid;
  final Clock _clock;
  final void Function() _nudge;

  @override
  Future<Result<EmergencyAlert>> raise(EmergencyAlert alert) async {
    final uid = _currentUid();
    if (uid == null) return const Err(Failure.unauthenticated());
    if (alert.uid != uid) {
      return const Err(Failure.permissionDenied(SosCodes.notOwnAlert));
    }
    // Lo que se guarda es una alerta nueva y pendiente: ni recuento, ni
    // confirmaciones, ni fin, aunque la recibida los trajera.
    final queued = EmergencyAlert(
      id: alert.id,
      familyId: alert.familyId,
      uid: uid,
      createdAt: alert.createdAt.toUtc(),
      delivery: SosDelivery.queued,
      location: alert.location,
      locationAccuracyMeters: alert.location == null
          ? null
          : alert.locationAccuracyMeters,
    );
    try {
      // Idempotente: un id repetido (doble pulsación, reintento) no crea
      // otra entrada.
      await _outbox.enqueue(
        OutboxEntry(
          id: queued.id,
          kind: SosOutbox.kind,
          familyId: queued.familyId,
          payload: SosPayload.encode(queued),
          priority: SosOutbox.priority,
          createdAt: queued.createdAt,
        ),
      );
    } on Object catch (error) {
      return Err(Failure.unexpected(SosCodes.notSaved, error));
    }
    _nudge();
    return Ok(queued);
  }

  @override
  Stream<List<EmergencyAlert>> watchAlerts(String familyId) => _combineLatest(
    _cache.watchCollection(BackendPaths.emergencies(familyId)),
    _outbox.watch(kind: SosOutbox.kind, familyId: familyId),
    (docs, entries) => _merge(familyId, docs, entries),
  );

  List<EmergencyAlert> _merge(
    String familyId,
    List<CachedDoc> docs,
    List<OutboxEntry> entries,
  ) {
    final byId = <String, EmergencyAlert>{};
    // La bandeja solo guarda operaciones de la sesión actual (se purga al
    // cerrar sesión): sus alertas son de quien está usando la app.
    final uid = _currentUid();
    if (uid != null) {
      for (final entry in entries) {
        if (entry.familyId != familyId) continue;
        byId[entry.id] = _localAlert(entry, uid);
      }
    }
    // Si el servidor ya la tiene, manda la versión remota: es la única
    // verificable (registrada, recuento, confirmaciones, fin).
    for (final doc in docs) {
      if (_remoteAlert(familyId, doc) case final alert?) byId[alert.id] = alert;
    }
    return byId.values.toList()..sort(_newestFirst);
  }

  static int _newestFirst(EmergencyAlert a, EmergencyAlert b) {
    final byDate = b.createdAt.compareTo(a.createdAt);
    return byDate != 0 ? byDate : b.id.compareTo(a.id);
  }

  @override
  Future<VoidResult> acknowledge(String familyId, String alertId) async {
    final uid = _currentUid();
    if (uid == null) return const Err(Failure.unauthenticated());
    final doc = await _cachedAlert(familyId, alertId);
    if (doc == null) return const Err(Failure.notFound(SosCodes.notFound));
    if (RemoteJson.string(doc.data['uid']) == uid) {
      return const Err(Failure.validation(SosCodes.cannotAckOwn));
    }
    // Ya confirmada por mí: las reglas solo permiten añadir la propia
    // confirmación, así que no se reescribe.
    if (_acks(doc.data['acks'], doc.syncedAt).any((a) => a.uid == uid)) {
      return const Ok(null);
    }
    return await _remote.commit([
      RemoteWrite.merge(BackendPaths.emergency(familyId, alertId), {
        'acks': {uid: serverTimestamp},
      }),
    ]);
  }

  @override
  Future<VoidResult> resolve(String familyId, String alertId) async {
    final uid = _currentUid();
    if (uid == null) return const Err(Failure.unauthenticated());
    final doc = await _cachedAlert(familyId, alertId);
    if (doc != null) {
      if (RemoteJson.string(doc.data['uid']) != uid) {
        return const Err(Failure.permissionDenied(SosCodes.notAuthor));
      }
      if (RemoteJson.date(doc.data['resolvedAt']) != null) {
        return const Ok(null);
      }
      final result = await _remote.commit([
        RemoteWrite.merge(BackendPaths.emergency(familyId, alertId), const {
          'resolvedAt': serverTimestamp,
        }),
      ]);
      // Terminada: un reintento pendiente (p. ej. completar el aviso) ya no
      // tiene sentido. Uno en curso se deja terminar.
      if (result.isOk) await _discardIfIdle(alertId);
      return result;
    }
    // Aún no la confirmó el servidor: terminarla es dejar de enviarla.
    final entry = await _outbox.find(alertId);
    if (entry == null ||
        entry.kind != SosOutbox.kind ||
        entry.familyId != familyId) {
      return const Err(Failure.notFound(SosCodes.notFound));
    }
    if (entry.status == OutboxStatus.sending) {
      return const Err(Failure.conflict(SosCodes.sending));
    }
    await _outbox.remove(alertId);
    return const Ok(null);
  }

  @override
  Future<VoidResult> retry(String alertId) async {
    final entry = await _outbox.find(alertId);
    if (entry == null || entry.kind != SosOutbox.kind) {
      return const Err(Failure.notFound(SosCodes.notFound));
    }
    // Una que se está enviando no se toca: el procesador ya la tiene.
    if (entry.status != OutboxStatus.sending) {
      await _outbox.requeue(alertId, _clock.now());
    }
    _nudge();
    return const Ok(null);
  }

  Future<CachedDoc?> _cachedAlert(String familyId, String alertId) =>
      _cache.watchDoc(BackendPaths.emergencies(familyId), alertId).first;

  Future<void> _discardIfIdle(String alertId) async {
    final entry = await _outbox.find(alertId);
    if (entry != null &&
        entry.kind == SosOutbox.kind &&
        entry.status != OutboxStatus.sending) {
      await _outbox.remove(alertId);
    }
  }

  static EmergencyAlert _localAlert(OutboxEntry entry, String uid) {
    final (location, accuracy) = SosPayload.location(entry.payload);
    final failed = entry.status == OutboxStatus.failed;
    return EmergencyAlert(
      id: entry.id,
      familyId: entry.familyId,
      uid: uid,
      createdAt: entry.createdAt,
      delivery: switch (entry.status) {
        OutboxStatus.pending => SosDelivery.queued,
        OutboxStatus.sending => SosDelivery.sending,
        OutboxStatus.failed => SosDelivery.failed,
      },
      location: location,
      locationAccuracyMeters: accuracy,
      failureCode: failed ? (entry.lastErrorCode ?? 'unexpected') : null,
    );
  }

  static EmergencyAlert? _remoteAlert(String familyId, CachedDoc doc) {
    final data = doc.data;
    final uid = RemoteJson.string(data['uid']);
    if (uid == null || uid.isEmpty) return null;
    final (location, accuracy) = SosPayload.location(data);
    final notified = RemoteJson.integer(data['notifiedCount']);
    return EmergencyAlert(
      id: doc.id,
      familyId: familyId,
      uid: uid,
      // La hora la fija el servidor; si faltara, la de llegada es la mejor
      // aproximación (nunca se descarta una alerta por eso).
      createdAt: RemoteJson.date(data['createdAt']) ?? doc.syncedAt,
      delivery: SosDelivery.sent,
      location: location,
      locationAccuracyMeters: accuracy,
      // `null` mientras el servidor no conoce el recuento.
      notifiedCount: notified != null && notified >= 0 ? notified : null,
      acks: _acks(data['acks'], doc.syncedAt),
      resolvedAt: RemoteJson.date(data['resolvedAt']),
    );
  }

  /// Confirmaciones `{uid: fecha}` en orden de llegada.
  static List<EmergencyAck> _acks(Object? raw, DateTime fallback) {
    if (raw is! Map) return const [];
    final acks = [
      for (final MapEntry(:key, :value) in raw.entries)
        if (key is String && key.isNotEmpty)
          EmergencyAck(uid: key, at: RemoteJson.date(value) ?? fallback),
    ]..sort((a, b) => a.at.compareTo(b.at));
    return List.unmodifiable(acks);
  }
}

/// Carga de una alerta en la bandeja de salida, que es también la entrada
/// de `raiseSos`: `{familyId, alertId, lat?, lng?, accuracyM?}`. Sin claves
/// nulas.
abstract final class SosPayload {
  static Json encode(EmergencyAlert alert) => {
    'familyId': alert.familyId,
    'alertId': alert.id,
    if (alert.location case final point?) ...{
      'lat': point.latitude,
      'lng': point.longitude,
      if (alert.locationAccuracyMeters case final accuracy?
          when accuracy.isFinite && accuracy >= 0)
        'accuracyM': accuracy,
    },
  };

  /// Ubicación válida (o `null`) y su precisión, de una carga o de un
  /// documento remoto (mismos nombres de campo).
  static (GeoPoint?, double?) location(Json data) {
    final lat = RemoteJson.number(data['lat']);
    final lng = RemoteJson.number(data['lng']);
    final point = lat == null || lng == null
        ? null
        : GeoPoint.tryCreate(lat, lng);
    if (point == null) return (null, null);
    final accuracy = RemoteJson.number(data['accuracyM']);
    return (point, accuracy != null && accuracy >= 0 ? accuracy : null);
  }
}

/// Emite `combine(a, b)` con lo último de cada flujo en cuanto los dos han
/// emitido, y de nuevo cada vez que cualquiera cambia. Los errores se
/// reenvían; termina cuando terminan los dos.
Stream<R> _combineLatest<A, B, R>(
  Stream<A> first,
  Stream<B> second,
  R Function(A a, B b) combine,
) {
  late final StreamController<R> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  late A lastA;
  late B lastB;
  var hasA = false;
  var hasB = false;
  var done = 0;

  void emit() {
    if (hasA && hasB) controller.add(combine(lastA, lastB));
  }

  void onDone() {
    if (++done == 2) unawaited(controller.close());
  }

  controller = StreamController<R>(
    onListen: () {
      subA = first.listen(
        (value) {
          lastA = value;
          hasA = true;
          emit();
        },
        onError: controller.addError,
        onDone: onDone,
      );
      subB = second.listen(
        (value) {
          lastB = value;
          hasB = true;
          emit();
        },
        onError: controller.addError,
        onDone: onDone,
      );
    },
    onPause: () {
      subA?.pause();
      subB?.pause();
    },
    onResume: () {
      subA?.resume();
      subB?.resume();
    },
    onCancel: () async {
      await Future.wait([?subA?.cancel(), ?subB?.cancel()]);
    },
  );
  return controller.stream;
}
