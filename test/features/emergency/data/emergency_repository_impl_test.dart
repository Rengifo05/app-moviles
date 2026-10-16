import 'dart:async';
import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/emergency/data/emergency_repository_impl.dart';
import 'package:nexo_familia/features/emergency/data/sos_outbox_handler.dart';
import 'package:nexo_familia/features/emergency/domain/emergency.dart';
import 'package:nexo_familia/features/emergency/domain/sos_codes.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';
import 'package:nexo_familia/infrastructure/database/drift_stores.dart';
import 'package:nexo_familia/infrastructure/demo/demo_functions.dart';
import 'package:nexo_familia/infrastructure/demo/in_memory_remote_store.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/backoff.dart';
import 'package:nexo_familia/infrastructure/sync/outbox.dart';
import 'package:nexo_familia/infrastructure/sync/remote_mirror.dart';

import '../../../helpers/fakes.dart';

const _familyId = 'f1';

/// Integración: repositorio + bandeja de salida (Drift en memoria) +
/// `SosOutboxHandler` + funciones de demostración + espejo + caché.
void main() {
  late FakeClock clock;
  late InMemoryRemoteStore store;
  late AppDatabase db;
  late DriftDocumentCache cache;
  late DriftOutboxStore outboxStore;
  late RemoteMirror mirror;
  late OutboxProcessor processor;
  late int nudges;
  String? uid;

  /// Si es `true`, `nudge` procesa la bandeja de inmediato (como en la app);
  /// si no, solo cuenta, para observar el estado "en cola".
  var autoDrain = true;

  EmergencyRepositoryImpl repoFor() => EmergencyRepositoryImpl(
    outbox: outboxStore,
    cache: cache,
    remote: store,
    currentUid: () => uid,
    clock: clock,
    nudge: () {
      nudges++;
      if (autoDrain) unawaited(processor.drain());
    },
  );

  void mirrorFamily() => mirror.start(_familyId, [
    MirrorSpec(
      BackendPaths.emergencies(_familyId),
      query: const RemoteQuery(
        orderBy: 'createdAt',
        descending: true,
        limit: 20,
      ),
    ),
  ]);

  EmergencyAlert alertOf(
    String id, {
    String author = 'ana',
    GeoPoint? location,
    double? accuracy,
  }) => EmergencyAlert(
    id: id,
    familyId: _familyId,
    uid: author,
    createdAt: clock.now(),
    delivery: SosDelivery.queued,
    location: location,
    locationAccuracyMeters: accuracy,
  );

  Future<List<EmergencyAlert>> alertsWhere(
    bool Function(List<EmergencyAlert> alerts) test,
  ) => repoFor()
      .watchAlerts(_familyId)
      .firstWhere(test)
      .timeout(const Duration(seconds: 5));

  Future<EmergencyAlert> alertWhere(
    String id,
    bool Function(EmergencyAlert alert) test,
  ) async {
    final alerts = await alertsWhere(
      (list) => list.any((a) => a.id == id && test(a)),
    );
    return alerts.firstWhere((a) => a.id == id);
  }

  List<Json> sosEvents() => [
    for (final MapEntry(:key, :value) in store.snapshot.entries)
      if (key.startsWith('${BackendPaths.events(_familyId)}/') &&
          value['type'] == 'sos')
        value,
  ];

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
    processor = OutboxProcessor(
      store: outboxStore,
      handlers: {
        SosOutbox.kind: SosOutboxHandler(
          DemoFunctionsClient(
            store: store,
            currentUid: () => uid,
            clock: clock,
            random: math.Random(7),
          ),
          cache: cache,
          currentUid: () => uid,
        ),
      },
      clock: clock,
      logger: logger,
      policies: const {SosOutbox.kind: BackoffPolicy.sos},
      random: () => 0.5,
    );
    nudges = 0;
    autoDrain = true;
    uid = 'ana';
    store
      ..serverWrite('users/ana', {'displayName': 'Ana'})
      ..serverWrite('users/luis', {'displayName': 'Luis'})
      ..serverWrite(BackendPaths.family(_familyId), {
        'name': 'Familia Rojas',
        'createdBy': 'ana',
        'memberCount': 2,
      })
      ..serverWrite(BackendPaths.member(_familyId, 'ana'), {
        'uid': 'ana',
        'displayName': 'Ana',
        'role': 'owner',
        'joinedAt': clock.now(),
      })
      ..serverWrite(BackendPaths.member(_familyId, 'luis'), {
        'uid': 'luis',
        'displayName': 'Luis',
        'role': 'member',
        'joinedAt': clock.now(),
      });
  });

  tearDown(() async {
    processor.stop();
    await mirror.dispose();
    await db.close();
  });

  test('raise: aparece en cola y luego registrada con recuento 0', () async {
    autoDrain = false;
    mirrorFamily();
    final repo = repoFor();
    final raised = await repo.raise(alertOf('sos-1'));
    expect(raised.valueOrNull?.delivery, SosDelivery.queued);
    expect(nudges, 1);

    final queued = await alertWhere('sos-1', (a) => true);
    expect(queued.status, SosStatus.queued);
    expect(queued.uid, 'ana');
    expect(queued.notifiedCount, isNull);
    final entry = await outboxStore.find('sos-1');
    expect(entry?.kind, 'sos');
    expect(entry?.priority, 100);
    expect(entry?.payload, {'familyId': _familyId, 'alertId': 'sos-1'});

    await processor.drain();
    final sent = await alertWhere(
      'sos-1',
      (a) => a.delivery == SosDelivery.sent,
    );
    // En demostración no hay push: el servidor informa 0 con honestidad.
    expect(sent.notifiedCount, 0);
    expect(sent.status, SosStatus.notified);
    expect(await outboxStore.find('sos-1'), isNull);
    expect(sosEvents(), hasLength(1));
  });

  test('sin conexión queda en cola y se envía al volver', () async {
    store.simulatedFailure = const Failure.network();
    final repo = repoFor();
    expect((await repo.raise(alertOf('sos-1'))).isOk, isTrue);
    await processor.drain();

    final entry = await outboxStore.find('sos-1');
    expect(entry?.status, OutboxStatus.pending);
    expect(entry?.attempts, 1);
    expect(entry?.lastErrorCode, 'network');
    final waiting = await alertWhere('sos-1', (a) => true);
    expect(waiting.status, SosStatus.queued);
    // Un reintento pendiente no es un fallo: no se muestra un motivo.
    expect(waiting.failureCode, isNull);
    expect(
      store.snapshot.keys.where((k) => k.contains('/emergencies/')),
      isEmpty,
    );

    store.simulatedFailure = null;
    mirrorFamily();
    clock.advance(const Duration(minutes: 1));
    await processor.drain();
    final sent = await alertWhere(
      'sos-1',
      (a) => a.delivery == SosDelivery.sent,
    );
    expect(sent.status, SosStatus.notified);
  });

  test('el aviso pendiente (notification-unavailable) se reintenta', () async {
    store.simulatedFailure = const Failure.unavailable(
      SosCodes.notificationUnavailable,
    );
    await repoFor().raise(alertOf('sos-1'));
    await processor.drain();
    final entry = await outboxStore.find('sos-1');
    expect(entry?.status, OutboxStatus.pending);
    expect(entry?.lastErrorCode, SosCodes.notificationUnavailable);
  });

  test('idempotencia: el mismo id crea una sola alerta y un aviso', () async {
    autoDrain = false;
    mirrorFamily();
    final repo = repoFor();
    final alert = alertOf('sos-1');
    await repo.raise(alert);
    await repo.raise(alert);
    expect(await outboxStore.watch(kind: 'sos').first, hasLength(1));

    await processor.drain();
    await alertWhere('sos-1', (a) => a.delivery == SosDelivery.sent);

    // Un reintento tardío del mismo id no vuelve a notificar ni duplica.
    await repo.raise(alert);
    await processor.drain();
    final alerts = await alertsWhere(
      (list) => list.every((a) => a.delivery == SosDelivery.sent),
    );
    expect(alerts.where((a) => a.id == 'sos-1'), hasLength(1));
    expect(sosEvents(), hasLength(1));
    expect(
      store.snapshot.keys.where((k) => k.contains('/emergencies/')),
      hasLength(1),
    );
  });

  test('solo se crean alertas a nombre de la sesión actual', () async {
    final repo = repoFor();
    expect(
      (await repo.raise(alertOf('sos-1', author: 'luis'))).failureOrNull,
      const Failure.permissionDenied(SosCodes.notOwnAlert),
    );
    uid = null;
    expect(
      (await repo.raise(alertOf('sos-2'))).failureOrNull?.kind,
      FailureKind.unauthenticated,
    );
    expect(await outboxStore.watch().first, isEmpty);
  });

  test('la ubicación viaja en la carga y vuelve en la alerta', () async {
    mirrorFamily();
    // Comparte su ubicación exacta: el servidor la conserva tal cual.
    store.serverWrite('families/$_familyId/consents/ana', {
      'state': 'sharing',
      'precision': 'exact',
    });
    final repo = repoFor();
    final point = GeoPoint(4.6, -74.08);
    await repo.raise(alertOf('sos-1', location: point, accuracy: 1000));
    final sent = await alertWhere(
      'sos-1',
      (a) => a.delivery == SosDelivery.sent,
    );
    expect(sent.location?.latitude, 4.6);
    expect(sent.location?.longitude, -74.08);
    expect(sent.locationAccuracyMeters, 1000);
  });

  test('confirmación de otro integrante → confirmada', () async {
    mirrorFamily();
    await repoFor().raise(alertOf('sos-1'));
    await alertWhere('sos-1', (a) => a.delivery == SosDelivery.sent);

    uid = 'luis';
    clock.advance(const Duration(minutes: 2));
    expect((await repoFor().acknowledge(_familyId, 'sos-1')).isOk, isTrue);

    uid = 'ana';
    final seen = await alertWhere('sos-1', (a) => a.acks.isNotEmpty);
    expect(seen.status, SosStatus.acknowledged);
    expect(seen.acks.single.uid, 'luis');
    expect(seen.acks.single.at, clock.now());
    expect(seen.acknowledgedBy('luis'), isTrue);
  });

  test('la autora no puede confirmarse a sí misma', () async {
    mirrorFamily();
    await repoFor().raise(alertOf('sos-1'));
    await alertWhere('sos-1', (a) => a.delivery == SosDelivery.sent);

    final result = await repoFor().acknowledge(_familyId, 'sos-1');
    expect(
      result.failureOrNull,
      const Failure.validation(SosCodes.cannotAckOwn),
    );
    final doc = store.snapshot[BackendPaths.emergency(_familyId, 'sos-1')]!;
    expect(doc['acks'], isEmpty);
  });

  test('"Lo vi" sin conexión falla y no se da por hecho', () async {
    mirrorFamily();
    await repoFor().raise(alertOf('sos-1'));
    await alertWhere('sos-1', (a) => a.delivery == SosDelivery.sent);

    uid = 'luis';
    store.simulatedFailure = const Failure.network();
    final result = await repoFor().acknowledge(_familyId, 'sos-1');
    expect(result.failureOrNull?.kind, FailureKind.network);
    store.simulatedFailure = null;
    final doc = store.snapshot[BackendPaths.emergency(_familyId, 'sos-1')]!;
    expect(doc['acks'], isEmpty);
  });

  test('resolve: solo la autora la termina', () async {
    mirrorFamily();
    await repoFor().raise(alertOf('sos-1'));
    await alertWhere('sos-1', (a) => a.delivery == SosDelivery.sent);

    uid = 'luis';
    expect(
      (await repoFor().resolve(_familyId, 'sos-1')).failureOrNull,
      const Failure.permissionDenied(SosCodes.notAuthor),
    );

    uid = 'ana';
    clock.advance(const Duration(minutes: 10));
    expect((await repoFor().resolve(_familyId, 'sos-1')).isOk, isTrue);
    final resolved = await alertWhere('sos-1', (a) => a.resolvedAt != null);
    expect(resolved.status, SosStatus.resolved);
    expect(resolved.resolvedAt, clock.now());
    expect(resolved.isActive, isFalse);
  });

  test('terminar una alerta aún no enviada la quita de la bandeja', () async {
    autoDrain = false;
    final repo = repoFor();
    await repo.raise(alertOf('sos-1'));
    expect((await repo.resolve(_familyId, 'sos-1')).isOk, isTrue);
    expect(await outboxStore.find('sos-1'), isNull);

    await processor.drain();
    expect(
      store.snapshot.keys.where((k) => k.contains('/emergencies/')),
      isEmpty,
    );
    expect(await alertsWhere((_) => true), isEmpty);
  });

  test('una alerta que se está enviando no se puede descartar', () async {
    autoDrain = false;
    final repo = repoFor();
    await repo.raise(alertOf('sos-1'));
    await outboxStore.markSending('sos-1', clock.now());
    expect(
      (await repo.resolve(_familyId, 'sos-1')).failureOrNull,
      const Failure.conflict(SosCodes.sending),
    );
    expect(await outboxStore.find('sos-1'), isNotNull);
  });

  test('un fallo permanente se muestra con su motivo y se reintenta', () async {
    // El espejo empieza después: con este fallo simulado sus escuchas
    // también recibirían permission-denied y purgarían la familia.
    store.simulatedFailure = const Failure.permissionDenied('not-member');
    final repo = repoFor();
    await repo.raise(alertOf('sos-1'));
    await processor.drain();
    final failed = await alertWhere(
      'sos-1',
      (a) => a.delivery == SosDelivery.failed,
    );
    expect(failed.status, SosStatus.failed);
    expect(failed.failureCode, 'not-member');

    store.simulatedFailure = null;
    mirrorFamily();
    nudges = 0;
    expect((await repo.retry('sos-1')).isOk, isTrue);
    expect(nudges, 1);
    final sent = await alertWhere(
      'sos-1',
      (a) => a.delivery == SosDelivery.sent,
    );
    expect(sent.failureCode, isNull);
    expect(
      (await repo.retry('no-existe')).failureOrNull?.code,
      SosCodes.notFound,
    );
  });

  test('las más recientes primero; la remota manda sobre la local', () async {
    autoDrain = false;
    mirrorFamily();
    final repo = repoFor();
    await repo.raise(alertOf('vieja'));
    await processor.drain();
    await alertWhere('vieja', (a) => a.delivery == SosDelivery.sent);

    // La remota lleva la hora del servidor; la local, la del dispositivo.
    clock.advance(const Duration(hours: 1));
    await repo.raise(alertOf('nueva'));
    final alerts = await alertsWhere((list) => list.length == 2);
    expect(alerts.map((a) => a.id), ['nueva', 'vieja']);
    expect(alerts.first.delivery, SosDelivery.queued);
    expect(alerts.last.delivery, SosDelivery.sent);

    // Una entrada local que repite una alerta ya registrada (reintento
    // tardío) no oculta la versión del servidor.
    await outboxStore.enqueue(
      OutboxEntry(
        id: 'vieja',
        kind: SosOutbox.kind,
        familyId: _familyId,
        payload: const {'familyId': _familyId, 'alertId': 'vieja'},
        createdAt: clock.now(),
      ),
    );
    final merged = await alertsWhere((list) => list.length == 2);
    expect(
      merged.firstWhere((a) => a.id == 'vieja').status,
      SosStatus.notified,
    );
  });

  test('ignora documentos remotos sin autora', () async {
    mirrorFamily();
    store.serverWrite(BackendPaths.emergency(_familyId, 'rota'), {
      'createdAt': clock.now(),
    });
    await repoFor().raise(alertOf('sos-1'));
    final alerts = await alertsWhere(
      (list) => list.any((a) => a.delivery == SosDelivery.sent),
    );
    expect(alerts.map((a) => a.id), ['sos-1']);
  });

  group('SosCall.payload', () {
    OutboxEntry entry(Json payload) => OutboxEntry(
      id: 'sos-1',
      kind: SosOutbox.kind,
      familyId: _familyId,
      payload: payload,
      createdAt: DateTime.utc(2026),
    );

    test('sin ubicación solo lleva familia y alerta', () {
      expect(SosCall.payload(entry(const {})), {
        'familyId': _familyId,
        'alertId': 'sos-1',
      });
    });

    test('la ubicación sigue el consentimiento VIGENTE', () {
      SharingConsent consentOf(SharingState state, LocationPrecision p) =>
          SharingConsent(
            familyId: _familyId,
            uid: 'ana',
            state: state,
            precision: p,
          );
      final point = entry(const {
        'lat': 4.61734,
        'lng': -74.07291,
        'accuracyM': 8,
      });
      expect(
        SosCall.payload(
          point,
          consent: consentOf(
            SharingState.sharing,
            LocationPrecision.approximate,
          ),
        ),
        containsPair('lat', 4.62),
      );
      expect(
        SosCall.payload(
          point,
          consent: consentOf(
            SharingState.sharing,
            LocationPrecision.approximate,
          ),
        )['accuracyM'],
        1000.0,
      );
      expect(
        SosCall.payload(
          point,
          consent: consentOf(SharingState.paused, LocationPrecision.exact),
        ),
        {'familyId': _familyId, 'alertId': 'sos-1'},
      );
    });

    test('la ubicación viaja completa y la precisión solo con ella', () {
      expect(
        SosCall.payload(
          entry(const {'lat': 4.6, 'lng': -74.1, 'accuracyM': 8}),
        ),
        {
          'familyId': _familyId,
          'alertId': 'sos-1',
          'lat': 4.6,
          'lng': -74.1,
          'accuracyM': 8.0,
        },
      );
      expect(SosCall.payload(entry(const {'lat': 4.6, 'accuracyM': 8})), {
        'familyId': _familyId,
        'alertId': 'sos-1',
      });
      expect(SosCall.payload(entry(const {'lat': 91.0, 'lng': 0.0})), {
        'familyId': _familyId,
        'alertId': 'sos-1',
      });
    });

    test('el handler propaga el fallo del servidor', () async {
      final handler = SosOutboxHandler(
        _FailingFunctions(),
        cache: cache,
        currentUid: () => uid,
      );
      final result = await handler.send(entry(const {}));
      expect(
        result.failureOrNull,
        const Failure.unavailable(SosCodes.notificationUnavailable),
      );
    });
  });
}

final class _FailingFunctions implements FunctionsClient {
  @override
  Future<Result<Json>> call(String name, Json payload) async =>
      const Err(Failure.unavailable(SosCodes.notificationUnavailable));
}
