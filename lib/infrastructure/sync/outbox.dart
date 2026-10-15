import 'dart:async';
import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/backoff.dart';

enum OutboxStatus { pending, sending, failed }

/// Operación remota pendiente creada en el dispositivo.
@immutable
final class OutboxEntry {
  const new({
    required this.id,
    required this.kind,
    required this.familyId,
    required this.payload,
    required this.createdAt,
    this.priority = 0,
    this.status = OutboxStatus.pending,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastErrorCode,
  });

  /// Clave de idempotencia; también es el id del documento remoto.
  final String id;
  final String kind;
  final String familyId;
  final Json payload;
  final int priority;
  final OutboxStatus status;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastErrorCode;
  final DateTime createdAt;
}

/// Persistencia de la bandeja de salida (Drift en la app; memoria en pruebas).
abstract interface class OutboxStore {
  /// No hace nada si ya existe una entrada con el mismo id (idempotente).
  Future<void> enqueue(OutboxEntry entry);

  /// Entradas `pending` cuyo próximo intento ya venció, por prioridad
  /// descendente y antigüedad.
  Future<List<OutboxEntry>> due(DateTime now);

  /// Momento en que vence la próxima entrada `pending`, o `null` si no hay
  /// ninguna. Una entrada sin `nextAttemptAt` ya venció: se devuelve un
  /// instante del pasado.
  Future<DateTime?> nextAttemptAt();

  Future<void> markSending(String id, DateTime now);

  /// Confirmada por el servidor: se elimina de la bandeja.
  Future<void> remove(String id);

  Future<void> scheduleRetry(
    String id, {
    required int attempts,
    required DateTime nextAttemptAt,
    required String errorCode,
    required DateTime now,
  });

  Future<void> markFailed(
    String id, {
    required String errorCode,
    required DateTime now,
  });

  /// Vuelve a `pending` (reintento manual o recuperación tras un cierre
  /// inesperado durante el envío).
  Future<void> requeue(String id, DateTime now);

  /// Las entradas que quedaron en `sending` (la app se cerró a mitad de
  /// envío) vuelven a `pending`. El envío es idempotente, así que repetirlo
  /// es seguro.
  Future<void> recoverInterrupted(DateTime now);

  Stream<List<OutboxEntry>> watch({String? kind, String? familyId});

  Future<OutboxEntry?> find(String id);
}

/// Envía un tipo de operación al backend. Debe ser idempotente respecto a
/// [OutboxEntry.id].
abstract interface class OutboxHandler {
  Future<VoidResult> send(OutboxEntry entry);
}

/// Procesa la bandeja de salida con reintentos y espera exponencial.
final class OutboxProcessor {
  new({
    required this._store,
    required this._handlers,
    required this._clock,
    required this._logger,
    this._policies = const {},
    double Function()? random,
  }) : _random = random ?? math.Random().nextDouble;

  final OutboxStore _store;
  final Map<String, OutboxHandler> _handlers;
  final Clock _clock;
  final SafeLogger _logger;
  final Map<String, BackoffPolicy> _policies;
  final double Function() _random;

  Timer? _timer;
  Future<void>? _running;
  bool _rerun = false;
  bool _started = false;

  /// Fallos seguidos del almacén (espera de [_scheduleRecovery]).
  int _storeFailures = 0;

  /// Puede haber entradas en `sending` que nadie está enviando (arranque o
  /// fallo del almacén a mitad de envío).
  bool _interrupted = false;

