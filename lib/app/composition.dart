import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/app/firebase_setup.dart';
import 'package:nexo_familia/app/session_providers.dart';
import 'package:nexo_familia/app/sync_coordinator.dart';
import 'package:nexo_familia/app/sync_status_binding.dart';
import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/logging/console_log_sink.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/features/authentication/data/demo_auth_repository.dart';
import 'package:nexo_familia/features/authentication/data/firebase_auth_repository.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/data/family_repository_impl.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/settings/data/drift_preferences_repository.dart';
import 'package:nexo_familia/features/settings/presentation/settings_providers.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';
import 'package:nexo_familia/infrastructure/database/drift_stores.dart';
import 'package:nexo_familia/infrastructure/demo/demo_functions.dart';
import 'package:nexo_familia/infrastructure/demo/in_memory_remote_store.dart';
import 'package:nexo_familia/infrastructure/firebase/firebase_functions_client.dart';
import 'package:nexo_familia/infrastructure/firebase/firestore_remote_store.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/backoff.dart';
import 'package:nexo_familia/infrastructure/sync/outbox.dart';
import 'package:nexo_familia/infrastructure/sync/remote_mirror.dart';
import 'package:riverpod/misc.dart';

/// Coordinador de sincronización de la sesión (la app lo alimenta con los
/// cambios de sesión y del ciclo de vida).
final syncCoordinatorProvider = Provider<SyncCoordinator?>((ref) => null);

/// Conecta la sesión con el coordinador: cada cambio de usuario o de familia
/// activa arranca o detiene la sincronización correspondiente.
final syncBindingProvider = Provider<void>((ref) {
  final coordinator = ref.watch(syncCoordinatorProvider);
  if (coordinator == null) return;
  ref.listen(
    sessionProvider,
    (_, next) => coordinator.onSession(next),
    fireImmediately: true,
  );
});

/// Dependencias concretas de la app para un backend.
final class AppComposition {
  new _({
    required this.overrides,
    required this.coordinator,
    required this._disposers,
  });

  /// Backend de demostración: todo en memoria salvo la base de datos local.
  /// No usa red ni credenciales.
  factory demo({
    required AppDatabase db,
    Clock clock = const SystemClock(),
    LogSink logSink = const ConsoleLogSink(),
    math.Random? random,
  }) {
    final store = InMemoryRemoteStore(clock: clock);
    late final DemoAuthRepository auth;
    final functions = DemoFunctionsClient(
      store: store,
      currentUid: () => auth.currentUser?.uid,
      clock: clock,
      random: random,
    );
    auth = DemoAuthRepository(
      store: store,
      callFunction: functions.call,
      random: random,
    );
    return AppComposition._assemble(
      db: db,
      clock: clock,
      logSink: logSink,
      remote: store,
      functions: functions,
      auth: auth,
      extraDisposers: [auth.dispose, store.dispose],
    );
  }

  /// Backend Firebase (proyecto real o emuladores).
  factory firebase({
    required AppDatabase db,
    required FirebaseHandles firebase,
    Clock clock = const SystemClock(),
    LogSink logSink = const ConsoleLogSink(),
  }) {
    final remote = FirestoreRemoteStore(firebase.firestore);
    final functions = FirebaseFunctionsClient(firebase.functions);
    return AppComposition._assemble(
      db: db,
      clock: clock,
      logSink: logSink,
      remote: remote,
      functions: functions,
      auth: FirebaseAuthRepository(
        auth: firebase.auth,
        remote: remote,
        functions: functions,
      ),
    );
  }

  /// Ensamblaje común a todos los backends: solo cambian el almacén remoto,
  /// las funciones y la autenticación.
  factory _assemble({
    required AppDatabase db,
    required Clock clock,
    required LogSink logSink,
    required RemoteStore remote,
    required FunctionsClient functions,
    required AuthRepository auth,
    List<Future<void> Function()> extraDisposers = const [],
  }) {
    final logger = SafeLogger(sink: logSink, clock: clock);
    final cache = DriftDocumentCache(db);
    final mirror = RemoteMirror(
      remote: remote,
      cache: cache,
      clock: clock,
      logger: logger,
    );
    final outboxStore = DriftOutboxStore(db);
    final outbox = OutboxProcessor(
      store: outboxStore,
      handlers: const {},
      clock: clock,
      logger: logger,
      policies: const {'sos': BackoffPolicy.sos},
    );
    final coordinator = SyncCoordinator(
      mirror: mirror,
      outbox: outbox,
      cache: cache,
      outboxStore: outboxStore,
      logger: logger,
    );
    String? uid() => auth.currentUser?.uid;

    return AppComposition._(
      coordinator: coordinator,
      overrides: [
        clockProvider.overrideWithValue(clock),
        loggerProvider.overrideWithValue(logger),
        syncCoordinatorProvider.overrideWithValue(coordinator),
        preferencesRepositoryProvider.overrideWithValue(
          DriftPreferencesRepository(db),
        ),
        authRepositoryProvider.overrideWithValue(auth),
        familyRepositoryProvider.overrideWithValue(
          FamilyRepositoryImpl(
            functions: functions,
            cache: cache,
            currentUid: uid,
          ),
        ),
        syncStatusProvider.overrideWith((ref) {
          final familyId = ref.watch(activeFamilyIdProvider);
          return familyId == null
              ? Stream.value(SyncStatus.unknown)
              : watchSyncStatus(mirror, familyId);
        }),
      ],
      disposers: [coordinator.dispose, mirror.dispose, ...extraDisposers],
    );
  }

  final List<Override> overrides;
  final SyncCoordinator coordinator;
  final List<Future<void> Function()> _disposers;

  Future<void> dispose() async {
    for (final dispose in _disposers) {
      await dispose();
    }
  }
}
