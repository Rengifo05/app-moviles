import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/features/activity/data/activity_repository_impl.dart';
import 'package:nexo_familia/features/activity/domain/activity.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/family/data/family_repository_impl.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';
import 'package:nexo_familia/infrastructure/database/drift_stores.dart';
import 'package:nexo_familia/infrastructure/demo/demo_functions.dart';
import 'package:nexo_familia/infrastructure/demo/in_memory_remote_store.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/remote_mirror.dart';

import '../../../helpers/fakes.dart';

/// Integración: eventos escritos en el backend de demostración (por las
/// Functions simuladas y como los escribe el cliente) → espejo → caché →
/// repositorio de actividad.
void main() {
  late FakeClock clock;
  late InMemoryRemoteStore store;
  late AppDatabase db;
  late DriftDocumentCache cache;
  late RemoteMirror mirror;
  late ActivityRepositoryImpl repo;
  String? uid;

  DemoFunctionsClient functions() => DemoFunctionsClient(
    store: store,
    currentUid: () => uid,
    clock: clock,
    random: math.Random(3),
  );

  FamilyRepositoryImpl familyRepo() => FamilyRepositoryImpl(
    functions: functions(),
    cache: cache,
    currentUid: () => uid,
  );

  /// Como en `familyMirrorSpecs` de la app.
  void mirrorEvents(String familyId) => mirror.start(familyId, [
    MirrorSpec(
      BackendPaths.events(familyId),
      query: const RemoteQuery(
        orderBy: 'createdAt',
        descending: true,
        limit: 100,
      ),
    ),
  ]);

  /// Evento de solo inserción escrito como lo hace el cliente.
  Future<void> clientEvent(String familyId, String id, Json data) async {
    final result = await store.commit([
      RemoteWrite.create(BackendPaths.event(familyId, id), {
        ...data,
        'createdAt': serverTimestamp,
        'clientCreatedAt': clock.now(),
        'expireAt': clock.now().add(const Duration(days: 30)),
      }),
    ]);
    expect(result.isOk, isTrue);
  }

  /// Familia de Ana con Luis como integrante (evento `joined` de Luis).
  Future<String> familyWithLuis() async {
    uid = 'ana';
    final ana = familyRepo();
    final familyId = (await ana.createFamily('Familia')).valueOrNull!.id;
    final code = (await ana.createInvitation(familyId)).valueOrNull!.code;
    clock.advance(const Duration(minutes: 1));
    uid = 'luis';
    expect((await familyRepo().acceptInvitation(code)).isOk, isTrue);
    return familyId;
  }

  setUp(() {
    clock = FakeClock();
    store = InMemoryRemoteStore(clock: clock);
    db = AppDatabase(NativeDatabase.memory());
    cache = DriftDocumentCache(db);
    mirror = RemoteMirror(
      remote: store,
      cache: cache,
      clock: clock,
      logger: SafeLogger(sink: MemoryLogSink(), clock: clock),
    );
    repo = ActivityRepositoryImpl(cache: cache, clock: clock);
    store
      ..serverWrite('users/ana', {'displayName': 'Ana'})
      ..serverWrite('users/luis', {'displayName': 'Luis'});
  });

  tearDown(() async {
    await mirror.dispose();
    await db.close();
  });

  test('convierte cada tipo de evento, los más recientes primero', () async {
    final familyId = await familyWithLuis();

    clock.advance(const Duration(minutes: 1));
    uid = 'ana';
    await clientEvent(familyId, 'c1', {
      'type': 'checkIn',
      'actorUid': 'ana',
      'kind': 'ok',
      'message': '  Llegué al colegio  ',
    });
    clock.advance(const Duration(minutes: 1));
    await clientEvent(familyId, 'g1', {
      'type': 'geofence',
      'actorUid': 'ana',
      'geofenceId': 'z1',
      'geofenceName': 'Casa',
      'transition': 'enter',
    });
    clock.advance(const Duration(minutes: 1));
    uid = 'luis';
    final sos = await functions().call(BackendFunctions.raiseSos, {
      'familyId': familyId,
      'alertId': 'sos-1',
    });
    expect(sos.isOk, isTrue);
    clock.advance(const Duration(minutes: 1));
    await clientEvent(familyId, 'c2', {
      'type': 'checkIn',
      'actorUid': 'luis',
      'kind': 'needHelp',
    });

    mirrorEvents(familyId);
    final items = await repo
        .watchActivity(familyId)
        .firstWhere((items) => items.length == 5);

    expect(items.map((i) => i.runtimeType), [
      CheckInActivity,
      SosActivity,
      GeofenceActivity,
      CheckInActivity,
      MembershipActivity,
    ]);
    final help = items[0] as CheckInActivity;
    expect(help.kind, CheckInKind.needHelp);
    expect(help.actorUid, 'luis');
    expect(help.message, isNull);

    final alert = items[1] as SosActivity;
    expect(alert.alertId, 'sos-1');
    expect(alert.resolved, isFalse);

    final zone = items[2] as GeofenceActivity;
    expect(zone.geofenceName, 'Casa');
    expect(zone.transition, GeofenceTransition.enter);

    final ok = items[3] as CheckInActivity;
    expect(ok.kind, CheckInKind.ok);
    expect(ok.message, 'Llegué al colegio');

    final joined = items[4] as MembershipActivity;
    expect(joined.change, MembershipChange.joined);
    expect(joined.actorUid, 'luis');
    expect(joined.targetUid, isNull);
    expect(items.every((i) => i.familyId == familyId), isTrue);
  });

  test('salir y expulsar generan eventos de membresía', () async {
    final familyId = await familyWithLuis();
    store.serverWrite('users/marta', {'displayName': 'Marta'});
    uid = 'ana';
    final code = (await familyRepo().createInvitation(familyId))
        .valueOrNull!
        .code;
    uid = 'marta';
    expect((await familyRepo().acceptInvitation(code)).isOk, isTrue);

    clock.advance(const Duration(minutes: 1));
    uid = 'luis';
    expect((await familyRepo().leaveFamily(familyId)).isOk, isTrue);
    clock.advance(const Duration(minutes: 1));
    uid = 'ana';
    expect((await familyRepo().removeMember(familyId, 'marta')).isOk, isTrue);

    mirrorEvents(familyId);
    final items = await repo
        .watchActivity(familyId)
        .firstWhere((items) => items.length == 4);
    final changes = items.cast<MembershipActivity>();
    expect(changes.first.change, MembershipChange.removed);
    expect(changes.first.actorUid, 'ana');
    expect(changes.first.targetUid, 'marta');
    expect(changes.elementAt(1).change, MembershipChange.left);
    expect(changes.elementAt(1).actorUid, 'luis');
  });

  test(
    'ignora tipos desconocidos, documentos mal formados y vencidos',
    () async {
      const familyId = 'f1';
      final events = BackendPaths.events(familyId);
      final valid = {
        'type': 'checkIn',
        'actorUid': 'ana',
        'kind': 'ok',
        'createdAt': serverTimestamp,
        'expireAt': clock.now().add(const Duration(days: 30)),
      };
      store
        ..serverWrite('$events/ok', valid)
        ..serverWrite('$events/unknown', {...valid, 'type': 'photo'})
        ..serverWrite('$events/no-actor', {...valid, 'actorUid': '  '})
        ..serverWrite('$events/bad-kind', {...valid, 'kind': 'maybe'})
        ..serverWrite('$events/no-date', {...valid, 'createdAt': 'ayer'})
        ..serverWrite('$events/expired', {
          ...valid,
          'expireAt': clock.now().subtract(const Duration(minutes: 1)),
        })
        ..serverWrite('$events/zone-no-name', {
          'type': 'geofence',
          'actorUid': 'ana',
          'geofenceName': '',
          'transition': 'enter',
          'createdAt': serverTimestamp,
        })
        ..serverWrite('$events/zone-bad', {
          'type': 'geofence',
          'actorUid': 'ana',
          'geofenceName': 'Casa',
          'transition': 'teleport',
          'createdAt': serverTimestamp,
        })
        ..serverWrite('$events/sos-no-alert', {
          'type': 'sos',
          'actorUid': 'ana',
          'createdAt': serverTimestamp,
        })
        ..serverWrite('$events/member-bad', {
          'type': 'membership',
          'actorUid': 'ana',
          'change': 'promoted',
          'createdAt': serverTimestamp,
        })
        ..serverWrite('$events/not-a-map-field', {...valid, 'actorUid': 42});

      mirrorEvents(familyId);
      await cache
          .watchCollection(events)
          .firstWhere((docs) => docs.length == 11);
      final items = await repo.watchActivity(familyId).first;
      expect(items.map((i) => i.id), ['ok']);
    },
  );

  test(
    'la hora del dispositivo manda salvo que sea posterior a la del servidor',
    () async {
      const familyId = 'f1';
      final events = BackendPaths.events(familyId);
      final now = clock.now();
      store
        // Check-in hecho sin conexión hace 2 h y recibido ahora.
        ..serverWrite('$events/offline', {
          'type': 'checkIn',
          'actorUid': 'ana',
          'kind': 'ok',
          'createdAt': serverTimestamp,
          'clientCreatedAt': now.subtract(const Duration(hours: 2)),
        })
        // Reloj del emisor adelantado 1 h: manda la hora del servidor.
        ..serverWrite('$events/ahead', {
          'type': 'checkIn',
          'actorUid': 'luis',
          'kind': 'ok',
          'createdAt': now.subtract(const Duration(minutes: 5)),
          'clientCreatedAt': now.add(const Duration(hours: 1)),
        });

      mirrorEvents(familyId);
      final items = await repo
          .watchActivity(familyId)
          .firstWhere((items) => items.length == 2);
      expect(items.map((i) => i.id), ['ahead', 'offline']);
      expect(items[0].occurredAt, now.subtract(const Duration(minutes: 5)));
      expect(items[1].occurredAt, now.subtract(const Duration(hours: 2)));
    },
  );

  test('respeta el límite y conserva los más recientes', () async {
    const familyId = 'f1';
    for (var i = 0; i < 8; i++) {
      clock.advance(const Duration(minutes: 1));
      store.serverWrite(BackendPaths.event(familyId, 'e$i'), {
        'type': 'sos',
        'actorUid': 'ana',
        'alertId': 'a$i',
        'createdAt': serverTimestamp,
      });
    }
    mirrorEvents(familyId);
    await cache
        .watchCollection(BackendPaths.events(familyId))
        .firstWhere((docs) => docs.length == 8);
    final items = await repo.watchActivity(familyId, limit: 3).first;
    expect(items.map((i) => i.id), ['e7', 'e6', 'e5']);
  });

  test('sin eventos devuelve una lista vacía', () async {
    mirrorEvents('f1');
    expect(await repo.watchActivity('f1').first, isEmpty);
  });

  test('al purgar la familia local el historial se vacía', () async {
    const familyId = 'f1';
    store.serverWrite(BackendPaths.event(familyId, 'e1'), {
      'type': 'sos',
      'actorUid': 'ana',
      'alertId': 'a1',
      'createdAt': serverTimestamp,
    });
    mirrorEvents(familyId);
    await repo.watchActivity(familyId).firstWhere((i) => i.length == 1);
    await mirror.stop(familyId);
    await cache.clearScope(familyId);
    expect(await repo.watchActivity(familyId).first, isEmpty);
  });
}
