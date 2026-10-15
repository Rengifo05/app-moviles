import 'dart:async';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/app/sync_status_binding.dart';
import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';
import 'package:nexo_familia/infrastructure/database/drift_stores.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/remote_mirror.dart';

/// Escucha controlada a mano, como una de Firestore.
final class _Remote implements RemoteStore {
  final controllers = <StreamController<List<RemoteDoc>>>[];

  @override
  Stream<List<RemoteDoc>> watchCollection(String path, {RemoteQuery? query}) {
    final controller = StreamController<List<RemoteDoc>>();
    controllers.add(controller);
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

final class _NoLogs implements LogSink {
  @override
  void write(LogEntry entry) {}
}

void main() {
  test('el aviso de sin conexión espera el margen y no parpadea al '
      'arrancar', () {
    fakeAsync((async) {
      final remote = _Remote();
      final db = AppDatabase(NativeDatabase.memory());
      const clock = SystemClock();
      final mirror = RemoteMirror(
        remote: remote,
        cache: DriftDocumentCache(db),
        clock: clock,
        logger: SafeLogger(sink: _NoLogs()),
      );
      final seen = <SyncStatus>[];
      final sub = watchSyncStatus(mirror, 'f1').listen(seen.add);
      async.flushMicrotasks();
      expect(seen, [SyncStatus.unknown]);

      mirror.start('f1', const [MirrorSpec('families/f1/members')]);
      // Arranque: primero la caché (señal offline) y enseguida el servidor.
      final listener = remote.controllers.single..addError(offlineSignal);
      async.elapse(const Duration(milliseconds: 500));
      listener.add(const []);
      async.elapse(const Duration(milliseconds: 100));
      expect(seen, [SyncStatus.unknown, SyncStatus.live]);

      // Una desconexión real sí se muestra, pasado el margen.
      listener.addError(offlineSignal);
      async.elapse(const Duration(seconds: 2));
      expect(seen.last, SyncStatus.live);
      async.elapse(const Duration(seconds: 2));
      expect(seen.last, SyncStatus.offline);

      // Al volver los datos del servidor, live al momento.
      listener.add(const []);
      async.elapse(const Duration(milliseconds: 100));
      expect(seen, [
        SyncStatus.unknown,
        SyncStatus.live,
        SyncStatus.offline,
        SyncStatus.live,
      ]);

      unawaited(sub.cancel());
      unawaited(mirror.dispose());
      unawaited(db.close());
      async.flushMicrotasks();
    });
  });
}
