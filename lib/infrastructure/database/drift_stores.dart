import 'package:drift/drift.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/document_cache.dart';
import 'package:nexo_familia/infrastructure/sync/outbox.dart';

/// [OutboxStore] sobre SQLite.
final class DriftOutboxStore implements OutboxStore {
  new(this._db);

  final AppDatabase _db;

  $OutboxOperationsTable get _t => _db.outboxOperations;

  static int _millis(DateTime value) => const UtcMillisConverter().toSql(value);

  /// `async`: un payload que no es JSON falla en el `Future`, no al llamar.
  @override
  Future<void> enqueue(OutboxEntry entry) async {
    await _db
        .into(_t)
        .insert(
          OutboxOperationsCompanion.insert(
            id: entry.id,
            kind: entry.kind,
            familyId: entry.familyId,
            payload: DocumentCodec.encode(entry.payload),
            priority: Value(entry.priority),
            status: entry.status.name,
            attempts: Value(entry.attempts),
            nextAttemptAt: Value(entry.nextAttemptAt),
            lastErrorCode: Value(entry.lastErrorCode),
            createdAt: entry.createdAt,
            updatedAt: entry.createdAt,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  @override
  Future<List<OutboxEntry>> due(DateTime now) async {
    final query = _db.select(_t)
      ..where(
        (o) =>
            o.status.equals(OutboxStatus.pending.name) &
            (o.nextAttemptAt.isNull() |
                o.nextAttemptAt.isSmallerOrEqualValue(_millis(now))),
      )
      ..orderBy([
        (o) => OrderingTerm.desc(o.priority),
        (o) => OrderingTerm.asc(o.createdAt),
        // Desempate estable: orden de inserción en este dispositivo.
        (o) => OrderingTerm.asc(o.rowId),
      ]);
    return (await query.get()).map(_toEntry).toList();
  }

  @override
  Future<DateTime?> nextAttemptAt() async {
    // Sin `nextAttemptAt` = vencida desde la época Unix (siempre pasada).
    final next = coalesce([_t.nextAttemptAt, const Constant(0)]).min();
    final row =
        await (_db.selectOnly(_t)
              ..addColumns([next])
              ..where(_t.status.equals(OutboxStatus.pending.name)))
            .getSingle();
    final millis = row.read(next);
    return millis == null ? null : const UtcMillisConverter().fromSql(millis);
  }

  Future<void> _update(String id, OutboxOperationsCompanion values) =>
      (_db.update(_t)..where((o) => o.id.equals(id))).write(values);

  @override
  Future<void> markSending(String id, DateTime now) => _update(
    id,
    OutboxOperationsCompanion(
      status: Value(OutboxStatus.sending.name),
      updatedAt: Value(now),
    ),
  );

  @override
  Future<void> remove(String id) =>
      (_db.delete(_t)..where((o) => o.id.equals(id))).go();

  @override
  Future<void> scheduleRetry(
    String id, {
    required int attempts,
    required DateTime nextAttemptAt,
    required String errorCode,
    required DateTime now,
  }) => _update(
    id,
    OutboxOperationsCompanion(
      status: Value(OutboxStatus.pending.name),
      attempts: Value(attempts),
      nextAttemptAt: Value(nextAttemptAt),
      lastErrorCode: Value(errorCode),
      updatedAt: Value(now),
    ),
  );

  @override
  Future<void> markFailed(
    String id, {
    required String errorCode,
    required DateTime now,
  }) => _update(
    id,
    OutboxOperationsCompanion(
      status: Value(OutboxStatus.failed.name),
      lastErrorCode: Value(errorCode),
      updatedAt: Value(now),
    ),
  );

  @override
  Future<void> requeue(String id, DateTime now) => _update(
    id,
    OutboxOperationsCompanion(
      status: Value(OutboxStatus.pending.name),
      nextAttemptAt: const Value(null),
      updatedAt: Value(now),
    ),
  );

  @override
  Future<void> recoverInterrupted(DateTime now) =>
      (_db.update(
        _t,
      )..where((o) => o.status.equals(OutboxStatus.sending.name))).write(
        OutboxOperationsCompanion(
          status: Value(OutboxStatus.pending.name),
          updatedAt: Value(now),
        ),
      );

  @override
  Stream<List<OutboxEntry>> watch({String? kind, String? familyId}) {
    final query = _db.select(_t)
      ..where(
        (o) =>
            (kind == null ? const Constant(true) : o.kind.equals(kind)) &
            (familyId == null
                ? const Constant(true)
                : o.familyId.equals(familyId)),
      )
      ..orderBy([(o) => OrderingTerm.asc(o.createdAt)]);
    return query.watch().map((rows) => rows.map(_toEntry).toList());
  }

  @override
  Future<OutboxEntry?> find(String id) async {
    final row = await (_db.select(
      _t,
    )..where((o) => o.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toEntry(row);
  }

  static OutboxEntry _toEntry(OutboxOperation row) => OutboxEntry(
    id: row.id,
    kind: row.kind,
    familyId: row.familyId,
    payload: DocumentCodec.decode(row.payload),
    priority: row.priority,
    status: OutboxStatus.values.byName(row.status),
    attempts: row.attempts,
    nextAttemptAt: row.nextAttemptAt,
    lastErrorCode: row.lastErrorCode,
    createdAt: row.createdAt,
  );
}

/// [DocumentCache] sobre SQLite.
final class DriftDocumentCache implements DocumentCache {
  new(this._db);

  final AppDatabase _db;

  $CachedDocumentsTable get _t => _db.cachedDocuments;

  /// Documentos de la colección ordenados por id (orden estable).
  @override
  Stream<List<CachedDoc>> watchCollection(String collection) =>
      (_db.select(_t)
            ..where((d) => d.collection.equals(collection))
            ..orderBy([(d) => OrderingTerm.asc(d.docId)]))
          .watch()
          .map((rows) => rows.map(_toDoc).toList());

  @override
  Stream<CachedDoc?> watchDoc(String collection, String docId) =>
      (_db.select(_t)..where(
            (d) => d.collection.equals(collection) & d.docId.equals(docId),
          ))
          .watchSingleOrNull()
          .map((row) => row == null ? null : _toDoc(row));

  @override
  Future<void> replaceCollection(
    String collection,
    String scope,
    List<RemoteDoc> docs,
    DateTime syncedAt,
  ) => _db.transaction(() async {
    // Borrar y reinsertar dentro de la transacción: los observadores solo
    // ven el resultado final y no hay un `NOT IN` con un parámetro por
    // documento (SQLite limita el número de parámetros).
    final rows = [
      for (final doc in docs) _companion(collection, scope, doc, syncedAt),
    ];
    await (_db.delete(_t)..where((d) => d.collection.equals(collection))).go();
    await _db.batch(
      (b) => b.insertAll(_t, rows, mode: InsertMode.insertOrReplace),
    );
  });

  /// `async`: datos que no son JSON fallan en el `Future`, no al llamar.
  @override
  Future<void> upsert(
    String collection,
    String scope,
    RemoteDoc doc,
    DateTime syncedAt,
  ) async {
    await _db
        .into(_t)
        .insertOnConflictUpdate(_companion(collection, scope, doc, syncedAt));
  }

  @override
  Future<void> remove(String collection, String docId) =>
      (_db.delete(_t)..where(
            (d) => d.collection.equals(collection) & d.docId.equals(docId),
          ))
          .go();

  @override
  Future<void> clearScope(String scope) =>
      (_db.delete(_t)..where((d) => d.familyId.equals(scope))).go();

  @override
  Future<Set<String>> scopes() async {
    final query = _db.selectOnly(_t, distinct: true)..addColumns([_t.familyId]);
    final rows = await query.get();
    return {for (final row in rows) row.read(_t.familyId)!};
  }

  @override
  Future<void> clearAll() => _db.delete(_t).go();

  static CachedDocumentsCompanion _companion(
    String collection,
    String scope,
    RemoteDoc doc,
    DateTime syncedAt,
  ) => CachedDocumentsCompanion.insert(
    collection: collection,
    docId: doc.id,
    familyId: scope,
    data: DocumentCodec.encode(doc.data),
    syncedAt: syncedAt,
  );

  static CachedDoc _toDoc(CachedDocument row) =>
      CachedDoc(row.docId, DocumentCodec.decode(row.data), row.syncedAt);
}
