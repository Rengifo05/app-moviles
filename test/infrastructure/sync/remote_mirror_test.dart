import 'dart:async';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';
import 'package:nexo_familia/infrastructure/database/drift_stores.dart';
import 'package:nexo_familia/infrastructure/demo/in_memory_remote_store.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/backoff.dart';
import 'package:nexo_familia/infrastructure/sync/document_cache.dart';
import 'package:nexo_familia/infrastructure/sync/remote_mirror.dart';

import '../../helpers/fakes.dart';

/// Cuenta las escuchas abiertas sobre el almacén remoto real.
final class _CountingRemote implements RemoteStore {
  new(this._inner);

  final RemoteStore _inner;
  final List<String> watched = [];

  @override
  Stream<List<RemoteDoc>> watchCollection(String path, {RemoteQuery? query}) {
    watched.add(path);
    return _inner.watchCollection(path, query: query);
  }

  @override
  Stream<RemoteDoc?> watchDoc(String path) => _inner.watchDoc(path);

  @override
  Future<Result<RemoteDoc?>> getDoc(String path) => _inner.getDoc(path);

  @override
  Future<VoidResult> commit(List<RemoteWrite> writes) => _inner.commit(writes);
}

/// Caché que delega en Drift y permite detener escrituras, contar purgas y
/// simular fallos.
final class _SpyCache implements DocumentCache {
  new(this._inner);

  final DocumentCache _inner;

  /// Si no es null, `replaceCollection` espera a que se complete (solo en
  /// [gatedCollection], si se indica).
  Completer<void>? replaceGate;
  String? gatedCollection;
  Error? clearScopeError;
  final List<String> clearedScopes = [];

  @override
  Stream<List<CachedDoc>> watchCollection(String collection) =>
      _inner.watchCollection(collection);

  @override
  Stream<CachedDoc?> watchDoc(String collection, String docId) =>
      _inner.watchDoc(collection, docId);

  @override
  Future<void> replaceCollection(
    String collection,
    String scope,
    List<RemoteDoc> docs,
    DateTime syncedAt,
  ) async {
    final gate = replaceGate;
    final only = gatedCollection;
    if (gate != null && (only == null || only == collection)) {
      await gate.future;
    }
    await _inner.replaceCollection(collection, scope, docs, syncedAt);
  }

  @override
  Future<void> upsert(
    String collection,
    String scope,
    RemoteDoc doc,
    DateTime syncedAt,
  ) => _inner.upsert(collection, scope, doc, syncedAt);

  @override
  Future<void> remove(String collection, String docId) =>
      _inner.remove(collection, docId);

  @override
  Future<void> clearScope(String scope) async {
    clearedScopes.add(scope);
    final error = clearScopeError;
    if (error != null) throw error;
    await _inner.clearScope(scope);
  }

  @override
  Future<void> clearAll() => _inner.clearAll();
}

/// Remoto cuyas escuchas controla la prueba. Como Firestore, puede cerrar
/// una escucha (p. ej. tras un error).
final class _ScriptedRemote implements RemoteStore {
  final Map<String, List<StreamController<List<RemoteDoc>>>> listeners = {};

  @override
  Stream<List<RemoteDoc>> watchCollection(String path, {RemoteQuery? query}) {
    final controller = StreamController<List<RemoteDoc>>();
    (listeners[path] ??= []).add(controller);
    return controller.stream;
  }

  @override
  Stream<RemoteDoc?> watchDoc(String path) => throw UnimplementedError();

  @override
  Future<Result<RemoteDoc?>> getDoc(String path) => throw UnimplementedError();

  @override
  Future<VoidResult> commit(List<RemoteWrite> writes) =>
      throw UnimplementedError();
}

const _members = 'families/f1/members';
const _geofences = 'families/f1/geofences';
const _memberships = 'users/u1/memberships';

