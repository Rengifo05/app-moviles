import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/geofences/data/geofence_repository_impl.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';
import 'package:nexo_familia/infrastructure/database/drift_stores.dart';
import 'package:nexo_familia/infrastructure/demo/demo_functions.dart';
import 'package:nexo_familia/infrastructure/demo/in_memory_remote_store.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/remote_mirror.dart';

import '../../../helpers/fakes.dart';

const _familyId = 'fam-1';

/// Centro sintético en el océano Atlántico sur (no es el lugar de nadie).
final GeoPoint _center = GeoPoint(-40, -30);

/// Almacén que delega en el de demostración pero puede simular lo que el
/// de memoria no aplica: el rechazo de las reglas o una escritura que el
/// servidor aplicó sin que llegara la confirmación.
final class _ScriptedStore implements RemoteStore {
  new(this._inner);

  final InMemoryRemoteStore _inner;

  /// Si no es nulo, todo `commit` falla con este fallo sin escribir.
  Failure? rejectCommits;

  /// Si no es nulo, `commit` escribe pero responde con este fallo (se cortó
  /// la conexión después de que el servidor lo aplicara).
  Failure? failAfterApplying;

  final List<List<RemoteWrite>> commits = [];

  @override
  Future<VoidResult> commit(List<RemoteWrite> writes) async {
    commits.add(writes);
    if (rejectCommits case final failure?) return Err(failure);
    final written = await _inner.commit(writes);
    if (failAfterApplying case final failure?) return Err(failure);
    return written;
  }

  @override
  Future<Result<RemoteDoc?>> getDoc(String path) => _inner.getDoc(path);

  @override
  Stream<List<RemoteDoc>> watchCollection(String path, {RemoteQuery? query}) =>
      _inner.watchCollection(path, query: query);

  @override
  Stream<RemoteDoc?> watchDoc(String path) => _inner.watchDoc(path);
}

/// Functions de demostración sobre el mismo almacén, con los mismos
/// fallos simulables que [_ScriptedStore].
final class _ScriptedFunctions implements FunctionsClient {
  new(this._inner);

  final DemoFunctionsClient _inner;
  Failure? rejectCalls;
  Failure? failAfterApplying;
  final List<(String, Json)> calls = [];

  @override
  Future<Result<Json>> call(String name, Json payload) async {
    calls.add((name, payload));
    if (rejectCalls case final failure?) return Err(failure);
    final result = await _inner.call(name, payload);
    if (failAfterApplying case final failure?) return Err(failure);
    return result;
  }
}

