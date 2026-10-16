import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/location_sharing/data/location_repository_impl.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/domain/location_use_cases.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';
import 'package:nexo_familia/infrastructure/database/drift_stores.dart';
import 'package:nexo_familia/infrastructure/demo/demo_functions.dart';
import 'package:nexo_familia/infrastructure/demo/in_memory_remote_store.dart';
import 'package:nexo_familia/infrastructure/location/demo_location_service.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/remote_mirror.dart';

import '../../../helpers/fakes.dart';

/// Registra los lotes que se envían al almacén (para comprobar que pausar
/// es una sola operación atómica).
final class _RecordingStore implements RemoteStore {
  new(this._inner);

  final InMemoryRemoteStore _inner;
  final List<List<RemoteWrite>> commits = [];

  @override
  Future<VoidResult> commit(List<RemoteWrite> writes) {
    commits.add(List.unmodifiable(writes));
    return _inner.commit(writes);
  }

  @override
  Future<Result<RemoteDoc?>> getDoc(String path) => _inner.getDoc(path);

  @override
  Stream<List<RemoteDoc>> watchCollection(String path, {RemoteQuery? query}) =>
      _inner.watchCollection(path, query: query);

  @override
  Stream<RemoteDoc?> watchDoc(String path) => _inner.watchDoc(path);
}