void main() {
  late FakeClock clock;
  late InMemoryRemoteStore remote;
  late _CountingRemote counting;
  late AppDatabase db;
  late _SpyCache cache;
  late MemoryLogSink sink;
  late RemoteMirror mirror;
  late List<Map<String, MirrorStatus>> statuses;
  late StreamSubscription<Map<String, MirrorStatus>> statusSub;

  setUp(() {
    clock = FakeClock();
    remote = InMemoryRemoteStore(clock: clock);
    counting = _CountingRemote(remote);
    db = AppDatabase(NativeDatabase.memory());
    cache = _SpyCache(DriftDocumentCache(db));
    sink = MemoryLogSink();
    mirror = RemoteMirror(
      remote: counting,
      cache: cache,
      clock: clock,
      logger: SafeLogger(sink: sink, clock: clock),
      // Como en Firestore, el almacén cierra la escucha tras un error: una
      // reconexión rápida mantiene las pruebas breves. La espera real se
      // prueba aparte con tiempo simulado.
      reconnect: const BackoffPolicy(
        base: Duration(milliseconds: 5),
        max: Duration(milliseconds: 20),
      ),
    );
    statuses = [];
    statusSub = mirror.status.listen(statuses.add);
  });

  tearDown(() async {
    await statusSub.cancel();
    await mirror.dispose();
    await remote.dispose();
    await db.close();
  });

  Future<List<String>> cachedIds(String collection) async => [
    for (final d in await cache.watchCollection(collection).first) d.id,
  ];

  List<MirrorConnection?> history(String scope) => [
    for (final s in statuses) s[scope]?.connection,
  ];

  void seed() {
    remote
      ..serverWrite('$_members/a', {
        'role': 'owner',
        'joinedAt': DateTime.utc(2025, 5),
      })
      ..serverWrite('$_members/b', {'role': 'member'})
      ..serverWrite('$_geofences/g1', {'name': 'Zona de prueba'});
  }

  final familySpecs = [
    const MirrorSpec(_members),
    const MirrorSpec(_geofences),
  ];

  test('refleja las colecciones en la caché y queda live', () async {
    seed();
    final syncedAt = clock.now();

    mirror.start('f1', familySpecs);
    await pumpEventQueue();

    expect(await cachedIds(_members), ['a', 'b']);
    expect(await cachedIds(_geofences), ['g1']);
    final a = (await cache.watchDoc(_members, 'a').first)!;
    expect(a.data, {'role': 'owner', 'joinedAt': DateTime.utc(2025, 5)});
    expect(a.syncedAt, syncedAt);
    expect(mirror.isActive('f1'), isTrue);
    expect(mirror.statusOf('f1').connection, MirrorConnection.live);
    expect(mirror.statusOf('f1').lastSyncedAt, syncedAt);
    expect(history('f1'), everyElement(MirrorConnection.live));
  });

  test('un ámbito desconocido está idle', () {
    expect(mirror.statusOf('nadie').connection, MirrorConnection.idle);
    expect(mirror.statusOf('nadie').lastSyncedAt, isNull);
    expect(mirror.isActive('nadie'), isFalse);
  });

  test('altas, cambios y bajas remotas se reflejan', () async {
    seed();
    mirror.start('f1', familySpecs);
    await pumpEventQueue();

    clock.advance(const Duration(minutes: 1));
    remote
      ..serverWrite('$_members/c', {'role': 'member'})
      ..serverWrite('$_members/a', {'role': 'admin'})
      ..serverDelete('$_members/b');
    await pumpEventQueue();

    expect(await cachedIds(_members), ['a', 'c']);
    final a = (await cache.watchDoc(_members, 'a').first)!;
    expect(a.data, {'role': 'admin'});
    expect(a.syncedAt, clock.now());
    expect(mirror.statusOf('f1').lastSyncedAt, clock.now());
  });

  test('respeta la consulta de la especificación', () async {
    for (var i = 1; i <= 3; i++) {
      remote.serverWrite('families/f1/events/e$i', {
        'createdAt': DateTime.utc(2026, 1, i),
      });
    }

    mirror.start('f1', [
      const MirrorSpec(
        'families/f1/events',
        query: RemoteQuery(orderBy: 'createdAt', descending: true, limit: 2),
      ),
    ]);
    await pumpEventQueue();

    expect(await cachedIds('families/f1/events'), ['e2', 'e3']);
  });

  test('start es idempotente: no duplica escuchas', () async {
    seed();
    mirror
      ..start('f1', familySpecs)
      ..start('f1', familySpecs)
      ..start('f1', [const MirrorSpec('families/f1/otra')]);
    await pumpEventQueue();

    expect(counting.watched, [_members, _geofences]);
    expect(await cachedIds('families/f1/otra'), isEmpty);
  });

  test('un error transitorio pasa a offline y conserva la caché', () async {
    seed();
    mirror.start('f1', familySpecs);
    await pumpEventQueue();
    final syncedAt = clock.now();

    clock.advance(const Duration(minutes: 5));
    remote
      ..simulatedFailure = const Failure.network()
      ..serverWrite('$_members/c', {'role': 'member'});
    await pumpEventQueue();

    expect(mirror.statusOf('f1').connection, MirrorConnection.offline);
    expect(mirror.statusOf('f1').lastSyncedAt, syncedAt);
    expect(mirror.isActive('f1'), isTrue);
    expect(await cachedIds(_members), ['a', 'b']);
    expect(cache.clearedScopes, isEmpty);
    final logged = sink.entries.where((e) => e.event == 'mirror.error');
    expect(logged, isNotEmpty);
    for (final entry in logged) {
      expect(entry.fields, {
        'feature': 'sync',
        'kind': 'network',
        'code': 'network',
      });
      expect(entry.toString(), isNot(contains('families')));
    }

    // Se recupera sola en cuanto el servidor vuelve a responder.
    remote
      ..simulatedFailure = null
      ..serverWrite('$_members/d', {'role': 'member'});
    await mirror.status
        .firstWhere((s) => s['f1']?.connection == MirrorConnection.live)
        .timeout(const Duration(seconds: 5));
    expect(mirror.statusOf('f1').connection, MirrorConnection.live);
    expect(mirror.statusOf('f1').lastSyncedAt, clock.now());
    expect(await cachedIds(_members), ['a', 'b', 'c', 'd']);
  });

  test('la señal de caché de Firestore pasa a offline sin cerrar la '
      'escucha, y los datos del servidor vuelven a live', () async {
    final scripted = _ScriptedRemote();
    final m = RemoteMirror(
      remote: scripted,
      cache: cache,
      clock: clock,
      logger: SafeLogger(sink: sink, clock: clock),
    );
    addTearDown(m.dispose);
    m.start('f1', [const MirrorSpec(_members)]);
    final listener = scripted.listeners[_members]!.single
      ..add([
        const RemoteDoc('a', {'role': 'owner'}),
      ]);
    await pumpEventQueue();
    expect(m.statusOf('f1').connection, MirrorConnection.live);

    listener.addError(offlineSignal);
    await pumpEventQueue();
    expect(m.statusOf('f1').connection, MirrorConnection.offline);
    // Sigue la misma escucha: no se abre otra ni se purga nada.
    expect(scripted.listeners[_members], hasLength(1));
    expect(cache.clearedScopes, isEmpty);

    listener.add([
      const RemoteDoc('a', {'role': 'owner'}),
      const RemoteDoc('b', {'role': 'member'}),
    ]);
    await pumpEventQueue();
    expect(m.statusOf('f1').connection, MirrorConnection.live);
    expect(await cachedIds(_members), ['a', 'b']);
  });

  for (final denied in const [
    Failure.permissionDenied(),
    Failure.unauthenticated(),
  ]) {
    test('${denied.code} purga el ámbito y pasa a accessLost', () async {
      seed();
      // Datos de otra familia y del usuario que no deben tocarse.
      await cache.upsert(
        'families/f2/members',
        'f2',
        const RemoteDoc('z', {'role': 'owner'}),
        clock.now(),
      );
      await cache.upsert(
        _memberships,
        DocumentCache.userScope,
        const RemoteDoc('f2', {'role': 'owner'}),
        clock.now(),
      );
      mirror.start('f1', familySpecs);
      await pumpEventQueue();
      statuses.clear();

      remote
        ..simulatedFailure = denied
        ..serverWrite('$_members/c', {'role': 'member'});
      await pumpEventQueue();

      expect(await cachedIds(_members), isEmpty);
      expect(await cachedIds(_geofences), isEmpty);
      expect(await cachedIds('families/f2/members'), ['z']);
      expect(await cachedIds(_memberships), ['f2']);
      expect(mirror.isActive('f1'), isFalse);
      expect(mirror.statusOf('f1').connection, MirrorConnection.accessLost);
      expect(mirror.statusOf('f1').lastSyncedAt, isNull);
      // Las dos colecciones fallan a la vez: una sola purga y un solo
      // cambio de estado, sin pasar por idle.
      expect(cache.clearedScopes, ['f1']);
      expect(history('f1'), [MirrorConnection.accessLost]);

      // Ya no se escucha: nada vuelve a escribir en el ámbito purgado.
      remote
        ..simulatedFailure = null
        ..serverWrite('$_members/d', {'role': 'member'});
      await pumpEventQueue();
      expect(await cachedIds(_members), isEmpty);
    });
  }

  test(
    'perder el acceso con una escritura en curso no deja datos tras purgar',
    () async {
      seed();
      mirror.start('f1', familySpecs);
      await pumpEventQueue();

      // Llega una instantánea de integrantes cuya escritura local tarda…
      cache
        ..replaceGate = Completer<void>()
        ..gatedCollection = _members;
      remote.serverWrite('$_members/c', {'role': 'member'});
      await pumpEventQueue();
      // …y mientras tanto el servidor deniega el acceso a las geocercas.
      remote
        ..simulatedFailure = const Failure.permissionDenied()
        ..serverWrite('$_geofences/g2', {'name': 'Otra zona'});
      await pumpEventQueue();
      cache.replaceGate!.complete();
      await pumpEventQueue();

      expect(mirror.statusOf('f1').connection, MirrorConnection.accessLost);
      expect(await cachedIds(_members), isEmpty);
      expect(await cachedIds(_geofences), isEmpty);
    },
  );

  test('un fallo al purgar se registra y aun así queda accessLost', () async {
    seed();
    mirror.start('f1', familySpecs);
    await pumpEventQueue();
    cache.clearScopeError = StateError('disco lleno');

    remote
      ..simulatedFailure = const Failure.permissionDenied()
      ..serverWrite('$_members/c', {'role': 'member'});
    await pumpEventQueue();

    expect(mirror.statusOf('f1').connection, MirrorConnection.accessLost);
    final failure = sink.entries.singleWhere(
      (e) => e.event == 'mirror.purge_failed',
    );
    expect(failure.fields, {
      'feature': 'sync',
      'kind': 'unexpected',
      'code': 'purge-failed',
    });
  });

  test('stop deja de reflejar, conserva la caché y pasa a idle', () async {
    seed();
    mirror.start('f1', familySpecs);
    await pumpEventQueue();
    final syncedAt = clock.now();

    await mirror.stop('f1');
    clock.advance(const Duration(minutes: 1));
    remote.serverWrite('$_members/c', {'role': 'member'});
    await pumpEventQueue();

    expect(mirror.isActive('f1'), isFalse);
    expect(mirror.statusOf('f1').connection, MirrorConnection.idle);
    expect(mirror.statusOf('f1').lastSyncedAt, syncedAt);
    expect(await cachedIds(_members), ['a', 'b']);

    // Se puede volver a empezar.
    mirror.start('f1', familySpecs);
    await pumpEventQueue();
    expect(await cachedIds(_members), ['a', 'b', 'c']);
    expect(mirror.statusOf('f1').connection, MirrorConnection.live);
  });

  test('stop de un ámbito offline también pasa a idle', () async {
    seed();
    mirror.start('f1', familySpecs);
    await pumpEventQueue();
    final syncedAt = clock.now();
    remote
      ..simulatedFailure = const Failure.unavailable()
      ..serverWrite('$_members/c', {'role': 'member'});
    await pumpEventQueue();
    expect(mirror.statusOf('f1').connection, MirrorConnection.offline);

    await mirror.stop('f1');

    expect(mirror.statusOf('f1').connection, MirrorConnection.idle);
    expect(mirror.statusOf('f1').lastSyncedAt, syncedAt);
  });

  test('stop de un ámbito inactivo no hace nada', () async {
    await mirror.stop('f1');
    await pumpEventQueue();
    expect(statuses, isEmpty);
  });

  test(
    'stop espera la escritura en curso: purgar después no deja datos',
    () async {
      seed();
      cache.replaceGate = Completer<void>();
      mirror.start('f1', [const MirrorSpec(_members)]);
      await pumpEventQueue();

      // Cierre de sesión: el coordinador espera a stop y después borra todo.
      final signOut = mirror.stop('f1').then((_) => cache.clearAll());
      await pumpEventQueue();
      cache.replaceGate!.complete();
      await signOut;
      await pumpEventQueue();

      expect(await cachedIds(_members), isEmpty);
      expect(mirror.isActive('f1'), isFalse);
      expect(mirror.statusOf('f1').connection, MirrorConnection.idle);
      expect(history('f1'), isNot(contains(MirrorConnection.live)));
    },
  );

  test(
    'si el servidor cierra la escucha, se reconecta con espera y vuelve a live',
    () {
      fakeAsync((async) {
        final scripted = _ScriptedRemote();
        final scriptedMirror = RemoteMirror(
          remote: scripted,
          cache: cache,
          clock: clock,
          logger: SafeLogger(sink: sink, clock: clock),
        )..start('f1', [const MirrorSpec(_members)]);
        async.flushMicrotasks();
        final first = scripted.listeners[_members]!.single
          ..add([
            const RemoteDoc('a', {'role': 'owner'}),
          ]);
        async.flushMicrotasks();
        expect(scriptedMirror.statusOf('f1').connection, MirrorConnection.live);
        final syncedAt = clock.now();

        // Como Firestore: tras el error, la escucha termina.
        first.addError(const Failure.unavailable());
        unawaited(first.close());
        async.flushMicrotasks();
        expect(
          scriptedMirror.statusOf('f1').connection,
          MirrorConnection.offline,
        );

        // Espera de 2 s con jitter (±20 %) antes de volver a escuchar.
        async.elapse(const Duration(milliseconds: 1599));
        expect(scripted.listeners[_members], hasLength(1));
        clock.advance(const Duration(seconds: 3));
        async.elapse(const Duration(milliseconds: 801));
        expect(scripted.listeners[_members], hasLength(2));

        final second = scripted.listeners[_members]!.last
          ..add([
            const RemoteDoc('a', {'role': 'owner'}),
            const RemoteDoc('b', {'role': 'member'}),
          ]);
        async.flushMicrotasks();
        final status = scriptedMirror.statusOf('f1');
        expect(status.connection, MirrorConnection.live);
        expect(status.lastSyncedAt, isNot(syncedAt));

        // stop cancela también un reintento pendiente.
        unawaited(second.close());
        async.flushMicrotasks();
        expect(async.pendingTimers, hasLength(1));
        unawaited(scriptedMirror.dispose());
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
        expect(scriptedMirror.isActive('f1'), isFalse);
      });
    },
  );

  test('stopAll detiene todos los ámbitos', () async {
    seed();
    remote.serverWrite('$_memberships/f1', {'role': 'owner'});
    mirror
      ..start('f1', familySpecs)
      ..start(DocumentCache.userScope, [const MirrorSpec(_memberships)]);
    await pumpEventQueue();
    expect(
      mirror.statusOf(DocumentCache.userScope).connection,
      MirrorConnection.live,
    );

    await mirror.stopAll();

    for (final scope in ['f1', DocumentCache.userScope]) {
      expect(mirror.isActive(scope), isFalse);
      expect(mirror.statusOf(scope).connection, MirrorConnection.idle);
    }
    remote.serverWrite('$_memberships/f2', {'role': 'member'});
    await pumpEventQueue();
    expect(await cachedIds(_memberships), ['f1']);
  });

  test('dispose detiene todo y cierra el stream de estado', () async {
    seed();
    final done = Completer<void>();
    final sub = mirror.status.listen(null, onDone: done.complete);
    mirror.start('f1', familySpecs);
    await pumpEventQueue();

    await mirror.dispose();

    expect(done.isCompleted, isTrue);
    expect(mirror.isActive('f1'), isFalse);
    await sub.cancel();
  });
}
