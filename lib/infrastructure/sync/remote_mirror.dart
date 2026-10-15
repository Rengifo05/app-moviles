import 'dart:async';
import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/backoff.dart';
import 'package:nexo_familia/infrastructure/sync/document_cache.dart';

/// Colección remota que se refleja en la caché local.
@immutable
final class MirrorSpec {
  const new(this.path, {this.query});

  final String path;
  final RemoteQuery? query;
}

enum MirrorConnection {
  /// Sin escuchas activas.
  idle,

  /// Recibiendo datos del servidor.
  live,

  /// Se perdió la conexión; la caché conserva los últimos datos.
  offline,

  /// El servidor denegó el acceso (p. ej. la persona salió del grupo). La
  /// caché de ese ámbito ya se purgó.
  accessLost,
}

@immutable
final class MirrorStatus {
  const new(this.connection, {this.lastSyncedAt});

  static const idle = MirrorStatus(MirrorConnection.idle);

  final MirrorConnection connection;
  final DateTime? lastSyncedAt;
}

/// Refleja colecciones remotas de un ámbito (familia activa o usuario) en la
/// caché local mientras la app está en primer plano (ADR-004).
final class RemoteMirror {
  new({
    required this._remote,
    required this._cache,
    required this._clock,
    required this._logger,
    this._reconnect = const BackoffPolicy(),
    double Function()? random,
  }) : _random = random ?? math.Random().nextDouble;

  final RemoteStore _remote;
  final DocumentCache _cache;
  final Clock _clock;
  final SafeLogger _logger;

  /// Espera antes de volver a escuchar una colección cuya escucha terminó.
  final BackoffPolicy _reconnect;
  final double Function() _random;

  final Map<String, _Listening> _listening = {};
  final Map<String, MirrorStatus> _status = {};
  final StreamController<Map<String, MirrorStatus>> _statusController =
      StreamController.broadcast();

  /// Estado por ámbito.
  Stream<Map<String, MirrorStatus>> get status => _statusController.stream;

  MirrorStatus statusOf(String scope) => _status[scope] ?? MirrorStatus.idle;

  bool isActive(String scope) => _listening.containsKey(scope);

  /// Empieza a reflejar [specs] bajo [scope]. Si ya estaba activo, no hace
  /// nada (llamarlo de nuevo es seguro).
  void start(String scope, List<MirrorSpec> specs) {
    if (_listening.containsKey(scope)) return;
    final listening = _listening[scope] = _Listening();
    for (final spec in specs) {
      _listen(scope, listening, spec);
    }
  }

  /// Escucha [spec]. Si el servidor cierra la escucha (Firestore lo hace
  /// tras un error), se vuelve a escuchar con espera exponencial: si no, el
  /// ámbito quedaría `offline` y activo, y `start` no lo repararía.
  /// [failures] cuenta los cierres seguidos sin recibir datos.
  void _listen(
    String scope,
    _Listening listening,
    MirrorSpec spec, [
    int failures = 0,
  ]) {
    // Tras `stop` puede quedar una escritura en curso o un error ya en
    // camino: no deben cambiar el estado de una escucha que ya terminó.
    bool active() => identical(_listening[scope], listening);
    void onError(Object error) {
      if (active()) unawaited(_onError(scope, error));
    }

    var received = false;
    Future<void> apply(List<RemoteDoc> docs) async {
      final now = _clock.now();
      await listening.track(
        _cache.replaceCollection(spec.path, scope, docs, now),
      );
      received = true;
      if (!active()) return;
      _setStatus(scope, MirrorStatus(MirrorConnection.live, lastSyncedAt: now));
    }

    late final StreamSubscription<List<RemoteDoc>> subscription;
    subscription = _remote
        .watchCollection(spec.path, query: spec.query)
        .listen(
          (docs) {
            // Una instantánea a la vez: las siguientes (y el cierre) esperan
            // en la escucha a que termine esta escritura.
            subscription.pause();
            unawaited(
              apply(docs).catchError(onError).whenComplete(subscription.resume),
            );
          },
          onError: onError,
          onDone: () {
            listening.subscriptions.remove(subscription);
            if (!active()) return;
            _setOffline(scope);
            final attempt = received ? 1 : failures + 1;
            listening.retry(
              _reconnect.delayFor(attempt, random: _random()),
              () {
                if (active()) _listen(scope, listening, spec, attempt);
              },
            );
          },
        );
    listening.subscriptions.add(subscription);
  }

