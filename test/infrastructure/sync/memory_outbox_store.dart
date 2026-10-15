import 'dart:async';

import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/document_cache.dart';
import 'package:nexo_familia/infrastructure/sync/outbox.dart';

/// [OutboxStore] en memoria con la misma semántica que `DriftOutboxStore`:
/// enqueue idempotente, `due` por prioridad, antigüedad y orden de
/// inserción, entradas sin `nextAttemptAt` contadas como vencidas y payload
/// serializado con [DocumentCodec] (rechaza lo que no es JSON y guarda una
/// copia).
final class MemoryOutboxStore implements OutboxStore {
  /// Conserva el orden de inserción (desempate de `due`).
  final Map<String, OutboxEntry> _entries = {};
  final StreamController<void> _changes = StreamController.broadcast(
    sync: true,
  );

  /// Si no es null, `due` lanza este error (simula un fallo del almacén).
  Error? dueError;

  @override
  Future<void> enqueue(OutboxEntry entry) async {
    final payload = DocumentCodec.decode(DocumentCodec.encode(entry.payload));
    if (_entries.containsKey(entry.id)) return;
    _entries[entry.id] = _copy(entry, payload: payload);
    _changes.add(null);
  }

  bool _isDue(OutboxEntry e, DateTime now) =>
      e.status == OutboxStatus.pending &&
      (e.nextAttemptAt == null || !e.nextAttemptAt!.isAfter(now));

  @override
  Future<List<OutboxEntry>> due(DateTime now) async {
    final error = dueError;
    if (error != null) throw error;
    final order = _entries.keys.toList();
    return [
      for (final e in _entries.values)
        if (_isDue(e, now)) e,
    ]..sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      if (byPriority != 0) return byPriority;
      final byAge = a.createdAt.compareTo(b.createdAt);
      if (byAge != 0) return byAge;
      return order.indexOf(a.id).compareTo(order.indexOf(b.id));
    });
  }

  @override
  Future<DateTime?> nextAttemptAt() async {
    DateTime? next;
    for (final e in _entries.values) {
      if (e.status != OutboxStatus.pending) continue;
      // Igual que en SQLite: sin fecha = vencida desde la época Unix.
      final at = e.nextAttemptAt ?? DateTime.utc(1970);
      if (next == null || at.isBefore(next)) next = at;
    }
    return next;
  }

  void _update(String id, OutboxEntry Function(OutboxEntry current) change) {
    final current = _entries[id];
    if (current == null) return;
    _entries[id] = change(current);
    _changes.add(null);
  }

  @override
  Future<void> markSending(String id, DateTime now) async =>
      _update(id, (e) => _copy(e, status: OutboxStatus.sending));

  @override
  Future<void> remove(String id) async {
    if (_entries.remove(id) != null) _changes.add(null);
  }

  @override
  Future<void> scheduleRetry(
    String id, {
    required int attempts,
    required DateTime nextAttemptAt,
    required String errorCode,
    required DateTime now,
  }) async => _update(
    id,
    (e) => _copy(
      e,
      status: OutboxStatus.pending,
      attempts: attempts,
      nextAttemptAt: () => nextAttemptAt,
      lastErrorCode: errorCode,
    ),
  );

  @override
  Future<void> markFailed(
    String id, {
    required String errorCode,
    required DateTime now,
  }) async => _update(
    id,
    (e) => _copy(e, status: OutboxStatus.failed, lastErrorCode: errorCode),
  );

  @override
  Future<void> requeue(String id, DateTime now) async => _update(
    id,
    (e) => _copy(e, status: OutboxStatus.pending, nextAttemptAt: () => null),
  );

  @override
  Future<void> recoverInterrupted(DateTime now) async {
    for (final e in _entries.values.toList()) {
      if (e.status == OutboxStatus.sending) {
        _update(e.id, (e) => _copy(e, status: OutboxStatus.pending));
      }
    }
  }

  @override
  Stream<List<OutboxEntry>> watch({String? kind, String? familyId}) {
    List<OutboxEntry> read() => [
      for (final e in _entries.values)
        if ((kind == null || e.kind == kind) &&
            (familyId == null || e.familyId == familyId))
          e,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    late final StreamController<List<OutboxEntry>> controller;
    StreamSubscription<void>? changes;
    controller = StreamController(
      onListen: () {
        controller.add(read());
        changes = _changes.stream.listen((_) => controller.add(read()));
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<OutboxEntry?> find(String id) async => _entries[id];

  Future<void> dispose() => _changes.close();

  static OutboxEntry _copy(
    OutboxEntry e, {
    Json? payload,
    OutboxStatus? status,
    int? attempts,
    DateTime? Function()? nextAttemptAt,
    String? lastErrorCode,
  }) => OutboxEntry(
    id: e.id,
    kind: e.kind,
    familyId: e.familyId,
    payload: payload ?? e.payload,
    createdAt: e.createdAt,
    priority: e.priority,
    status: status ?? e.status,
    attempts: attempts ?? e.attempts,
    nextAttemptAt: nextAttemptAt == null ? e.nextAttemptAt : nextAttemptAt(),
    lastErrorCode: lastErrorCode ?? e.lastErrorCode,
  );
}
