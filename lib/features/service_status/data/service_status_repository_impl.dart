import 'dart:async';

import 'package:nexo_familia/features/service_status/domain/service_status.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';

/// Lee `config/app` (contrato: `docs/architecture/05-api-backend.md`).
/// Cualquier campo ausente, de otro tipo o desconocido se trata como su
/// valor por defecto: un documento mal escrito nunca apaga nada por error.
final class ServiceStatusRepositoryImpl implements ServiceStatusRepository {
  new(this._remote, {this._retryDelay = const Duration(minutes: 1)});

  final RemoteStore _remote;

  /// Tras un error de la escucha (p. ej., `unavailable` o un
  /// `permission-denied` pasajero al renovar la sesión), se vuelve a
  /// escuchar pasado este tiempo: un aviso que el equipo active después
  /// debe llegar igual.
  final Duration _retryDelay;

  @override
  Stream<ServiceFlags> watchFlags() {
    late final StreamController<ServiceFlags> controller;
    StreamSubscription<RemoteDoc?>? subscription;
    Timer? retry;

    void listen() {
      subscription = _remote
          .watchDoc(BackendPaths.appConfig)
          .listen(
            (doc) => controller.add(
              doc == null ? ServiceFlags.defaults : parse(doc.data),
            ),
            onError: (Object _) {
              controller.add(ServiceFlags.defaults);
              unawaited(subscription?.cancel());
              retry = Timer(_retryDelay, listen);
            },
            cancelOnError: true,
          );
    }

    controller = StreamController(
      onListen: listen,
      onCancel: () {
        retry?.cancel();
        return subscription?.cancel();
      },
    );
    return controller.stream;
  }

  static ServiceFlags parse(Json data) => ServiceFlags(
    // Solo un `false` explícito apaga una función.
    checkInsEnabled: data['checkInsEnabled'] != false,
    geofenceEditingEnabled: data['geofenceEditingEnabled'] != false,
    notice: switch (data['notice']) {
      'pushDegraded' => ServiceNotice.pushDegraded,
      'serviceDegraded' => ServiceNotice.serviceDegraded,
      _ => null,
    },
    minBuild: switch (data['minBuild']) {
      final int build when build > 0 => build,
      _ => null,
    },
  );
}
