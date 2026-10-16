import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/app/session.dart';
import 'package:nexo_familia/app/sync_coordinator.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';
import 'package:nexo_familia/infrastructure/database/drift_stores.dart';
import 'package:nexo_familia/infrastructure/demo/in_memory_remote_store.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/document_cache.dart';
import 'package:nexo_familia/infrastructure/sync/outbox.dart';
import 'package:nexo_familia/infrastructure/sync/remote_mirror.dart';

import '../helpers/fakes.dart';

const ana = AuthUser(uid: 'ana', email: 'ana@example.com');

void main() {
  late FakeClock clock;
  late InMemoryRemoteStore store;
  late AppDatabase db;
  late DriftDocumentCache cache;
  late DriftOutboxStore outboxStore;
  late RemoteMirror mirror;
  late SyncCoordinator coordinator;

  setUp(() {
    clock = FakeClock();
    store = InMemoryRemoteStore(clock: clock);
    db = AppDatabase(NativeDatabase.memory());
    cache = DriftDocumentCache(db);
    outboxStore = DriftOutboxStore(db);
    final logger = SafeLogger(sink: MemoryLogSink(), clock: clock);
    mirror = RemoteMirror(
      remote: store,
      cache: cache,
      clock: clock,
      logger: logger,
    );
    coordinator = SyncCoordinator(
      mirror: mirror,
      outbox: OutboxProcessor(
        store: outboxStore,
        handlers: const {},
        clock: clock,
        logger: logger,
      ),
      cache: cache,
      outboxStore: outboxStore,
      logger: logger,
    );
    for (final f in ['f1', 'f2']) {
      store.serverWrite(BackendPaths.member(f, 'ana'), {
        'uid': 'ana',
        'role': 'owner',
      });
    }
    store
      ..serverWrite('users/ana/memberships/f1', {'familyName': 'Uno'})
      ..serverWrite('users/ana/memberships/f2', {'familyName': 'Dos'});
  });

  tearDown(() async {
    await coordinator.dispose();
    await mirror.dispose();
    await db.close();
  });

  Future<List<CachedDoc>> members(String f) =>
      cache.watchCollection(BackendPaths.members(f)).first;

  Future<void> settle() async {
    await coordinator.settled;
    await pumpEventQueue();
    await coordinator.settled;
  }

  test('con sesión y familia activa refleja usuario y familia', () async {
    coordinator.onSession(const SessionReady(ana, 'f1'));
    await settle();
    expect(mirror.isActive(DocumentCache.userScope), isTrue);
    expect(mirror.isActive('f1'), isTrue);
    expect(await members('f1'), isNotEmpty);
  });

  OutboxEntry entryFor(String id, String familyId) => OutboxEntry(
    id: id,
    kind: 'desconocido',
    familyId: familyId,
    payload: const {},
    createdAt: clock.now(),
  );

  test('al cambiar de familia detiene la anterior pero conserva su copia '
      '(sin conexión se ven los últimos datos, no un vacío)', () async {
    coordinator.onSession(const SessionReady(ana, 'f1'));
    await settle();
    coordinator.onSession(const SessionReady(ana, 'f2'));
    await settle();
    expect(mirror.isActive('f1'), isFalse);
    expect(await members('f1'), isNotEmpty);
    expect(await members('f2'), isNotEmpty);
  });

  test('al dejar de ser integrante purga la copia y la bandeja de esa '
      'familia', () async {
    coordinator.onSession(const SessionReady(ana, 'f1'));
    await settle();
    coordinator.onSession(const SessionReady(ana, 'f2'));
    await settle();
    await outboxStore.enqueue(entryFor('op-f1', 'f1'));
    await outboxStore.enqueue(entryFor('op-f2', 'f2'));

    // Sale de f1 (o la quitan): el servidor borra su membresía.
    store.serverDelete('users/ana/memberships/f1');
    await settle();
    await settle();

    expect(await members('f1'), isEmpty);
    expect(await members('f2'), isNotEmpty);
    expect([for (final e in await outboxStore.watch().first) e.id], ['op-f2']);
  });

  test('sin membresías confirmadas por el servidor no purga nada', () async {
    await cache.upsert(
      BackendPaths.members('f9'),
      'f9',
      const RemoteDoc('ana', {'role': 'owner'}),
      clock.now(),
    );
    await outboxStore.enqueue(entryFor('op-f9', 'f9'));
    // Sin conexión desde el arranque: las membresías nunca llegan.
    store.simulatedFailure = const Failure.network();
    coordinator.onSession(const SessionReady(ana, 'f1'));
    await settle();
    expect(await members('f9'), isNotEmpty);
    expect(await outboxStore.watch().first, hasLength(1));
  });

  test('en segundo plano se detiene sin purgar (datos sin conexión)', () async {
    coordinator.onSession(const SessionReady(ana, 'f1'));
    await settle();
    coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
    await settle();
    expect(mirror.isActive('f1'), isFalse);
    expect(await members('f1'), isNotEmpty);
    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settle();
    expect(mirror.isActive('f1'), isTrue);
  });

  test('un diálogo del sistema (inactive) no detiene las escuchas', () async {
    coordinator.onSession(const SessionReady(ana, 'f1'));
    await settle();
    coordinator.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await settle();
    expect(mirror.isActive('f1'), isTrue);
    coordinator.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await settle();
    expect(mirror.isActive('f1'), isFalse);
  });

  test('al cerrar sesión purga la caché y la bandeja de salida', () async {
    coordinator.onSession(const SessionReady(ana, 'f1'));
    await settle();
    await outboxStore.enqueue(
      OutboxEntry(
        id: 'op-1',
        kind: 'desconocido',
        familyId: 'f1',
        payload: const {},
        createdAt: clock.now(),
      ),
    );
    coordinator.onSession(const SignedOut());
    await settle();
    expect(await members('f1'), isEmpty);
    expect(await outboxStore.watch().first, isEmpty);
    expect(mirror.isActive(DocumentCache.userScope), isFalse);
  });

  test('un paso que falla no impide los siguientes', () async {
    // Una base cerrada hace fallar el arranque de la bandeja de salida.
    coordinator.onSession(const SessionReady(ana, 'f1'));
    await settle();
    await db.close();
    coordinator
      ..onSession(const SessionReady(ana, 'f2'))
      ..onSession(const SignedOut());
    await settle();
    expect(mirror.isActive('f1'), isFalse);
    expect(mirror.isActive('f2'), isFalse);
    db = AppDatabase(NativeDatabase.memory());
  });
}
