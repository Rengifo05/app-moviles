import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/check_ins/data/check_in_outbox_handler.dart';
import 'package:nexo_familia/features/check_ins/data/check_in_repository_impl.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/check_ins/domain/submit_check_in.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';
import 'package:nexo_familia/infrastructure/database/drift_stores.dart';
import 'package:nexo_familia/infrastructure/demo/in_memory_remote_store.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/outbox.dart';

import '../../../helpers/fakes.dart';

/// UUID v7 sintéticos (el registro seguro solo deja pasar ids con esa forma).
const String idA = '01890a5d-ac96-774b-bcce-b302099a9001';
const String idB = '01890a5d-ac96-774b-bcce-b302099a9002';
const String idC = '01890a5d-ac96-774b-bcce-b302099a9003';

const String fam = 'fam-prueba';
const String otherFam = 'fam-otra';

/// Coordenada sintética (no corresponde a ninguna persona).
final GeoPoint syntheticPoint = GeoPoint(4.5, -74.25);

/// Decorador del almacén remoto que puede responder un fallo después de
/// aplicar el lote (la confirmación se perdió en el camino) o antes.
final class _FlakyRemote implements RemoteStore {
  new(this._inner);

  final InMemoryRemoteStore _inner;

  /// Aplica el lote y responde este fallo una vez.
  Failure? failAfterCommitOnce;

  /// Responde este fallo una vez sin aplicar el lote.
  Failure? failBeforeCommitOnce;

  int commits = 0;

  @override
  Future<VoidResult> commit(List<RemoteWrite> writes) async {
    commits++;
    if (failBeforeCommitOnce case final failure?) {
      failBeforeCommitOnce = null;
      return Err(failure);
    }
    final result = await _inner.commit(writes);
    if (failAfterCommitOnce case final failure? when result.isOk) {
      failAfterCommitOnce = null;
      return Err(failure);
    }
    return result;
  }

  @override
  Future<Result<RemoteDoc?>> getDoc(String path) => _inner.getDoc(path);

  @override
  Stream<List<RemoteDoc>> watchCollection(String path, {RemoteQuery? query}) =>
      _inner.watchCollection(path, query: query);

  @override
  Stream<RemoteDoc?> watchDoc(String path) => _inner.watchDoc(path);
}