  Future<void> _onError(String scope, Object error) async {
    final failure = error is Failure
        ? error
        : Failure.unexpected('mirror', error);
    _logger.warning(
      'mirror.error',
      fields: {'feature': 'sync'},
      failure: failure,
    );
    if (failure.kind == FailureKind.permissionDenied ||
        failure.kind == FailureKind.unauthenticated) {
      // Se deja de escuchar antes de purgar: nada vuelve a escribir en el
      // ámbito después del borrado.
      await _cancel(scope);
      try {
        await _cache.clearScope(scope);
      } on Object catch (clearError) {
        _logger.error(
          'mirror.purge_failed',
          fields: {'feature': 'sync'},
          failure: Failure.unexpected('purge-failed', clearError),
        );
      }
      _setStatus(scope, const MirrorStatus(MirrorConnection.accessLost));
    } else {
      _setOffline(scope);
    }
  }

  /// Pasa a `offline` conservando la última sincronización.
  void _setOffline(String scope) {
    final current = statusOf(scope);
    if (current.connection == MirrorConnection.offline) return;
    _setStatus(
      scope,
      MirrorStatus(
        MirrorConnection.offline,
        lastSyncedAt: current.lastSyncedAt,
      ),
    );
  }

  void _setStatus(String scope, MirrorStatus status) {
    _status[scope] = status;
    if (!_statusController.isClosed) {
      _statusController.add(Map.unmodifiable(_status));
    }
  }

  /// Cancela las escuchas de [scope] y espera sus escrituras en curso;
  /// `false` si no estaba activo.
  Future<bool> _cancel(String scope) async {
    final listening = _listening.remove(scope);
    if (listening == null) return false;
    listening.cancelRetries();
    await Future.wait([
      for (final subscription in listening.subscriptions.toList())
        subscription.cancel(),
    ]);
    // Cancelar no detiene una escritura ya iniciada: si no se espera, puede
    // llegar a la caché después de purgarla (cierre de sesión o acceso
    // perdido) y dejar datos de una familia a la que ya no se pertenece.
    await listening.settled();
    return true;
  }

  /// Deja de reflejar [scope]. La caché conserva los datos y el estado pasa
  /// a `idle` con la última sincronización. Al terminar, nada de [scope]
  /// sigue escribiendo en la caché: se puede purgar a continuación.
  Future<void> stop(String scope) async {
    if (!await _cancel(scope)) return;
    final current = statusOf(scope);
    if (current.connection == MirrorConnection.idle ||
        current.connection == MirrorConnection.accessLost) {
      return;
    }
    _setStatus(
      scope,
      MirrorStatus(MirrorConnection.idle, lastSyncedAt: current.lastSyncedAt),
    );
  }

  Future<void> stopAll() async {
    for (final scope in _listening.keys.toList()) {
      await stop(scope);
    }
  }

  Future<void> dispose() async {
    await stopAll();
    await _statusController.close();
  }
}

/// Escuchas de un ámbito, sus reconexiones pendientes y sus escrituras en
/// la caché aún en curso.
final class _Listening {
  final List<StreamSubscription<void>> subscriptions = [];
  final Set<Timer> _retries = {};
  final Set<Future<void>> _writes = {};

  void retry(Duration delay, void Function() action) {
    late final Timer timer;
    timer = Timer(delay, () {
      _retries.remove(timer);
      action();
    });
    _retries.add(timer);
  }

  void cancelRetries() {
    for (final timer in _retries) {
      timer.cancel();
    }
    _retries.clear();
  }

  Future<void> track(Future<void> write) async {
    _writes.add(write);
    try {
      await write;
    } finally {
      _writes.remove(write);
    }
  }

  /// Termina cuando acaban las escrituras en curso (sus errores ya los
  /// recibe la escucha correspondiente).
  Future<void> settled() => Future.wait([
    for (final write in _writes) write.then<void>((_) {}, onError: (_) {}),
  ]);
}