  /// Arranca (o reanuda) el procesamiento. Se puede llamar varias veces.
  Future<void> start() {
    _started = true;
    // Lo que esté en `sending` quedó de un cierre inesperado. Con un
    // procesamiento en curso, en cambio, son las entradas que se están
    // enviando ahora: devolverlas a `pending` falsearía su estado.
    if (_running == null) _interrupted = true;
    return drain();
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Procesa todo lo que esté vencido. Si ya hay un procesamiento en curso,
  /// se repite al terminar (nunca hay dos en paralelo).
  Future<void> drain() {
    if (_running != null) {
      _rerun = true;
      return _running!;
    }
    return _running = _drainLoop().whenComplete(() => _running = null);
  }

  Future<void> _drainLoop() async {
    try {
      // Aquí no hay otra vuelta en curso: nada se está enviando.
      if (_interrupted) {
        await _store.recoverInterrupted(_clock.now());
        _interrupted = false;
      }
      do {
        _rerun = false;
        final entries = await _store.due(_clock.now());
        for (final entry in entries) {
          await _process(entry);
          // Lo que llegó durante el envío (p. ej. un SOS) puede tener más
          // prioridad que el resto de la lista: se vuelve a consultar.
          if (_rerun) break;
        }
        // Un `drain()` que llegue mientras se programa el temporizador
        // también debe repetir la vuelta, o su entrada esperaría al
        // temporizador.
        if (!_rerun) await _scheduleNext();
      } while (_rerun);
      _storeFailures = 0;
    } on Object {
      // El fallo pudo llegar tras `markSending`: la próxima vuelta devuelve
      // esa entrada a `pending`, o quedaría en `sending` para siempre.
      _interrupted = true;
      _scheduleRecovery();
      rethrow;
    }
  }

  /// Tras un fallo del almacén no queda temporizador: sin este reintento lo
  /// pendiente (también un SOS) esperaría al próximo `start()` o `drain()`.
  void _scheduleRecovery() {
    _timer?.cancel();
    _timer = null;
    if (!_started) return;
    _storeFailures++;
    _timer = Timer(
      const BackoffPolicy().delayFor(_storeFailures),
      _drainFromTimer,
    );
  }

  Future<void> _process(OutboxEntry listed) async {
    // La lista puede haber quedado vieja mientras se enviaban las anteriores
    // (entrada cancelada, fallida o ya enviada): se relee antes de enviar.
    final entry = await _store.find(listed.id);
    if (entry == null || entry.status != OutboxStatus.pending) return;
    final handler = _handlers[entry.kind];
    final now = _clock.now();
    if (handler == null) {
      await _store.markFailed(entry.id, errorCode: 'unknown-kind', now: now);
      _logger.error('outbox.unknown_kind', fields: {'opId': entry.id});
      return;
    }
    await _store.markSending(entry.id, now);
    final Result<void> result;
    try {
      result = await handler.send(entry);
    } on Object catch (error) {
      // Un error inesperado no debe detener la bandeja.
      await _retry(entry, Failure.unexpected('handler-threw', error));
      return;
    }
    switch (result) {
      case Ok():
        await _store.remove(entry.id);
        _logger.info(
          'outbox.sent',
          fields: {
            'opId': entry.id,
            'operation': entry.kind,
            'attempt': entry.attempts + 1,
          },
        );
      case Err(:final failure) when failure.isTransient:
        await _retry(entry, failure);
      case Err(:final failure):
        await _store.markFailed(
          entry.id,
          errorCode: failure.code,
          now: _clock.now(),
        );
        _logger.warning(
          'outbox.failed',
          fields: {'opId': entry.id, 'operation': entry.kind},
          failure: failure,
        );
    }
  }

  Future<void> _retry(OutboxEntry entry, Failure failure) async {
    final attempts = entry.attempts + 1;
    final policy = _policies[entry.kind] ?? const BackoffPolicy();
    final delay = policy.delayFor(attempts, random: _random());
    final now = _clock.now();
    await _store.scheduleRetry(
      entry.id,
      attempts: attempts,
      nextAttemptAt: now.add(delay),
      errorCode: failure.code,
      now: now,
    );
    _logger.info(
      'outbox.retry_scheduled',
      fields: {
        'opId': entry.id,
        'operation': entry.kind,
        'attempt': attempts,
        'durationMs': delay,
      },
    );
  }

  Future<void> _scheduleNext() async {
    _timer?.cancel();
    if (!_started) return;
    final next = await _store.nextAttemptAt();
    if (next == null || !_started) return;
    final wait = next.difference(_clock.now());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, _drainFromTimer);
  }

  /// Nadie espera el `Future` del temporizador: un fallo del almacén se
  /// registra (solo su tipo) en lugar de quedar como error no capturado, y
  /// [_scheduleRecovery] ya programó otro intento.
  void _drainFromTimer() {
    unawaited(
      drain().catchError((Object error) {
        _logger.error(
          'outbox.drain_failed',
          fields: {'feature': 'sync'},
          failure: Failure.unexpected('drain-failed', error),
        );
      }),
    );
  }
}
