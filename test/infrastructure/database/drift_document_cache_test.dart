import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';
import 'package:nexo_familia/infrastructure/database/drift_stores.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/document_cache.dart';

const _members = 'families/f1/members';
const _geofences = 'families/f1/geofences';
const _otherMembers = 'families/f2/members';
const _memberships = 'users/u1/memberships';

void main() {
  late AppDatabase db;
  late DriftDocumentCache cache;
  final t0 = DateTime.utc(2026, 1, 1, 12);
  final t1 = t0.add(const Duration(minutes: 1, milliseconds: 250));

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    cache = DriftDocumentCache(db);
  });

  tearDown(() => db.close());

  Future<List<CachedDoc>> docs(String collection) =>
      cache.watchCollection(collection).first;

  Future<List<String>> ids(String collection) async => [
    for (final d in await docs(collection)) d.id,
  ];

  RemoteDoc doc(String id, [Json data = const {'role': 'member'}]) =>
      RemoteDoc(id, data);

  group('replaceCollection', () {
    test('guarda la instantánea con datos, fechas y syncedAt', () async {
      await cache.replaceCollection(_members, 'f1', [
        doc('b'),
        doc('a', {'role': 'owner', 'joinedAt': DateTime.utc(2025, 5)}),
      ], t0);

      final stored = await docs(_members);
      expect([for (final d in stored) d.id], ['a', 'b']);
      expect(stored.first.data, {
        'role': 'owner',
        'joinedAt': DateTime.utc(2025, 5),
      });
      expect(stored.first.syncedAt, t0);
      expect(stored.first.syncedAt.isUtc, isTrue);
    });

    test('borra lo que ya no está y actualiza el resto', () async {
      await cache.replaceCollection(_members, 'f1', [
        doc('a'),
        doc('b'),
        doc('c'),
      ], t0);

      await cache.replaceCollection(_members, 'f1', [
        doc('a', {'role': 'admin'}),
        doc('d'),
      ], t1);

      final stored = await docs(_members);
      expect([for (final d in stored) d.id], ['a', 'd']);
      expect(stored.first.data, {'role': 'admin'});
      expect(stored.every((d) => d.syncedAt == t1), isTrue);
    });

    test('no toca otras colecciones ni otros ámbitos', () async {
      await cache.replaceCollection(_members, 'f1', [doc('a')], t0);
      await cache.replaceCollection(_geofences, 'f1', [doc('g1')], t0);
      await cache.replaceCollection(_otherMembers, 'f2', [doc('a')], t0);
      await cache.replaceCollection(_memberships, DocumentCache.userScope, [
        doc('f1'),
      ], t0);

      await cache.replaceCollection(_members, 'f1', [], t1);

      expect(await ids(_members), isEmpty);
      expect(await ids(_geofences), ['g1']);
      expect(await ids(_otherMembers), ['a']);
      expect(await ids(_memberships), ['f1']);
    });

    test('es atómica: si un documento falla no cambia nada', () async {
      await cache.replaceCollection(_members, 'f1', [doc('a'), doc('b')], t0);

      await expectLater(
        cache.replaceCollection(_members, 'f1', [
          doc('c'),
          doc('d', {'raro': Object()}),
        ], t1),
        throwsUnsupportedError,
      );

      final stored = await docs(_members);
      expect([for (final d in stored) d.id], ['a', 'b']);
      expect(stored.every((d) => d.syncedAt == t0), isTrue);
    });

    test(
      'admite más documentos que el límite de parámetros de SQLite',
      () async {
        // SQLite admite como mucho 32 766 parámetros por consulta.
        final many = [
          for (var i = 0; i < 33000; i++) doc('d${'$i'.padLeft(5, '0')}'),
        ];
        await cache.replaceCollection(_members, 'f1', many, t0);
        await cache.replaceCollection(_members, 'f1', many.sublist(500), t1);

        final stored = await ids(_members);
        expect(stored, hasLength(32500));
        expect(stored.first, 'd00500');
      },
    );
  });

  test('upsert inserta y actualiza un documento', () async {
    await cache.upsert(_members, 'f1', doc('a'), t0);
    await cache.upsert(_members, 'f1', doc('a', {'role': 'owner'}), t1);

    final stored = (await cache.watchDoc(_members, 'a').first)!;
    expect(stored.data, {'role': 'owner'});
    expect(stored.syncedAt, t1);
    expect(await ids(_members), ['a']);
  });

  test('upsert con datos que no son JSON falla de forma asíncrona', () async {
    await cache.upsert(_members, 'f1', doc('a'), t0);

    final upserted = cache.upsert(
      _members,
      'f1',
      doc('a', {'raro': Object()}),
      t1,
    );
    await expectLater(upserted, throwsUnsupportedError);

    final stored = (await cache.watchDoc(_members, 'a').first)!;
    expect(stored.data, {'role': 'member'});
    expect(stored.syncedAt, t0);
  });

  test('remove borra solo el documento indicado', () async {
    await cache.replaceCollection(_members, 'f1', [doc('a'), doc('b')], t0);
    await cache.upsert(_otherMembers, 'f2', doc('a'), t0);

    await cache.remove(_members, 'a');

    expect(await ids(_members), ['b']);
    expect(await ids(_otherMembers), ['a']);
  });

  test('clearScope purga todas las colecciones del ámbito', () async {
    await cache.replaceCollection(_members, 'f1', [doc('a')], t0);
    await cache.replaceCollection(_geofences, 'f1', [doc('g1')], t0);
    await cache.replaceCollection(_otherMembers, 'f2', [doc('a')], t0);
    await cache.upsert(_memberships, DocumentCache.userScope, doc('f1'), t0);

    await cache.clearScope('f1');

    expect(await ids(_members), isEmpty);
    expect(await ids(_geofences), isEmpty);
    expect(await ids(_otherMembers), ['a']);
    expect(await ids(_memberships), ['f1']);

    await cache.clearScope(DocumentCache.userScope);
    expect(await ids(_memberships), isEmpty);
    expect(await ids(_otherMembers), ['a']);
  });

  test(
    'la purga no deja los datos borrados en el archivo de la base',
    () async {
      // En un archivo real, SQLite conserva el contenido borrado en páginas
      // libres salvo con `secure_delete` (amenaza 10: salir del grupo).
      const marker = 'marca-sintetica-de-ubicacion';
      final dir = Directory.systemTemp.createTempSync('nexo_cache_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/cache.sqlite');
      final onDisk = AppDatabase(NativeDatabase(file));
      final diskCache = DriftDocumentCache(onDisk);
      await diskCache.replaceCollection('families/f1/locations', 'f1', [
        doc('u1', {'nota': marker}),
      ], t0);
      await diskCache.upsert(_otherMembers, 'f2', doc('a'), t0);

      await diskCache.clearScope('f1');
      await onDisk.close();

      final content = String.fromCharCodes(file.readAsBytesSync());
      expect(
        content.contains(marker),
        isFalse,
        reason: 'el archivo conserva el documento purgado',
      );
      // Lo que no se purgó sigue intacto.
      expect(content, contains(_otherMembers));
    },
  );

  test('clearAll vacía la caché', () async {
    await cache.replaceCollection(_members, 'f1', [doc('a')], t0);
    await cache.upsert(_memberships, DocumentCache.userScope, doc('f1'), t0);

    await cache.clearAll();

    expect(await ids(_members), isEmpty);
    expect(await ids(_memberships), isEmpty);
  });

  test('watchCollection emite cada cambio de la colección', () async {
    final emitted = <List<String>>[];
    final sub = cache
        .watchCollection(_members)
        .listen((list) => emitted.add([for (final d in list) d.id]));
    await pumpEventQueue();

    await cache.replaceCollection(_members, 'f1', [doc('b'), doc('a')], t0);
    await pumpEventQueue();
    await cache.upsert(_members, 'f1', doc('c'), t1);
    await pumpEventQueue();
    await cache.remove(_members, 'a');
    await pumpEventQueue();
    await cache.clearScope('f1');
    await pumpEventQueue();
    await sub.cancel();

    expect(emitted, [
      <String>[],
      ['a', 'b'],
      ['a', 'b', 'c'],
      ['b', 'c'],
      <String>[],
    ]);
  });

  test('watchDoc emite altas, cambios y bajas del documento', () async {
    final emitted = <Json?>[];
    final sub = cache
        .watchDoc(_members, 'a')
        .listen((d) => emitted.add(d?.data));
    await pumpEventQueue();

    await cache.upsert(_members, 'f1', doc('a', {'v': 1}), t0);
    await pumpEventQueue();
    await cache.upsert(_members, 'f1', doc('a', {'v': 2}), t1);
    await pumpEventQueue();
    await cache.remove(_members, 'a');
    await pumpEventQueue();
    await sub.cancel();

    expect(emitted, [
      null,
      {'v': 1},
      {'v': 2},
      null,
    ]);
  });
}