/// Bandeja que falla al guardar (disco lleno, base de datos cerrada…).
final class _BrokenOutbox implements OutboxStore {
  @override
  Future<void> enqueue(OutboxEntry entry) async =>
      throw StateError('base de datos no disponible');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Integración: repositorio + bandeja Drift (SQLite en memoria) +
/// procesador real + manejador + backend de demostración en memoria.
void main() {
  late FakeClock clock;
  late InMemoryRemoteStore backend;
  late _FlakyRemote remote;
  late AppDatabase db;
  late DriftOutboxStore outbox;
  late MemoryLogSink logs;
  late OutboxProcessor processor;
  late CheckInRepositoryImpl repo;
  late int nudges;
  Future<void>? lastDrain;

  setUp(() {
    clock = FakeClock();
    backend = InMemoryRemoteStore(clock: clock);
    remote = _FlakyRemote(backend);
    db = AppDatabase(NativeDatabase.memory());
    outbox = DriftOutboxStore(db);
    logs = MemoryLogSink();
    processor = OutboxProcessor(
      store: outbox,
      handlers: {
        CheckInOutbox.kind: CheckInOutboxHandler(
          remote: remote,
          clock: clock,
          cache: DriftDocumentCache(db),
        ),
      },
      clock: clock,
      logger: SafeLogger(sink: logs, clock: clock),
      random: () => 0.5,
    );
    nudges = 0;
    lastDrain = null;
    repo = CheckInRepositoryImpl(
      outbox: outbox,
      clock: clock,
      nudge: () {
        nudges++;
        lastDrain = processor.drain();
      },
    );
  });

  tearDown(() async {
    processor.stop();
    await lastDrain;
    await db.close();
  });

  CheckIn checkIn({
    String id = idA,
    String familyId = fam,
    CheckInKind kind = CheckInKind.ok,
    String? message,
    GeoPoint? location,
  }) => CheckIn(
    id: id,
    familyId: familyId,
    uid: 'ana',
    kind: kind,
    createdAt: clock.now().subtract(const Duration(seconds: 5)),
    delivery: DeliveryState.delivered,
    message: message,
    location: location,
  );

  Map<String, Json> events([String familyId = fam]) => {
    for (final MapEntry(:key, :value) in backend.snapshot.entries)
      if (key.startsWith('${BackendPaths.events(familyId)}/')) key: value,
  };

  /// Espera la vuelta que pidió el último `nudge` (sin temporizadores).
  Future<void> settle() async {
    await lastDrain;
    lastDrain = null;
  }

  /// Avanza el reloj más allá de cualquier espera y procesa lo vencido.
  Future<void> retryLater() async {
    clock.advance(const Duration(minutes: 6));
    await processor.drain();
  }

  group('submit', () {
    test(
      'envío normal: guarda, avisa al procesador y crea el evento',
      () async {
        final created = checkIn(
          message: '  Llegué a la casa  ',
          location: syntheticPoint,
        ).createdAt;
        final result = await repo.submit(
          checkIn(message: '  Llegué a la casa  ', location: syntheticPoint),
        );

        final saved = result.valueOrNull!;
        expect(saved.id, idA);
        expect(saved.delivery, DeliveryState.pending);
        expect(saved.message, 'Llegué a la casa');
        expect(nudges, 1);

        await settle();

        final event = events()[BackendPaths.event(fam, idA)];
        expect(event, {
          'type': 'checkIn',
          'actorUid': 'ana',
          'kind': 'ok',
          'message': 'Llegué a la casa',
          'lat': 4.5,
          'lng': -74.25,
          'createdAt': clock.now(),
          'clientCreatedAt': created,
          'expireAt': clock.now().add(const Duration(days: 30)),
        });
        expect(await outbox.find(idA), isNull);
        expect(await repo.watchPending(fam).first, isEmpty);
      },
    );

    test('la carga de la bandeja es mínima y sin claves nulas', () async {
      await repo.submit(checkIn(kind: CheckInKind.needHelp, message: '   '));
      final entry = (await outbox.find(idA))!;
      expect(entry.kind, 'checkIn');
      expect(entry.familyId, fam);
      expect(entry.payload, {
        'familyId': fam,
        'uid': 'ana',
        'kind': 'needHelp',
        'clientCreatedAt': checkIn().createdAt.millisecondsSinceEpoch,
      });
      await settle();
      final event = events()[BackendPaths.event(fam, idA)]!;
      expect(event.keys, isNot(contains('message')));
      expect(event.keys, isNot(contains('lat')));
      expect(event.keys, isNot(contains('lng')));
      expect(event['kind'], 'needHelp');
    });

    test('un mensaje de más de 140 caracteres no se guarda', () async {
      final result = await repo.submit(checkIn(message: 'a' * 141));
      expect(
        result.failureOrNull,
        const Failure.validation('check-in-message-too-long'),
      );
      expect(await outbox.find(idA), isNull);
      expect(nudges, 0);
    });

    test('el límite se mide sobre el texto recortado', () async {
      final result = await repo.submit(checkIn(message: '  ${'a' * 140}  '));
      expect(result.valueOrNull?.message, 'a' * 140);
      await settle();
      expect(events()[BackendPaths.event(fam, idA)]!['message'], 'a' * 140);
    });

    test('repetir el mismo check-in no crea otra entrada', () async {
      remote.failBeforeCommitOnce = const Failure.network();
      await repo.submit(checkIn(message: 'Primero'));
      await settle();
      await repo.submit(checkIn(message: 'Segundo'));
      await settle();
      final pending = await repo.watchPending(fam).first;
      expect(pending, hasLength(1));
      expect(pending.single.message, 'Primero');
    });

    test('si no se puede guardar en el teléfono, lo dice', () async {
      final broken = CheckInRepositoryImpl(
        outbox: _BrokenOutbox(),
        clock: clock,
        nudge: () => nudges++,
      );
      final result = await broken.submit(checkIn());
      expect(
        result.failureOrNull,
        const Failure.unexpected(CheckInFailureCodes.notSaved),
      );
      expect(nudges, 0);
    });
  });

  group('sin conexión', () {
    test('queda pendiente y se envía al recuperar la conexión', () async {
      backend.simulatedFailure = const Failure.network();
      await repo.submit(checkIn(message: 'Voy en camino'));
      await settle();

      expect(events(), isEmpty);
      final entry = (await outbox.find(idA))!;
      expect(entry.status, OutboxStatus.pending);
      expect(entry.attempts, 1);
      expect(entry.lastErrorCode, 'network');
      final pending = await repo.watchPending(fam).first;
      expect(pending.single.id, idA);
      expect(pending.single.delivery, DeliveryState.pending);
      expect(pending.single.message, 'Voy en camino');

      // Sigue sin conexión: otro intento fallido, sigue pendiente.
      await retryLater();
      expect((await outbox.find(idA))!.attempts, 2);
      expect(events(), isEmpty);

      backend.simulatedFailure = null;
      await retryLater();
      expect(events().keys, [BackendPaths.event(fam, idA)]);
      expect(await repo.watchPending(fam).first, isEmpty);
    });

    test('watchPending refleja el paso de pendiente a enviado', () async {
      backend.simulatedFailure = const Failure.network();
      final seen = <List<String>>[];
      final sub = repo
          .watchPending(fam)
          .listen((list) => seen.add([for (final c in list) c.id]));
      addTearDown(sub.cancel);

      await repo.submit(checkIn());
      await settle();
      await pumpEventQueue();
      expect(seen.last, [idA]);

      backend.simulatedFailure = null;
      await retryLater();
      await pumpEventQueue();
      expect(seen.last, isEmpty);
    });
  });

  group('reintentos', () {
    test('si se perdió la confirmación, el reintento no duplica', () async {
      remote.failAfterCommitOnce = const Failure.network();
      await repo.submit(checkIn(message: 'Hola'));
      await settle();

      // El servidor sí lo guardó, pero el teléfono no lo sabe: pendiente.
      final firstCreatedAt = clock.now();
      expect(events(), hasLength(1));
      expect((await outbox.find(idA))!.status, OutboxStatus.pending);

      await retryLater();
      expect(remote.commits, 2);
      expect(await outbox.find(idA), isNull);
      final all = events();
      expect(all, hasLength(1));
      // El evento original no se reescribió.
      expect(all.values.single['createdAt'], firstCreatedAt);
    });

    test('un rechazo permanente queda fallido y se puede reintentar', () async {
      remote.failBeforeCommitOnce = const Failure.permissionDenied();
      await repo.submit(checkIn(kind: CheckInKind.needHelp));
      await settle();

      final failed = await repo.watchPending(fam).first;
      expect(failed.single.delivery, DeliveryState.failed);
      expect(events(), isEmpty);

      expect(await repo.retry(idA), const Ok<void>(null));
      expect(nudges, 2);
      await settle();
      expect(events().keys, [BackendPaths.event(fam, idA)]);
      expect(await repo.watchPending(fam).first, isEmpty);
    });

    test('reintentar uno que ya no está en la bandeja', () async {
      expect(
        (await repo.retry(idA)).failureOrNull,
        const Failure.notFound(CheckInFailureCodes.notFound),
      );
    });

    test('descartar uno fallido lo quita y no se envía', () async {
      remote.failBeforeCommitOnce = const Failure.permissionDenied();
      await repo.submit(checkIn());
      await settle();

      expect(await repo.discard(idA), const Ok<void>(null));
      expect(await repo.watchPending(fam).first, isEmpty);
      await retryLater();
      expect(events(), isEmpty);
      expect(
        (await repo.discard(idA)).failureOrNull,
        const Failure.notFound(CheckInFailureCodes.notFound),
      );
    });

    test('no se descarta uno que se está enviando', () async {
      await outbox.enqueue(
        OutboxEntry(
          id: idA,
          kind: CheckInOutbox.kind,
          familyId: fam,
          payload: const {'uid': 'ana', 'kind': 'ok'},
          createdAt: clock.now(),
          status: OutboxStatus.sending,
        ),
      );
      expect(
        (await repo.discard(idA)).failureOrNull,
        const Failure.conflict(CheckInFailureCodes.sending),
      );
      expect(await outbox.find(idA), isNotNull);
    });
  });

  test('watchPending: solo check-ins de esa familia, en orden', () async {
    backend.simulatedFailure = const Failure.network();
    await repo.submit(checkIn(message: 'Uno'));
    clock.advance(const Duration(seconds: 1));
    await repo.submit(checkIn(id: idB, familyId: otherFam));
    clock.advance(const Duration(seconds: 1));
    await repo.submit(checkIn(id: idC, kind: CheckInKind.needHelp));
    await outbox.enqueue(
      OutboxEntry(
        id: '01890a5d-ac96-774b-bcce-b302099a9004',
        kind: 'sos',
        familyId: fam,
        payload: const {},
        createdAt: clock.now(),
      ),
    );
    await settle();

    final pending = await repo.watchPending(fam).first;
    expect(pending.map((c) => c.id), [idA, idC]);
    expect(pending.map((c) => c.kind), [CheckInKind.ok, CheckInKind.needHelp]);
    expect(pending.first.uid, 'ana');
    expect(pending.first.familyId, fam);
    expect(
      pending.first.createdAt,
      checkIn().createdAt.subtract(const Duration(seconds: 2)),
    );
  });

  test('la ubicación viaja en la bandeja y vuelve como GeoPoint', () async {
    backend.simulatedFailure = const Failure.network();
    await repo.submit(checkIn(location: syntheticPoint));
    await settle();
    final pending = await repo.watchPending(fam).first;
    expect(pending.single.location, syntheticPoint);
  });

  test('los registros no contienen el mensaje ni coordenadas', () async {
    remote.failBeforeCommitOnce = const Failure.network();
    await repo.submit(
      checkIn(message: 'Mensaje privado', location: syntheticPoint),
    );
    await settle();
    await retryLater();
    expect(events(), hasLength(1));
    final text = logs.entries.map((e) => e.toString()).join('\n');
    expect(text, isNot(contains('Mensaje privado')));
    expect(text, isNot(contains('74.25')));
    expect(text, isNot(contains('4.5')));
  });

  group('CheckInOutboxHandler', () {
    test(
      'una carga inválida falla como validación (no se reintenta)',
      () async {
        final handler = CheckInOutboxHandler(
          remote: remote,
          clock: clock,
          cache: DriftDocumentCache(db),
        );
        final result = await handler.send(
          OutboxEntry(
            id: idA,
            kind: CheckInOutbox.kind,
            familyId: fam,
            payload: const {'kind': 'otro'},
            createdAt: clock.now(),
          ),
        );
        expect(
          result.failureOrNull,
          const Failure.validation(CheckInOutboxHandler.invalidPayload),
        );
        expect(remote.commits, 0);
      },
    );

    test('la ubicación sigue el consentimiento VIGENTE al enviar', () async {
      final cache = DriftDocumentCache(db);
      final handler = CheckInOutboxHandler(
        remote: remote,
        clock: clock,
        cache: cache,
      );
      Future<Json> sendWith(String id, String state, String precision) async {
        await cache.upsert(
          BackendPaths.consents(fam),
          fam,
          RemoteDoc('ana', {'state': state, 'precision': precision}),
          clock.now(),
        );
        await handler.send(
          OutboxEntry(
            id: id,
            kind: CheckInOutbox.kind,
            familyId: fam,
            payload: {
              'familyId': fam,
              'uid': 'ana',
              'kind': 'ok',
              'lat': 4.61734,
              'lng': -74.07291,
              'clientCreatedAt': clock.now().millisecondsSinceEpoch,
            },
            createdAt: clock.now(),
          ),
        );
        return backend.serverRead(BackendPaths.event(fam, id))!;
      }

      final approx = await sendWith(idA, 'sharing', 'approximate');
      expect((approx['lat'], approx['lng']), (4.62, -74.07));
      final paused = await sendWith(idB, 'paused', 'exact');
      expect(paused.keys, isNot(contains('lat')));
    });

    test('expireAt queda dentro de la tolerancia de las reglas', () async {
      await repo.submit(checkIn());
      await settle();
      final event = events().values.single;
      final expireAt = event['expireAt']! as DateTime;
      expect(
        expireAt.isAfter(clock.now().add(const Duration(days: 31))),
        isFalse,
      );
    });
  });
}
