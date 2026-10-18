import 'dart:async';

import 'package:nexo_familia/features/service_status/domain/service_status.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';

/// Lee `config/app` (contrato: `docs/architecture/05-api-backend.md`).
/// Cualquier campo ausente, de otro tipo o desconocido se trata como su
/// valor por defecto: un documento mal escrito nunca apaga nada por error.
final class ServiceStatusRepositoryImpl implements ServiceStatusRepository {
  new(this._remote);

  final RemoteStore _remote;

  @override
  Stream<ServiceFlags> watchFlags() => _remote
      .watchDoc(BackendPaths.appConfig)
      .map((doc) => doc == null ? ServiceFlags.defaults : parse(doc.data))
      .transform(
        StreamTransformer.fromHandlers(
          handleError: (_, _, sink) {
            sink
              ..add(ServiceFlags.defaults)
              ..close();
          },
        ),
      );

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
