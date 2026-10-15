import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';
import 'package:nexo_familia/infrastructure/database/drift_stores.dart';
import 'package:nexo_familia/infrastructure/sync/outbox.dart';

import 'generated/schema.dart';

/// Esquema v1 de la base local (ADR-004). El volcado de referencia está en
/// `schemas/drift_schema_v1.json` y se regenera con:
///
/// ```sh
/// dart run drift_dev schema dump \
///   lib/infrastructure/database/app_database.dart \
///   test/infrastructure/database/schemas/
/// dart run drift_dev schema generate \
///   test/infrastructure/database/schemas/ \
///   test/infrastructure/database/generated/
/// ```
///
/// Al subir `schemaVersion` se vuelca la versión nueva y se añade aquí la
/// prueba de migración desde cada versión anterior.
void main() {
  group('migraciones (drift_dev)', () {
    late SchemaVerifier verifier;

    setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

    test(
      'crear desde cero produce exactamente el esquema v1 volcado',
      () async {
        // onCreate (createAll) con el código actual frente al volcado v1.
        final db = AppDatabase(NativeDatabase.memory());
        await verifier.migrateAndValidate(db, 1);
        await db.close();
      },
    );

    test(
      'una base v1 existente se abre sin cambios y coincide con el código',
      () async {
        final connection = await verifier.startAt(1);
        final db = AppDatabase(connection);
        // Primero frente al código; después, la migración (vacía en v1).
        await db.validateDatabaseSchema();
        await verifier.migrateAndValidate(db, 1);
        await db.close();
      },
    );
  });

  group('esquema v1', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));

    tearDown(() => db.close());

    Future<List<Map<String, Object?>>> tableInfo(String table) async => [
      for (final row
          in await db.customSelect('PRAGMA table_info("$table")').get())
        row.data,
    ];

    test('la versión del esquema es 1', () {
      expect(db.schemaVersion, 1);
    });

    test('createAll crea exactamente las tablas documentadas', () async {
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' ORDER BY name",
          )
          .get();
      expect(
        [for (final r in rows) r.read<String>('name')],
        ['cached_documents', 'key_values', 'outbox_operations'],
      );
      // Ninguna tabla queda sin `rowid`: la bandeja lo usa para desempatar.
      final sql = await db
          .customSelect("SELECT sql FROM sqlite_master WHERE type = 'table'")
          .get();
      for (final r in sql) {
        expect(r.read<String>('sql'), isNot(contains('WITHOUT ROWID')));
      }
    });

    test('las claves primarias son las documentadas', () async {
      Future<List<String>> primaryKey(String table) async {
        final columns = [
          for (final c in await tableInfo(table))
            if ((c['pk']! as int) > 0) c,
        ]..sort((a, b) => (a['pk']! as int).compareTo(b['pk']! as int));
        return [for (final c in columns) c['name']! as String];
      }

      expect(await primaryKey('key_values'), ['key']);
      expect(await primaryKey('outbox_operations'), ['id']);
      expect(await primaryKey('cached_documents'), ['collection', 'doc_id']);
    });

    test('la clave compuesta permite el mismo id en otra colección', () async {
      Future<void> insert(String collection, String docId) =>
          db.customStatement(
            'INSERT INTO cached_documents '
            '(collection, doc_id, family_id, data, synced_at) '
            "VALUES (?, ?, 'f1', '{}', 0)",
            [collection, docId],
          );

      await insert('families/f1/members', 'a');
      await insert('families/f1/geofences', 'a');
      await expectLater(
        insert('families/f1/members', 'a'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('columnas, nulabilidad y valores por defecto de la bandeja', () async {
      final columns = {
        for (final c in await tableInfo('outbox_operations'))
          c['name']! as String: (
            type: c['type'],
            notNull: c['notnull'] == 1,
            defaultValue: c['dflt_value'],
          ),
      };
      expect(columns.keys, [
        'id',
        'kind',
        'family_id',
        'payload',
        'priority',
        'status',
        'attempts',
        'next_attempt_at',
        'last_error_code',
        'created_at',
        'updated_at',
      ]);
      expect(columns['priority'], (
        type: 'INTEGER',
        notNull: true,
        defaultValue: '0',
      ));
      expect(columns['attempts'], (
        type: 'INTEGER',
        notNull: true,
        defaultValue: '0',
      ));
      expect(columns['next_attempt_at']!.notNull, isFalse);
      expect(columns['last_error_code']!.notNull, isFalse);
      for (final name in ['next_attempt_at', 'created_at', 'updated_at']) {
        expect(columns[name]!.type, 'INTEGER', reason: name);
      }
    });

    test('las fechas se guardan como milisegundos UTC', () async {
      final createdAt = DateTime.utc(2026, 1, 1, 12, 0, 0, 345);
      await DriftOutboxStore(db).enqueue(
        OutboxEntry(
          id: 'op-1',
          kind: 'checkIn',
          familyId: 'f1',
          payload: const {},
          createdAt: createdAt,
          nextAttemptAt: createdAt.add(const Duration(milliseconds: 1)),
        ),
      );

      final row = await db
          .customSelect(
            'SELECT created_at, next_attempt_at, updated_at '
            'FROM outbox_operations',
          )
          .getSingle();
      expect(row.read<int>('created_at'), createdAt.millisecondsSinceEpoch);
      expect(row.read<int>('updated_at'), createdAt.millisecondsSinceEpoch);
      expect(
        row.read<int>('next_attempt_at'),
        createdAt.millisecondsSinceEpoch + 1,
      );
    });

    test('UtcMillisConverter conserva el instante y devuelve UTC', () {
      const converter = UtcMillisConverter();
      final local = DateTime(2026, 7, 1, 8, 30, 0, 5);
      final back = converter.fromSql(converter.toSql(local));
      expect(back.isUtc, isTrue);
      expect(back.isAtSameMomentAs(local), isTrue);
      expect(converter.toSql(DateTime.utc(1970)), 0);
    });

    test('activa las claves foráneas al abrir', () async {
      final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(row.read<int>('foreign_keys'), 1);
    });
  });
}