/// Integración: repositorio + almacén de demostración + espejo + caché de
/// Drift en memoria.
void main() {
  late FakeClock clock;
  late InMemoryRemoteStore store;
  late _ScriptedStore remote;
  late _ScriptedFunctions functions;
  late AppDatabase db;
  late DriftDocumentCache cache;
  late RemoteMirror mirror;
  late SequentialIdGenerator ids;
  String? uid;

  GeofenceRepositoryImpl repoFor() => GeofenceRepositoryImpl(
    remote: remote,
    functions: functions,
    cache: cache,
    currentUid: () => uid,
    clock: clock,
    ids: ids,
  );

  void mirrorFamily() =>
      mirror.start(_familyId, [MirrorSpec(BackendPaths.geofences(_familyId))]);

  Future<List<Geofence>> zonesWhere(
    GeofenceRepositoryImpl repo,
    bool Function(List<Geofence>) test,
  ) => repo
      .watchGeofences(_familyId)
      .firstWhere(test)
      .timeout(const Duration(seconds: 5));

  void seedZone(String id, {String name = 'Zona', int version = 1}) =>
      store.serverWrite(BackendPaths.geofence(_familyId, id), {
        'name': name,
        'lat': -40.0,
        'lng': -30.0,
        'radiusM': 200,
        'createdBy': 'ana',
        'version': version,
        'updatedAt': serverTimestamp,
      });

  setUp(() {
    clock = FakeClock();
    store = InMemoryRemoteStore(clock: clock);
    remote = _ScriptedStore(store);
    functions = _ScriptedFunctions(
      DemoFunctionsClient(store: store, currentUid: () => uid),
    );
    // Ana gestiona la familia (la Function lo exige para crear zonas).
    store.serverWrite(BackendPaths.member(_familyId, 'ana'), {
      'uid': 'ana',
      'role': 'owner',
    });
    db = AppDatabase(NativeDatabase.memory());
    cache = DriftDocumentCache(db);
    ids = SequentialIdGenerator();
    mirror = RemoteMirror(
      remote: store,
      cache: cache,
      clock: clock,
      logger: SafeLogger(sink: MemoryLogSink(), clock: clock),
    );
    uid = 'ana';
  });

  tearDown(() async {
    await mirror.dispose();
    await db.close();
    await store.dispose();
  });

  group('create', () {
    test('escribe el contrato y la zona llega vía el espejo', () async {
      final repo = repoFor();
      mirrorFamily();
      final created = await repo.create(
        familyId: _familyId,
        name: '  Casa  ',
        center: _center,
        radiusMeters: 250,
      );

      final zone = created.valueOrNull!;
      expect(zone.id, 'id-1');
      expect(zone.name, 'Casa');
      expect(zone.version, 1);
      expect(zone.createdBy, 'ana');

      expect(store.serverRead(BackendPaths.geofence(_familyId, 'id-1')), {
        'name': 'Casa',
        'lat': -40.0,
        'lng': -30.0,
        'radiusM': 250.0,
        'createdBy': 'ana',
        'version': 1,
        'updatedAt': clock.now(),
      });

      final zones = await zonesWhere(repo, (z) => z.isNotEmpty);
      final listed = zones.single;
      expect(listed.id, 'id-1');
      expect(listed.familyId, _familyId);
      expect(listed.name, 'Casa');
      expect(listed.center, _center);
      expect(listed.radiusMeters, 250);
      expect(listed.version, 1);
      expect(listed.createdBy, 'ana');
      expect(listed.updatedAt, clock.now());
    });

    test('valida nombre y radio antes de escribir', () async {
      final repo = repoFor();
      Future<Failure?> attempt(String name, double radius) async =>
          (await repo.create(
            familyId: _familyId,
            name: name,
            center: _center,
            radiusMeters: radius,
          )).failureOrNull;

      expect(
        await attempt('   ', 200),
        const Failure.validation('geofence-name-required'),
      );
      expect(
        await attempt('x' * 41, 200),
        const Failure.validation('geofence-name-too-long'),
      );
      expect(
        await attempt('Casa', 99),
        const Failure.validation('geofence-radius-out-of-range'),
      );
      expect(
        await attempt('Casa', 2001),
        const Failure.validation('geofence-radius-out-of-range'),
      );
      // El nombre se mide ya recortado (las reglas miden el texto tal cual).
      expect(await attempt('  ${'x' * 40}  ', 200), isNull);
      expect(functions.calls, hasLength(1));
    });

    test('respeta el límite de zonas por familia según la caché', () async {
      for (var i = 0; i < GeofenceRules.maxPerFamily; i++) {
        seedZone('z$i', name: 'Zona $i');
      }
      final repo = repoFor();
      mirrorFamily();
      await zonesWhere(repo, (z) => z.length == GeofenceRules.maxPerFamily);

      final result = await repo.create(
        familyId: _familyId,
        name: 'Una más',
        center: _center,
        radiusMeters: 200,
      );
      expect(
        result.failureOrNull,
        const Failure.validation(GeofenceFailureCodes.limit),
      );
      expect(functions.calls, isEmpty);
    });

    test('el servidor aplica el límite aunque la caché no lo sepa', () async {
      for (var i = 0; i < GeofenceRules.maxPerFamily; i++) {
        seedZone('z$i', name: 'Zona $i');
      }
      // Sin espejo: la caché no tiene ninguna zona.
      final result = await repoFor().create(
        familyId: _familyId,
        name: 'Una más',
        center: _center,
        radiusMeters: 200,
      );
      expect(
        result.failureOrNull,
        const Failure.validation(GeofenceFailureCodes.limit),
      );
      expect(functions.calls, hasLength(1));
    });

    test('sin sesión no se crea', () async {
      uid = null;
      final result = await repoFor().create(
        familyId: _familyId,
        name: 'Casa',
        center: _center,
        radiusMeters: 200,
      );
      expect(result.failureOrNull?.kind, FailureKind.unauthenticated);
      expect(functions.calls, isEmpty);
    });

    test('devuelve el rechazo del servidor (sin rol de gestión)', () async {
      functions.rejectCalls = const Failure.permissionDenied();
      final result = await repoFor().create(
        familyId: _familyId,
        name: 'Casa',
        center: _center,
        radiusMeters: 200,
      );
      expect(result.failureOrNull, const Failure.permissionDenied());
    });

    test(
      'crea con la Function createGeofence, nunca escribiendo directo',
      () async {
        await repoFor().create(
          familyId: _familyId,
          name: 'Casa',
          center: _center,
          radiusMeters: 200,
        );
        expect(remote.commits, isEmpty);
        final (name, payload) = functions.calls.single;
        expect(name, 'createGeofence');
        expect(payload, {
          'familyId': _familyId,
          'geofenceId': 'id-1',
          'name': 'Casa',
          'lat': -40.0,
          'lng': -30.0,
          'radiusM': 200.0,
        });
      },
    );

    test('sin conexión falla rápido como transitorio y no escribe', () async {
      store.simulatedFailure = const Failure.unavailable();
      final result = await repoFor().create(
        familyId: _familyId,
        name: 'Casa',
        center: _center,
        radiusMeters: 200,
      );
      expect(result.failureOrNull?.isTransient, isTrue);
      store.simulatedFailure = null;
      expect(
        store.serverRead(BackendPaths.geofence(_familyId, 'id-1')),
        isNull,
      );
    });

    test(
      'reintentar lo mismo tras un fallo sin confirmar no duplica la zona',
      () async {
        final repo = repoFor();
        mirrorFamily();
        functions.failAfterApplying = const Failure.network();
        final first = await repo.create(
          familyId: _familyId,
          name: 'Casa',
          center: _center,
          radiusMeters: 200,
        );
        expect(first.failureOrNull, const Failure.network());
        // El servidor sí la guardó.
        await zonesWhere(repo, (z) => z.length == 1);

        functions.failAfterApplying = null;
        final retry = await repo.create(
          familyId: _familyId,
          name: ' Casa ',
          center: _center,
          radiusMeters: 200,
        );
        expect(retry.valueOrNull?.id, 'id-1');
        expect(functions.calls.map((c) => c.$2['geofenceId']).toSet(), {
          'id-1',
        });
        final zones = await zonesWhere(repo, (z) => z.isNotEmpty);
        expect(zones.single.id, 'id-1');

        // Un intento distinto ya es otra zona.
        final other = await repo.create(
          familyId: _familyId,
          name: 'Colegio',
          center: _center,
          radiusMeters: 200,
        );
        expect(other.valueOrNull?.id, 'id-2');
      },
    );

    test(
      'el reintento no choca con el límite por la zona que ya llegó',
      () async {
        for (var i = 0; i < GeofenceRules.maxPerFamily - 1; i++) {
          seedZone('z$i', name: 'Zona $i');
        }
        final repo = repoFor();
        mirrorFamily();
        await zonesWhere(
          repo,
          (z) => z.length == GeofenceRules.maxPerFamily - 1,
        );
        functions.failAfterApplying = const Failure.unavailable('timeout');
        await repo.create(
          familyId: _familyId,
          name: 'Casa',
          center: _center,
          radiusMeters: 200,
        );
        await zonesWhere(repo, (z) => z.length == GeofenceRules.maxPerFamily);

        functions.failAfterApplying = null;
        final retry = await repo.create(
          familyId: _familyId,
          name: 'Casa',
          center: _center,
          radiusMeters: 200,
        );
        expect(retry.isOk, isTrue);
        final another = await repo.create(
          familyId: _familyId,
          name: 'Parque',
          center: _center,
          radiusMeters: 200,
        );
        expect(
          another.failureOrNull,
          const Failure.validation(GeofenceFailureCodes.limit),
        );
      },
    );
  });

  group('update', () {
    Future<Geofence> createZone(GeofenceRepositoryImpl repo) async {
      final created = await repo.create(
        familyId: _familyId,
        name: 'Casa',
        center: _center,
        radiusMeters: 200,
      );
      return created.valueOrNull!;
    }

    test(
      'incrementa la versión y conserva el autor original aunque edite otro',
      () async {
        final repo = repoFor();
        mirrorFamily();
        final zone = await createZone(repo);
        await zonesWhere(repo, (z) => z.isNotEmpty);

        clock.advance(const Duration(minutes: 5));
        uid = 'marta';
        final updated = await repo.update(
          Geofence(
            id: zone.id,
            familyId: _familyId,
            name: ' Casa de la abuela ',
            center: GeoPoint(-40.001, -30.002),
            radiusMeters: 500,
            createdBy: 'marta',
            version: 1,
            updatedAt: zone.updatedAt,
          ),
        );

        expect(updated.valueOrNull?.version, 2);
        expect(updated.valueOrNull?.createdBy, 'ana');
        expect(updated.valueOrNull?.name, 'Casa de la abuela');
        expect(store.serverRead(BackendPaths.geofence(_familyId, zone.id)), {
          'name': 'Casa de la abuela',
          'lat': -40.001,
          'lng': -30.002,
          'radiusM': 500.0,
          'createdBy': 'ana',
          'version': 2,
          'updatedAt': clock.now(),
        });
        final zones = await zonesWhere(repo, (z) => z.single.version == 2);
        expect(zones.single.radiusMeters, 500);
      },
    );

    test('con una versión anterior a la de la caché → conflicto', () async {
      final repo = repoFor();
      mirrorFamily();
      final zone = await createZone(repo);
      await zonesWhere(repo, (z) => z.isNotEmpty);

      // Otro integrante la cambia primero.
      uid = 'marta';
      final theirs = await repo.update(
        Geofence(
          id: zone.id,
          familyId: _familyId,
          name: 'Casa (nueva)',
          center: _center,
          radiusMeters: 300,
          createdBy: zone.createdBy,
          version: 1,
          updatedAt: zone.updatedAt,
        ),
      );
      expect(theirs.isOk, isTrue);
      await zonesWhere(repo, (z) => z.single.version == 2);

      uid = 'ana';
      remote.commits.clear();
      final mine = await repo.update(
        Geofence(
          id: zone.id,
          familyId: _familyId,
          name: 'Casa (mía)',
          center: _center,
          radiusMeters: 800,
          createdBy: zone.createdBy,
          version: 1,
          updatedAt: zone.updatedAt,
        ),
      );
      expect(
        mine.failureOrNull,
        const Failure.conflict(GeofenceFailureCodes.conflict),
      );
      expect(remote.commits, isEmpty);
      expect(
        store.serverRead(BackendPaths.geofence(_familyId, zone.id))!['name'],
        'Casa (nueva)',
      );
    });

    test('una zona que ya no está en la caché → no encontrada', () async {
      final result = await repoFor().update(
        Geofence(
          id: 'nope',
          familyId: _familyId,
          name: 'Casa',
          center: _center,
          radiusMeters: 200,
          createdBy: 'ana',
          version: 1,
          updatedAt: clock.now(),
        ),
      );
      expect(
        result.failureOrNull,
        const Failure.notFound(GeofenceFailureCodes.notFound),
      );
    });

    test('valida antes de escribir', () async {
      final result = await repoFor().update(
        Geofence(
          id: 'z',
          familyId: _familyId,
          name: '',
          center: _center,
          radiusMeters: 200,
          createdBy: 'ana',
          version: 1,
          updatedAt: clock.now(),
        ),
      );
      expect(
        result.failureOrNull,
        const Failure.validation('geofence-name-required'),
      );
      expect(remote.commits, isEmpty);
    });

    test(
      'reintentar un cambio que sí llegó al servidor lo da por guardado',
      () async {
        final repo = repoFor();
        mirrorFamily();
        final zone = await createZone(repo);
        await zonesWhere(repo, (z) => z.isNotEmpty);
        final edit = Geofence(
          id: zone.id,
          familyId: _familyId,
          name: 'Casa grande',
          center: _center,
          radiusMeters: 600,
          createdBy: zone.createdBy,
          version: 1,
          updatedAt: zone.updatedAt,
        );

        remote.failAfterApplying = const Failure.network();
        expect(
          (await repo.update(edit)).failureOrNull,
          const Failure.network(),
        );
        await zonesWhere(repo, (z) => z.single.version == 2);

        remote
          ..failAfterApplying = null
          ..commits.clear();
        final retry = await repo.update(edit);
        expect(retry.valueOrNull?.version, 2);
        expect(remote.commits, isEmpty);
        expect(
          store.serverRead(
            BackendPaths.geofence(_familyId, zone.id),
          )!['version'],
          2,
        );
      },
    );

    group('si las reglas la rechazan con la caché desactualizada', () {
      late GeofenceRepositoryImpl repo;
      late Geofence zone;

      setUp(() async {
        repo = repoFor();
        mirrorFamily();
        zone = await createZone(repo);
        await zonesWhere(repo, (z) => z.isNotEmpty);
        // Sin escucha (p. ej. sin conexión) la caché no se entera de lo que
        // pase en el servidor.
        await mirror.stop(_familyId);
        remote.rejectCommits = const Failure.permissionDenied();
      });

      Geofence edit() => Geofence(
        id: zone.id,
        familyId: _familyId,
        name: 'Casa',
        center: _center,
        radiusMeters: 900,
        createdBy: zone.createdBy,
        version: zone.version,
        updatedAt: zone.updatedAt,
      );

      test('otra versión en el servidor → conflicto', () async {
        seedZone(zone.id, name: 'Casa', version: 2);
        expect(
          (await repo.update(edit())).failureOrNull,
          const Failure.conflict(GeofenceFailureCodes.conflict),
        );
      });

      test('ya no existe en el servidor → no encontrada', () async {
        store.serverDelete(BackendPaths.geofence(_familyId, zone.id));
        expect(
          (await repo.update(edit())).failureOrNull,
          const Failure.notFound(GeofenceFailureCodes.notFound),
        );
      });

      test('el servidor ya tiene este mismo cambio → guardado', () async {
        store.serverWrite(BackendPaths.geofence(_familyId, zone.id), {
          'name': 'Casa',
          'lat': -40.0,
          'lng': -30.0,
          'radiusM': 900.0,
          'createdBy': 'ana',
          'version': 2,
          'updatedAt': serverTimestamp,
        });
        expect((await repo.update(edit())).valueOrNull?.version, 2);
      });

      test(
        'contención de la transacción con otra versión → conflicto',
        () async {
          remote.rejectCommits = const Failure.conflict();
          seedZone(zone.id, name: 'Casa', version: 2);
          expect(
            (await repo.update(edit())).failureOrNull,
            const Failure.conflict(GeofenceFailureCodes.conflict),
          );
        },
      );

      test('misma versión → es un problema de permisos', () async {
        expect(
          (await repo.update(edit())).failureOrNull,
          const Failure.permissionDenied(),
        );
      });
    });
  });

  group('delete y lectura', () {
    test('eliminar la quita de la lista', () async {
      final repo = repoFor();
      mirrorFamily();
      final zone = (await repo.create(
        familyId: _familyId,
        name: 'Casa',
        center: _center,
        radiusMeters: 200,
      )).valueOrNull!;
      await zonesWhere(repo, (z) => z.isNotEmpty);

      expect((await repo.delete(zone)).isOk, isTrue);
      expect(
        store.serverRead(BackendPaths.geofence(_familyId, zone.id)),
        isNull,
      );
      await zonesWhere(repo, (z) => z.isEmpty);
    });

    test(
      'ordena por nombre e ignora documentos que no cumplen el contrato',
      () async {
        seedZone('b', name: 'colegio');
        seedZone('a', name: 'Casa');
        seedZone('c', name: 'Abuela');
        store
          ..serverWrite(BackendPaths.geofence(_familyId, 'sin-version'), {
            'name': 'Rota',
            'lat': -40.0,
            'lng': -30.0,
            'radiusM': 200,
          })
          ..serverWrite(BackendPaths.geofence(_familyId, 'fuera-de-rango'), {
            'name': 'Rota',
            'lat': 91.0,
            'lng': -30.0,
            'radiusM': 200,
            'version': 1,
          });
        final repo = repoFor();
        mirrorFamily();
        final zones = await zonesWhere(repo, (z) => z.length >= 3);
        expect(zones.map((z) => z.name), ['Abuela', 'Casa', 'colegio']);
      },
    );

    test('sin hora del servidor todavía, usa la hora actual', () async {
      store.serverWrite(BackendPaths.geofence(_familyId, 'z'), {
        'name': 'Casa',
        'lat': -40.0,
        'lng': -30.0,
        'radiusM': 200,
        'version': 3,
      });
      final repo = repoFor();
      mirrorFamily();
      final zone = (await zonesWhere(repo, (z) => z.isNotEmpty)).single;
      expect(zone.updatedAt, clock.now());
      expect(zone.version, 3);
      expect(zone.createdBy, '');
    });
  });
}
