import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/infrastructure/demo/in_memory_remote_store.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';

import '../../helpers/fakes.dart';

/// Escucha un `Stream` y acumula lo que emite.
final class _Recorder<T> {
  new(Stream<T> stream) {
    _subscription = stream.listen(
      values.add,
      onError: errors.add,
      onDone: () => done = true,
    );
  }

  final List<T> values = [];
  final List<Object> errors = [];
  bool done = false;
  late final StreamSubscription<T> _subscription;

  Future<void> cancel() => _subscription.cancel();
}

/// Reloj que avanza un microsegundo en cada lectura, como uno real.
final class _TickingClock implements Clock {
  DateTime _now = DateTime.utc(2026);

  @override
  DateTime now() => _now = _now.add(const Duration(microseconds: 1));
}

/// Deja correr las microtareas pendientes (entrega de eventos).
Future<void> _settle() => Future<void>.delayed(Duration.zero);

List<String> _ids(List<RemoteDoc> docs) => [for (final d in docs) d.id];

const _invalidPath = Err<void>(Failure.validation('invalid-path'));

void main() {
  late FakeClock clock;
  late InMemoryRemoteStore store;

  setUp(() {
    clock = FakeClock();
    store = InMemoryRemoteStore(clock: clock);
  });

  tearDown(() => store.dispose());

  Future<void> put(String path, Json data) async {
    expect(await store.commit([RemoteWrite.put(path, data)]), const Ok(null));
  }

  Future<List<String>> idsOf(String path, [RemoteQuery? query]) async =>
      _ids(await store.watchCollection(path, query: query).first);

  group('watchCollection', () {
    test('devuelve solo los documentos directos de la colección', () async {
      await put('families/f1', {'name': 'Casa Prueba'});
      await put('families/f1/members/a', {'role': 'owner'});
      await put('families/f1/members/b', {'role': 'member'});
      await put('families/f1/members/a/devices/d1', {'platform': 'android'});
      await put('families/f1/geofences/g1', {'name': 'Zona'});
      // Mismo prefijo de texto, distinta familia.
      await put('families/f10/members/c', {'role': 'owner'});

      expect(await idsOf('families/f1/members'), ['a', 'b']);
      expect(await idsOf('families/f1/members/a/devices'), ['d1']);
      expect(await idsOf('families/f10/members'), ['c']);
      // f10 solo tiene subcolecciones: como en Firestore, no es un documento.
      expect(await idsOf('families'), ['f1']);
    });

    test('sin orderBy ordena por ID, no por orden de inserción', () async {
      for (final id in ['c', 'a', 'b']) {
        await put('items/$id', {'n': 1});
      }
      expect(await idsOf('items'), ['a', 'b', 'c']);
    });

    group('con datos de edad', () {
      setUp(() async {
        await put('people/x', {'age': 3, 'role': 'member', 'active': true});
        await put('people/a', {'age': 1, 'role': 'admin', 'active': true});
        await put('people/b', {'age': 3, 'role': 'admin', 'active': false});
        await put('people/c', {'age': 2, 'role': 'admin', 'active': true});
      });

      test('orderBy ordena ascendente y desempata por ID', () async {
        expect(await idsOf('people', const RemoteQuery(orderBy: 'age')), [
          'a',
          'c',
          'b',
          'x',
        ]);
      });

      test('descending invierte el orden, incluido el desempate', () async {
        expect(
          await idsOf(
            'people',
            const RemoteQuery(orderBy: 'age', descending: true),
          ),
          ['x', 'b', 'c', 'a'],
        );
      });

      test('descending sin orderBy no tiene efecto', () async {
        expect(await idsOf('people', const RemoteQuery(descending: true)), [
          'a',
          'b',
          'c',
          'x',
        ]);
      });

      test('limit se aplica después de ordenar', () async {
        expect(
          await idsOf(
            'people',
            const RemoteQuery(orderBy: 'age', descending: true, limit: 2),
          ),
          ['x', 'b'],
        );
        expect(
          await idsOf('people', const RemoteQuery(limit: 10)),
          hasLength(4),
        );
      });

      test('whereEquals exige que coincidan todos los campos', () async {
        expect(
          await idsOf(
            'people',
            const RemoteQuery(whereEquals: {'role': 'admin', 'active': true}),
          ),
          ['a', 'c'],
        );
        expect(
          await idsOf(
            'people',
            const RemoteQuery(whereEquals: {'role': 'owner'}),
          ),
          isEmpty,
        );
      });

      test('combina whereEquals, orderBy, descending y limit', () async {
        expect(
          await idsOf(
            'people',
            const RemoteQuery(
              whereEquals: {'role': 'admin'},
              orderBy: 'age',
              descending: true,
              limit: 2,
            ),
          ),
          ['b', 'c'],
        );
      });
    });

    test('whereEquals con null solo coincide con un null explícito', () async {
      await put('alerts/a', {'resolvedAt': null});
      await put('alerts/b', <String, Object?>{});
      await put('alerts/c', {'resolvedAt': DateTime.utc(2026)});
      expect(
        await idsOf(
          'alerts',
          const RemoteQuery(whereEquals: {'resolvedAt': null}),
        ),
        ['a'],
      );
    });

    test('whereEquals compara listas y mapas por contenido y fechas por '
        'instante, como Firestore', () async {
      final at = DateTime.utc(2026, 5, 6, 7, 8);
      await put('docs/a', {
        'tags': ['x', 'y'],
        'meta': {
          'k': 1,
          'list': [1, 2],
        },
        'at': at,
      });
      await put('docs/b', {
        'tags': ['y', 'x'],
        'meta': {'k': 1},
        'at': at.add(const Duration(seconds: 1)),
      });
      for (final where in <Map<String, Object?>>[
        {
          'tags': ['x', 'y'],
        },
        {
          'meta': {
            'list': [1.0, 2.0],
            'k': 1,
          },
        },
        {'at': at.toLocal()},
      ]) {
        expect(await idsOf('docs', RemoteQuery(whereEquals: where)), [
          'a',
        ], reason: '$where');
      }
    });

    test('orderBy excluye los documentos sin el campo, no los que lo tienen '
        'a null', () async {
      await put('alerts/a', {'at': 2});
      await put('alerts/b', <String, Object?>{});
      await put('alerts/c', {'at': null});
      expect(await idsOf('alerts', const RemoteQuery(orderBy: 'at')), [
        'c',
        'a',
      ]);
    });

    test('ordena valores de distinto tipo como Firestore: null < bool < número '
        '< fecha < texto', () async {
      await put('mixed/texto', {'v': 'abc'});
      await put('mixed/fecha', {'v': DateTime.utc(2026)});
      await put('mixed/entero', {'v': 2});
      await put('mixed/decimal', {'v': 1.5});
      await put('mixed/verdadero', {'v': true});
      await put('mixed/falso', {'v': false});
      await put('mixed/nulo', {'v': null});
      expect(await idsOf('mixed', const RemoteQuery(orderBy: 'v')), [
        'nulo',
        'falso',
        'verdadero',
        'decimal',
        'entero',
        'fecha',
        'texto',
      ]);
    });

    test('emite de nuevo con cada commit que cambia los datos', () async {
      final recorder = _Recorder(store.watchCollection('items'));
      await _settle();
      await put('items/a', {'n': 1});
      await store.commit([const RemoteWrite.remove('items/a')]);
      await _settle();

      expect(recorder.values.map(_ids), [
        isEmpty,
        ['a'],
        isEmpty,
      ]);
      expect(recorder.values[1].single.data, {'n': 1});
      await recorder.cancel();
    });

    test('una ruta que no es de colección emite invalid-path', () async {
      for (final path in ['families/f1', 'families//members', '', '/items']) {
        await expectLater(
          store.watchCollection(path),
          emitsInOrder([
            emitsError(const Failure.validation('invalid-path')),
            emitsDone,
          ]),
          reason: path,
        );
      }
    });

    test('un limit menor que 1 es un error de programación, como en '
        'Firestore', () {
      for (final limit in [0, -1]) {
        expect(
          () =>
              store.watchCollection('items', query: RemoteQuery(limit: limit)),
          throwsRangeError,
          reason: '$limit',
        );
      }
    });

    test('al cancelar la escucha deja de emitir', () async {
      final recorder = _Recorder(store.watchCollection('items'));
      await _settle();
      await recorder.cancel();
      await put('items/a', {'n': 1});
      await _settle();
      expect(recorder.values, hasLength(1));
      expect(recorder.errors, isEmpty);
    });
  });

  group('watchDoc', () {
    test('emite null, luego el documento con el ID del último segmento y null '
        'al borrarlo', () async {
      final recorder = _Recorder(store.watchDoc('families/f1/members/ana'));
      await _settle();
      await put('families/f1/members/ana', {'role': 'owner'});
      await store.commit([const RemoteWrite.remove('families/f1/members/ana')]);
      await _settle();

      expect(recorder.values, hasLength(3));
      expect(recorder.values[0], isNull);
      expect(recorder.values[1]!.id, 'ana');
      expect(recorder.values[1]!.data, {'role': 'owner'});
      expect(recorder.values[2], isNull);
      await recorder.cancel();
    });

    test('una ruta de colección emite invalid-path', () async {
      await expectLater(
        store.watchDoc('families'),
        emitsError(const Failure.validation('invalid-path')),
      );
    });
  });

  group('primera emisión', () {
    test('es asíncrona en watchCollection y watchDoc', () {
      fakeAsync((async) {
        store.serverWrite('items/a', {'n': 1});
        final collection = <List<RemoteDoc>>[];
        final doc = <RemoteDoc?>[];
        store.watchCollection('items').listen(collection.add);
        store.watchDoc('items/a').listen(doc.add);

        expect(collection, isEmpty);
        expect(doc, isEmpty);

        async.flushMicrotasks();
        expect(collection.single.single.id, 'a');
        expect(doc.single!.data, {'n': 1});
      });
    });

    test('una escritura antes de la primera emisión no se pierde', () {
      fakeAsync((async) {
        final collection = <List<RemoteDoc>>[];
        store.watchCollection('items').listen(collection.add);
        unawaited(
          store.commit([
            const RemoteWrite.put('items/a', {'n': 1}),
          ]),
        );

        async.flushMicrotasks();
        expect(collection, isNotEmpty);
        expect(_ids(collection.last), ['a']);
      });
    });
  });

  group('getDoc', () {
    test('devuelve Ok(null) si no existe y el documento si existe', () async {
      expect(await store.getDoc('items/a'), const Ok<RemoteDoc?>(null));
      await put('items/a', {'n': 1});
      final doc = (await store.getDoc('items/a')).valueOrNull!;
      expect(doc.id, 'a');
      expect(doc.data, {'n': 1});
    });

    test('una ruta de colección devuelve invalid-path', () async {
      expect(await store.getDoc('items'), _invalidPath);
    });
  });

  group('commit', () {
    test('put reemplaza el documento completo', () async {
      await put('items/a', {'n': 1, 'old': true});
      await put('items/a', {'n': 2});
      expect(store.serverRead('items/a'), {'n': 2});
    });

    test('create solo escribe si el documento no existe', () async {
      await store.commit([
        const RemoteWrite.create('items/a', {'n': 1}),
      ]);
      await store.commit([
        const RemoteWrite.create('items/a', {'n': 2}),
        const RemoteWrite.create('items/b', {'n': 3}),
      ]);
      expect(store.serverRead('items/a'), {'n': 1});
      expect(store.serverRead('items/b'), {'n': 3});
    });

    test('merge crea el documento si no existe', () async {
      await store.commit([
        const RemoteWrite.merge('items/a', {'n': 1}),
      ]);
      expect(store.serverRead('items/a'), {'n': 1});
    });

    test('merge fusiona en profundidad los mapas anidados', () async {
      final t0 = clock.now();
      await put('families/f1/emergencies/s1', {
        'uid': 'ana',
        'acks': {'bruno': t0},
        'resolvedAt': null,
      });
      clock.advance(const Duration(minutes: 1));
      await store.commit([
        const RemoteWrite.merge('families/f1/emergencies/s1', {
          'acks': {'carla': serverTimestamp},
        }),
      ]);

      expect(store.serverRead('families/f1/emergencies/s1'), {
        'uid': 'ana',
        'acks': {'bruno': t0, 'carla': clock.now()},
        'resolvedAt': null,
      });
    });

    test('merge reemplaza listas, escalares y con un mapa vacío', () async {
      await put('items/a', {
        'list': [1, 2],
        'scalar': 1,
        'map': {'x': 1},
        'emptied': {'x': 1},
      });
      await store.commit([
        const RemoteWrite.merge('items/a', {
          'list': [3],
          'scalar': {'y': 2},
          'map': 'texto',
          'emptied': <String, Object?>{},
        }),
      ]);
      expect(store.serverRead('items/a'), {
        'list': [3],
        'scalar': {'y': 2},
        'map': 'texto',
        'emptied': <String, Object?>{},
      });
    });

    test('remove borra y no falla si el documento no existe', () async {
      await put('items/a', {'n': 1});
      expect(
        await store.commit([
          const RemoteWrite.remove('items/a'),
          const RemoteWrite.remove('items/nadie'),
        ]),
        const Ok(null),
      );
      expect(store.snapshot, isEmpty);
    });

    test('aplica las escrituras de un lote en orden', () async {
      await store.commit([
        const RemoteWrite.put('items/a', {'n': 1, 'm': 1}),
        const RemoteWrite.merge('items/a', {'n': 2}),
        const RemoteWrite.remove('items/a'),
        const RemoteWrite.merge('items/a', {'z': 3}),
        const RemoteWrite.put('items/b', {'n': 4}),
      ]);
      expect(store.snapshot, {
        'items/a': {'z': 3},
        'items/b': {'n': 4},
      });
    });

    test('es atómico: una ruta inválida anula todo el lote', () async {
      await put('items/keep', {'n': 0});
      final recorder = _Recorder(store.watchCollection('items'));
      await _settle();

      for (final bad in [
        'items',
        'families/f1/members',
        '',
        '/items/a',
        'items/a/',
        'families//members/x',
        // IDs que Firestore reserva o rechaza.
        'items/.',
        'items/..',
        'items/__x__',
        '__x__/a',
      ]) {
        final result = await store.commit([
          const RemoteWrite.put('items/new', {'n': 1}),
          const RemoteWrite.remove('items/keep'),
          RemoteWrite.put(bad, const {'n': 2}),
        ]);
        expect(result, _invalidPath, reason: bad);
      }
      await _settle();

      expect(store.snapshot, {
        'items/keep': {'n': 0},
      });
      expect(recorder.values, hasLength(1), reason: 'sin emisiones nuevas');
      await recorder.cancel();
    });

    test('un lote vacío no escribe ni emite', () async {
      final recorder = _Recorder(store.watchCollection('items'));
      await _settle();
      expect(await store.commit(const []), const Ok(null));
      await _settle();
      expect(recorder.values, hasLength(1));
      await recorder.cancel();
    });

    test('un lote con varias escrituras produce una sola emisión', () async {
      final recorder = _Recorder(store.watchCollection('items'));
      await _settle();
      await store.commit([
        for (final id in ['a', 'b', 'c'])
          RemoteWrite.put('items/$id', const {}),
      ]);
      await _settle();
      expect(recorder.values.map(_ids), [
        isEmpty,
        ['a', 'b', 'c'],
      ]);
      await recorder.cancel();
    });
  });

  group('serverTimestamp', () {
    test('se resuelve con el reloj inyectado, también anidado en mapas y '
        'listas', () async {
      clock.current = DateTime.utc(2026, 3, 4, 5, 6, 7);
      await put('items/a', {
        'createdAt': serverTimestamp,
        'meta': {
          'updatedAt': serverTimestamp,
          'deep': {'at': serverTimestamp},
        },
        'list': [
          serverTimestamp,
          {'at': serverTimestamp},
        ],
      });

      final now = DateTime.utc(2026, 3, 4, 5, 6, 7);
      expect(store.serverRead('items/a'), {
        'createdAt': now,
        'meta': {
          'updatedAt': now,
          'deep': {'at': now},
        },
        'list': [
          now,
          {'at': now},
        ],
      });
      expect(
        (store.serverRead('items/a')!['createdAt']! as DateTime).isUtc,
        isTrue,
      );
    });

    test('todas las marcas de un lote comparten instante y las siguientes '
        'avanzan con el reloj', () async {
      final t0 = clock.now();
      await store.commit([
        const RemoteWrite.put('items/a', {'createdAt': serverTimestamp}),
        const RemoteWrite.put('items/b', {'createdAt': serverTimestamp}),
      ]);
      clock.advance(const Duration(minutes: 5));
      await store.commit([
        const RemoteWrite.merge('items/a', {
          'meta': {'updatedAt': serverTimestamp},
        }),
      ]);

      expect(store.serverRead('items/a'), {
        'createdAt': t0,
        'meta': {'updatedAt': t0.add(const Duration(minutes: 5))},
      });
      expect(store.serverRead('items/b'), {'createdAt': t0});
    });

    test('serverWrite también usa el reloj inyectado', () {
      store.serverWrite('items/a', {
        'x': {'at': serverTimestamp},
      });
      expect(store.serverRead('items/a'), {
        'x': {'at': clock.now()},
      });
    });

    test('el marcador nunca queda guardado', () async {
      await put('items/a', {
        'a': serverTimestamp,
        'b': [
          {'c': serverTimestamp},
        ],
      });
      bool containsMarker(Object? value) => switch (value) {
        ServerTimestamp() => true,
        final Map<String, Object?> map => map.values.any(containsMarker),
        final List<Object?> list => list.any(containsMarker),
        _ => false,
      };
      expect(store.snapshot.values.any(containsMarker), isFalse);
    });
  });

  group('simulatedFailure', () {
    const failure = Failure.network();

    test('getDoc y commit devuelven el fallo y commit no escribe', () async {
      await put('items/a', {'n': 1});
      store.simulatedFailure = failure;

      expect(await store.getDoc('items/a'), const Err<RemoteDoc?>(failure));
      expect(
        await store.commit([
          const RemoteWrite.put('items/b', {'n': 2}),
          const RemoteWrite.remove('items/a'),
        ]),
        const Err<void>(failure),
      );
      expect(store.snapshot, {
        'items/a': {'n': 1},
      });
    });

    test('watchCollection y watchDoc emiten el fallo como error y '
        'terminan', () async {
      store.simulatedFailure = failure;
      await expectLater(
        store.watchCollection('items'),
        emitsInOrder([emitsError(failure), emitsDone]),
      );
      await expectLater(
        store.watchDoc('items/a'),
        emitsInOrder([emitsError(failure), emitsDone]),
      );
    });

    test('un error termina la escucha, como en Firestore: no vuelve a emitir '
        'aunque el fallo desaparezca', () async {
      final recorder = _Recorder(store.watchCollection('items'));
      await _settle();

      store
        ..simulatedFailure = failure
        // La lógica de servidor no depende de la conexión del cliente.
        ..serverWrite('items/a', {'n': 1});
      await _settle();
      expect(recorder.errors, [failure]);
      expect(recorder.done, isTrue);

      store
        ..simulatedFailure = null
        ..serverWrite('items/b', {'n': 2});
      await _settle();
      expect(recorder.values.map(_ids), [isEmpty]);
      expect(recorder.errors, [failure]);
      // Para seguir recibiendo datos hay que suscribirse de nuevo.
      expect(await idsOf('items'), ['a', 'b']);
    });
  });

  group('copias defensivas', () {
    Json sample() => {
      'n': 1,
      'nested': {'x': 1},
      'list': [
        1,
        {'y': 1},
      ],
    };

    void mutate(Json data) {
      data['n'] = 99;
      (data['nested']! as Json)['x'] = 99;
      final list = data['list']! as List<Object?>;
      (list[1]! as Json)['y'] = 99;
      list.add(99);
    }

    test('mutar el RemoteDoc de getDoc no altera el almacén', () async {
      await put('items/a', sample());
      mutate((await store.getDoc('items/a')).valueOrNull!.data);
      expect(store.serverRead('items/a'), sample());
    });

    test('mutar lo emitido por watchCollection y watchDoc no altera el '
        'almacén ni a otros observadores', () async {
      await put('items/a', sample());
      mutate((await store.watchCollection('items').first).single.data);
      mutate((await store.watchDoc('items/a').first)!.data);
      expect(store.serverRead('items/a'), sample());
      expect((await store.watchDoc('items/a').first)!.data, sample());
    });

    test('mutar el mapa escrito después del commit no altera el '
        'almacén', () async {
      final data = sample();
      await store.commit([RemoteWrite.put('items/a', data)]);
      mutate(data);

      final merged = sample();
      await store.commit([RemoteWrite.merge('items/b', merged)]);
      mutate(merged);

      final written = sample();
      store.serverWrite('items/c', written);
      mutate(written);

      for (final id in ['a', 'b', 'c']) {
        expect(store.serverRead('items/$id'), sample(), reason: id);
      }
    });

    test('snapshot es de solo lectura y sus documentos son copias', () async {
      await put('items/a', sample());
      final snapshot = store.snapshot;
      expect(() => snapshot['items/b'] = {}, throwsUnsupportedError);
      mutate(snapshot['items/a']!);
      expect(store.serverRead('items/a'), sample());
    });

    test('serverRead devuelve una copia', () {
      store.serverWrite('items/a', sample());
      mutate(store.serverRead('items/a')!);
      expect(store.serverRead('items/a'), sample());
    });
  });

  group('lógica de servidor', () {
    test('serverTransaction notifica un único cambio al final', () async {
      final recorder = _Recorder(store.watchCollection('items'));
      await _settle();
      final result = store.serverTransaction(() {
        store
          ..serverWrite('items/a', {'n': 1})
          ..serverWrite('items/b', {'n': 2})
          ..serverDelete('items/a');
        return 'hecho';
      });
      await _settle();

      expect(result, 'hecho');
      expect(recorder.values.map(_ids), [
        isEmpty,
        ['b'],
      ]);
      await recorder.cancel();
    });

    test('serverTransaction revierte todo si el cuerpo lanza, también lo de '
        'una transacción anidada', () async {
      store.serverWrite('items/keep', {'n': 0});
      final recorder = _Recorder(store.watchCollection('items'));
      await _settle();

      expect(
        () => store.serverTransaction<void>(() {
          store.serverTransaction(() {
            store
              ..serverWrite('items/a', {'n': 1})
              ..serverDelete('items/keep');
          });
          store.serverWrite('items/b', {'n': 2});
          throw StateError('fallo a mitad');
        }),
        throwsStateError,
      );
      await _settle();

      expect(store.snapshot, {
        'items/keep': {'n': 0},
      });
      expect(recorder.values, hasLength(1), reason: 'sin emisiones nuevas');

      // Tras el fallo, el almacén sigue notificando con normalidad.
      store.serverWrite('items/c', {'n': 3});
      await _settle();
      expect(_ids(recorder.values.last), ['c', 'keep']);
      await recorder.cancel();
    });

    test('una transacción anidada que lanza se revierte aunque la exterior '
        'capture el error', () async {
      store.serverWrite('items/keep', {'n': 0});
      final recorder = _Recorder(store.watchCollection('items'));
      await _settle();

      store.serverTransaction(() {
        store.serverWrite('items/outer', {'n': 1});
        try {
          store.serverTransaction<void>(() {
            store
              ..serverWrite('items/inner', {'n': 2})
              ..serverDelete('items/keep');
            throw const FormatException('fallo interno');
          });
        } on FormatException {
          // La exterior sigue: solo debe perderse lo de la anidada.
        }
      });
      await _settle();

      expect(store.snapshot, {
        'items/keep': {'n': 0},
        'items/outer': {'n': 1},
      });
      expect(recorder.values.map(_ids), [
        ['keep'],
        ['keep', 'outer'],
      ]);
      await recorder.cancel();
    });

    test('todas las marcas de una transacción, también las anidadas, '
        'comparten instante, como en Firestore', () async {
      final local = InMemoryRemoteStore(clock: _TickingClock());
      local.serverTransaction(() {
        local.serverWrite('items/a', {'at': serverTimestamp});
        local.serverTransaction(
          () => local.serverWrite('items/b', {'at': serverTimestamp}),
        );
      });
      // Fuera de una transacción cada escritura tiene su propio instante.
      local.serverWrite('items/c', {'at': serverTimestamp});

      final [a, b, c] = [
        for (final id in ['a', 'b', 'c']) local.serverRead('items/$id')!['at'],
      ];
      expect(a, b);
      expect(c, isNot(a));
      await local.dispose();
    });

    test('serverList devuelve solo hijos directos y admite borrar mientras se '
        'recorre', () {
      store
        ..serverWrite('families/f1/members/a', {})
        ..serverWrite('families/f1/members/b', {})
        ..serverWrite('families/f1/members/a/devices/d', {})
        ..serverWrite('families/f10/members/c', {});
      final paths = store.serverList('families/f1/members');
      expect(paths, ['families/f1/members/a', 'families/f1/members/b']);
      paths.forEach(store.serverDelete);
      expect(store.serverList('families/f1/members'), isEmpty);
    });

    test('serverDeleteTree borra el documento y sus subcolecciones sin tocar '
        'rutas con el mismo prefijo', () {
      store
        ..serverWrite('families/f1', {})
        ..serverWrite('families/f1/members/a', {})
        ..serverWrite('families/f1/members/a/x/y', {})
        ..serverWrite('families/f10', {})
        ..serverWrite('families/f10/members/b', {})
        ..serverDeleteTree('families/f1');
      expect(store.snapshot.keys, ['families/f10', 'families/f10/members/b']);
    });

    test('clock expone el reloj inyectado', () {
      expect(store.clock, same(clock));
    });

    test('dispose termina las escuchas abiertas', () async {
      final local = InMemoryRemoteStore(clock: clock);
      final recorder = _Recorder(local.watchCollection('items'));
      await _settle();
      await local.dispose();
      await _settle();
      expect(recorder.done, isTrue);
      expect(recorder.values, hasLength(1));
    });
  });
}
