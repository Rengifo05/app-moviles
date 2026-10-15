import 'dart:async';

import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/infrastructure/sync/remote_mirror.dart';

/// Estado de conexión de un ámbito del espejo, tal como lo muestra la
/// interfaz.
///
/// `offline` solo se emite si dura más que [grace]: al arrancar, Firestore
/// entrega primero su caché local y enseguida los datos del servidor, y un
/// aviso de "Sin conexión" que parpadea un instante confunde. `live` se
/// emite al momento. Sin escuchas (app en segundo plano o ámbito detenido)
/// el estado es `unknown`: no se afirma ni conexión ni desconexión.
Stream<SyncStatus> watchSyncStatus(
  RemoteMirror mirror,
  String scope, {
  Duration grace = const Duration(seconds: 3),
}) {
  late final StreamController<SyncStatus> controller;
  StreamSubscription<Map<String, MirrorStatus>>? subscription;
  Timer? pendingOffline;
  SyncStatus? last;

  void emit(SyncStatus status) {
    if (status == last) return;
    last = status;
    controller.add(status);
  }

  void apply(MirrorStatus status) {
    if (status.connection == MirrorConnection.offline) {
      pendingOffline ??= Timer(grace, () => emit(SyncStatus.offline));
      return;
    }
    pendingOffline?.cancel();
    pendingOffline = null;
    emit(switch (status.connection) {
      MirrorConnection.live => SyncStatus.live,
      _ => SyncStatus.unknown,
    });
  }

  controller = StreamController<SyncStatus>(
    onListen: () {
      apply(mirror.statusOf(scope));
      subscription = mirror.status.listen(
        (all) => apply(all[scope] ?? MirrorStatus.idle),
      );
    },
    onCancel: () async {
      pendingOffline?.cancel();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}