/// Integración: repositorio + almacén y funciones de demostración + espejo
/// + caché Drift en memoria.
void main() {
  late FakeClock clock;
  late InMemoryRemoteStore store;
  late _RecordingStore remote;
  late DemoFunctionsClient functions;
  late AppDatabase db;
  late DriftDocumentCache cache;
  late RemoteMirror mirror;
  late String familyId;
  String? uid;

  LocationRepositoryImpl repo() => LocationRepositoryImpl(
    remote: remote,
    cache: cache,
    currentUid: () => uid,
  );

  SharingConsent consent(
    SharingState state, [
    LocationPrecision precision = LocationPrecision.exact,
  ]) => SharingConsent(
    familyId: familyId,
    uid: uid!,
    state: state,
    precision: precision,
  );

  MemberLocation location({
    double lat = 4.61234,
    double lng = -74.07891,
    double accuracy = 12,
    bool approximate = false,
  }) => MemberLocation(
    uid: uid!,
    point: GeoPoint(lat, lng),
    accuracyMeters: accuracy,
    capturedAt: clock.now().subtract(const Duration(seconds: 5)),
    isApproximate: approximate,
  );

  Future<String> createFamilyAs(String owner) async {
    uid = owner;
    final created = await functions.call('createFamily', {'name': 'Familia'});
    return created.valueOrNull!['familyId']! as String;
  }

  Future<void> join(String member) async {
    final owner = uid;
    final invitation = await functions.call('createInvitation', {
      'familyId': familyId,
    });
    uid = member;
    final joined = await functions.call('acceptInvitation', {
      'code': invitation.valueOrNull!['code'],
    });
    expect(joined.isOk, isTrue);
    uid = owner;
  }

  setUp(() async {
    clock = FakeClock();
    store = InMemoryRemoteStore(clock: clock);
    remote = _RecordingStore(store);
    functions = DemoFunctionsClient(
      store: store,
      currentUid: () => uid,
      clock: clock,
      random: math.Random(3),
    );
    db = AppDatabase(NativeDatabase.memory());
    cache = DriftDocumentCache(db);
    mirror = RemoteMirror(
      remote: store,
      cache: cache,
      clock: clock,
      logger: SafeLogger(sink: MemoryLogSink(), clock: clock),
    );
    store
      ..serverWrite('users/ana', {'displayName': 'Ana'})
      ..serverWrite('users/luis', {'displayName': 'Luis'});
    familyId = await createFamilyAs('ana');
    mirror.start(familyId, [
      MirrorSpec(BackendPaths.consents(familyId)),
      MirrorSpec(BackendPaths.locations(familyId)),
    ]);
  });

  tearDown(() async {
    await mirror.dispose();
    await db.close();
  });

  test('el consentimiento inicial de quien crea la familia es '
      '"sin configurar"', () async {
    final mine = await repo().watchMyConsent(familyId).first;
    expect(mine.state, SharingState.notConfigured);
    expect(mine.isSharing, isFalse);
    expect(mine.uid, 'ana');
  });

  test(
    'sin documento de consentimiento emite el inicial (no comparte)',
    () async {
      await mirror.stop(familyId);
      uid = 'ana';
      final mine = await repo().watchMyConsent('familia-sin-datos').first;
      expect(mine.state, SharingState.notConfigured);
      expect(mine.familyId, 'familia-sin-datos');
      expect(mine.updatedAt, isNull);
    },
  );

  test('solo emite el consentimiento propio', () async {
    await join('luis');
    uid = 'luis';
    expect(
      (await repo().updateConsent(consent(SharingState.sharing))).isOk,
      isTrue,
    );

    await cache
        .watchDoc(BackendPaths.consents(familyId), 'luis')
        .firstWhere((d) => d?.data['state'] == 'sharing');

    uid = 'ana';
    final mine = await repo().watchMyConsent(familyId).first;
    expect(mine.uid, 'ana');
    expect(mine.state, SharingState.notConfigured);
  });

  test(
    'activar, publicar y ver la ubicación con la hora del servidor',
    () async {
      final repository = repo();
      expect(
        (await repository.updateConsent(consent(SharingState.sharing))).isOk,
        isTrue,
      );
      final active = await repository
          .watchMyConsent(familyId)
          .firstWhere((c) => c.isSharing);
      expect(active.precision, LocationPrecision.exact);
      expect(active.updatedAt, clock.now());

      expect(
        (await repository.publishMyLocation(familyId, location())).isOk,
        isTrue,
      );
      final remoteDoc = store.serverRead(
        BackendPaths.location(familyId, 'ana'),
      )!;
      expect(remoteDoc['receivedAt'], clock.now());
      expect(remoteDoc['approximate'], isFalse);

      final locations = await repository
          .watchFamilyLocations(familyId)
          .firstWhere((l) => l.isNotEmpty);
      final mine = locations.single;
      expect(mine.uid, 'ana');
      expect(mine.point, GeoPoint(4.61234, -74.07891));
      expect(mine.accuracyMeters, 12);
      expect(mine.receivedAt, clock.now());
      expect(mine.isApproximate, isFalse);
    },
  );

  test(
    'pausar borra la ubicación remota en el mismo lote (amenaza 5)',
    () async {
      final repository = repo();
      await repository.updateConsent(consent(SharingState.sharing));
      await repository.publishMyLocation(familyId, location());
      await repository
          .watchFamilyLocations(familyId)
          .firstWhere((l) => l.isNotEmpty);
      remote.commits.clear();

      final paused = await repository.updateConsent(
        consent(SharingState.paused),
      );

      expect(paused.isOk, isTrue);
      expect(store.serverRead(BackendPaths.location(familyId, 'ana')), isNull);
      expect(
        store.serverRead(BackendPaths.consent(familyId, 'ana'))?['state'],
        'paused',
      );
      // Una sola operación con las dos escrituras: o se aplican ambas o
      // ninguna.
      expect(remote.commits, hasLength(1));
      expect(remote.commits.single.map((w) => (w.op, w.path)), [
        (RemoteOp.merge, BackendPaths.consent(familyId, 'ana')),
        (RemoteOp.remove, BackendPaths.location(familyId, 'ana')),
      ]);
      expect(
        await repository
            .watchFamilyLocations(familyId)
            .firstWhere((l) => l.isEmpty),
        isEmpty,
      );
    },
  );

  test('volver a "sin configurar" también borra la ubicación', () async {
    final repository = repo();
    await repository.updateConsent(consent(SharingState.sharing));
    await repository.publishMyLocation(familyId, location());
    await repository.updateConsent(consent(SharingState.notConfigured));
    expect(store.serverRead(BackendPaths.location(familyId, 'ana')), isNull);
  });

  test('activar en exacta no toca la ubicación; en aproximada la borra '
      '(pudo quedar una exacta publicada)', () async {
    final repository = repo();
    await repository.updateConsent(consent(SharingState.sharing));
    expect(remote.commits.last.map((w) => w.op), [RemoteOp.merge]);
    await repository.updateConsent(
      consent(SharingState.sharing, LocationPrecision.approximate),
    );
    expect(remote.commits.last.map((w) => w.op), [
      RemoteOp.merge,
      RemoteOp.remove,
    ]);
    final saved = store.serverRead(BackendPaths.consent(familyId, 'ana'))!;
    expect(saved['state'], 'sharing');
    expect(saved['precision'], 'approximate');
    expect(saved['updatedAt'], clock.now());
  });

  test(
    'pasar a aproximada borra la última ubicación exacta ya enviada',
    () async {
      final repository = repo();
      await repository.updateConsent(consent(SharingState.sharing));
      await repository.publishMyLocation(familyId, location());
      // Espera a que el espejo la refleje en la copia local.
      await cache
          .watchDoc(BackendPaths.locations(familyId), 'ana')
          .firstWhere((doc) => doc != null);

      final result = await repository.updateConsent(
        consent(SharingState.sharing, LocationPrecision.approximate),
      );
      expect(result.isOk, isTrue);
      expect(store.serverRead(BackendPaths.location(familyId, 'ana')), isNull);
      final saved = store.serverRead(BackendPaths.consent(familyId, 'ana'))!;
      expect(saved['precision'], 'approximate');
    },
  );

  test('publicar aplica el consentimiento VIGENTE de la copia local', () async {
    final repository = repo();
    // Sin espejo: la copia local es la que fija la prueba.
    await mirror.stop(familyId);
    Future<void> cachedConsent(String state, String precision) => cache.upsert(
      BackendPaths.consents(familyId),
      familyId,
      RemoteDoc('ana', {'state': state, 'precision': precision}),
      clock.now(),
    );
    // La pantalla preparó un envío exacto, pero ya eligió "aproximada".
    await cachedConsent('sharing', 'approximate');
    await repository.publishMyLocation(
      familyId,
      location(lat: 4.61734, lng: -74.07291),
    );
    final saved = store.serverRead(BackendPaths.location(familyId, 'ana'))!;
    expect(saved['lat'], 4.62);
    expect(saved['approximate'], isTrue);
    expect(saved['accuracyM'], 1000);

    // Pausó mientras se obtenía la posición: no se publica.
    await cachedConsent('paused', 'exact');
    final result = await repository.publishMyLocation(familyId, location());
    expect(result.failureOrNull?.code, 'not-sharing');
  });

  test('una ubicación aproximada nunca sale con más detalle', () async {
    final repository = repo();
    await repository.updateConsent(
      consent(SharingState.sharing, LocationPrecision.approximate),
    );
    // Aunque llegara sin redondear (error de quien llama), se redondea.
    await repository.publishMyLocation(
      familyId,
      location(lat: 4.61734, lng: -74.07291, accuracy: 8, approximate: true),
    );
    final saved = store.serverRead(BackendPaths.location(familyId, 'ana'))!;
    expect(saved['lat'], 4.62);
    expect(saved['lng'], -74.07);
    expect(saved['accuracyM'], 1000);
    expect(saved['approximate'], isTrue);
  });

  test('la precisión se ajusta al rango que aceptan las reglas', () async {
    final repository = repo();
    await repository.updateConsent(consent(SharingState.sharing));
    await repository.publishMyLocation(familyId, location(accuracy: 250000));
    expect(
      store.serverRead(BackendPaths.location(familyId, 'ana'))!['accuracyM'],
      99999,
    );
  });

  test('las ubicaciones inválidas en la caché se ignoran', () async {
    final valid = clock.now();
    store
      ..serverWrite(BackendPaths.location(familyId, 'fuera-de-rango'), {
        'lat': 91.0,
        'lng': 10.0,
        'accuracyM': 5.0,
        'capturedAt': valid,
      })
      ..serverWrite(BackendPaths.location(familyId, 'texto'), {
        'lat': '4.6',
        'lng': '-74.1',
        'accuracyM': 5.0,
        'capturedAt': valid,
      })
      ..serverWrite(BackendPaths.location(familyId, 'sin-hora'), {
        'lat': 4.6,
        'lng': -74.1,
        'accuracyM': 5.0,
      })
      ..serverWrite(BackendPaths.location(familyId, 'sin-precision'), {
        'lat': 4.6,
        'lng': -74.1,
        'capturedAt': valid,
      })
      ..serverWrite(BackendPaths.location(familyId, 'precision-negativa'), {
        'lat': 4.6,
        'lng': -74.1,
        'accuracyM': -3.0,
        'capturedAt': valid,
      })
      ..serverWrite(BackendPaths.location(familyId, 'luis'), {
        // Enteros y milisegundos: se convierten de forma tolerante.
        'lat': 4,
        'lng': -74,
        'accuracyM': 30,
        'capturedAt': valid.millisecondsSinceEpoch,
        'receivedAt': valid,
        'approximate': true,
      });

    uid = 'ana';
    final locations = await repo()
        .watchFamilyLocations(familyId)
        .firstWhere((l) => l.isNotEmpty);
    expect(locations.map((l) => l.uid), ['luis']);
    final luis = locations.single;
    expect(luis.point, GeoPoint(4, -74));
    expect(luis.capturedAt, valid);
    expect(luis.isApproximate, isTrue);
  });

  test('un consentimiento con valores desconocidos no comparte y usa la '
      'precisión que menos revela', () async {
    store.serverWrite(BackendPaths.consent(familyId, 'ana'), {
      'state': 'algo-raro',
      'precision': 'super-exacta',
    });
    uid = 'ana';
    final mine = await repo()
        .watchMyConsent(familyId)
        .firstWhere((c) => c.precision == LocationPrecision.approximate);
    expect(mine.state, SharingState.notConfigured);
  });

  test(
    'nadie cambia el consentimiento ni la ubicación de otra persona',
    () async {
      await join('luis');
      uid = 'ana';
      final repository = repo();
      final otherConsent = SharingConsent(
        familyId: familyId,
        uid: 'luis',
        state: SharingState.sharing,
        precision: LocationPrecision.exact,
      );
      expect(
        (await repository.updateConsent(otherConsent)).failureOrNull?.kind,
        FailureKind.permissionDenied,
      );
      final otherLocation = MemberLocation(
        uid: 'luis',
        point: GeoPoint(4.6, -74.1),
        accuracyMeters: 10,
        capturedAt: clock.now(),
        isApproximate: false,
      );
      expect(
        (await repository.publishMyLocation(
          familyId,
          otherLocation,
        )).failureOrNull?.kind,
        FailureKind.permissionDenied,
      );
      expect(remote.commits, isEmpty);
    },
  );

  test('sin sesión no lee ni escribe', () async {
    uid = null;
    final repository = repo();
    await expectLater(
      repository.watchMyConsent(familyId),
      emitsError(const Failure.unauthenticated()),
    );
    uid = 'ana';
    final mine = location();
    uid = null;
    expect(
      (await repository.publishMyLocation(familyId, mine)).failureOrNull,
      const Failure.unauthenticated(),
    );
    expect(remote.commits, isEmpty);
  });

  test('sin conexión devuelve el fallo y no cambia nada', () async {
    final repository = repo();
    store.simulatedFailure = const Failure.network();
    final result = await repository.updateConsent(
      consent(SharingState.sharing),
    );
    expect(result.failureOrNull?.kind, FailureKind.network);
    store.simulatedFailure = null;
    expect(
      store.serverRead(BackendPaths.consent(familyId, 'ana'))?['state'],
      'notConfigured',
    );
  });

  test(
    'ShareMyLocationNow publica una ubicación sintética de demostración',
    () async {
      final repository = repo();
      await repository.updateConsent(consent(SharingState.sharing));
      final device = DemoLocationService(
        clock: clock,
        simulatedPermission: DeviceLocationPermission.whileInUse,
      );
      final shared = await ShareMyLocationNow(repository, device)(
        familyId: familyId,
        uid: 'ana',
        consent: await repository
            .watchMyConsent(familyId)
            .firstWhere((c) => c.isSharing),
      );
      expect(shared.isOk, isTrue);
      final locations = await repository
          .watchFamilyLocations(familyId)
          .firstWhere((l) => l.isNotEmpty);
      expect(locations.single.uid, 'ana');
      expect(
        locations.single.point.distanceTo(DemoLocationService.defaultOrigin),
        lessThan(50),
      );
    },
  );
}
