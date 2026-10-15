import 'dart:async';

import 'package:drift/native.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';
import 'package:nexo_familia/infrastructure/database/drift_stores.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/outbox.dart';

import 'memory_outbox_store.dart';

/// Implementación de [OutboxStore] sobre la que se repite cada prueba.
abstract class OutboxStoreVariant {
  String get name;

  /// Crea un almacén vacío (en `setUp`).
  OutboxStore open();

  /// Libera lo creado en [open] (en `tearDown`).
  Future<void> close();
}

final class MemoryStoreVariant implements OutboxStoreVariant {
  MemoryOutboxStore? _store;

  @override
  String get name => 'en memoria';

  @override
  MemoryOutboxStore open() => _store = MemoryOutboxStore();

  @override
  Future<void> close() async {
    await _store?.dispose();
  }
}

final class DriftStoreVariant implements OutboxStoreVariant {
  AppDatabase? _db;

  @override
  String get name => 'Drift (SQLite en memoria)';

  @override
  DriftOutboxStore open() {
    final db = _db = AppDatabase(NativeDatabase.memory());
    return DriftOutboxStore(db);
  }

  @override
  Future<void> close() async {
    await _db?.close();
  }
}

List<OutboxStoreVariant> outboxStoreVariants() => [
  MemoryStoreVariant(),
  DriftStoreVariant(),
];

/// UUID v7 sintéticos (los únicos ids que el registro deja pasar).
const String opA = '01890a5d-ac96-774b-bcce-b302099a8001';
const String opB = '01890a5d-ac96-774b-bcce-b302099a8002';
const String opC = '01890a5d-ac96-774b-bcce-b302099a8003';
const String opD = '01890a5d-ac96-774b-bcce-b302099a8004';
const String opE = '01890a5d-ac96-774b-bcce-b302099a8005';

const String familyId = 'fam-prueba';

/// Entrada de bandeja con valores por defecto sintéticos.
OutboxEntry entry(
  String id, {
  required DateTime createdAt,
  String kind = 'checkIn',
  String family = familyId,
  Json payload = const {'note': 'texto de prueba'},
  int priority = 0,
  OutboxStatus status = OutboxStatus.pending,
  int attempts = 0,
  DateTime? nextAttemptAt,
  String? lastErrorCode,
}) => OutboxEntry(
  id: id,
  kind: kind,
  familyId: family,
  payload: payload,
  createdAt: createdAt,
  priority: priority,
  status: status,
  attempts: attempts,
  nextAttemptAt: nextAttemptAt,
  lastErrorCode: lastErrorCode,
);

/// Manejador que registra lo enviado y responde según [respond]
/// (por defecto, éxito).
final class FakeHandler implements OutboxHandler {
  new([this.respond]);

  FutureOr<VoidResult> Function(OutboxEntry entry)? respond;
  final List<OutboxEntry> sent = [];

  List<String> get sentIds => [for (final e in sent) e.id];

  @override
  Future<VoidResult> send(OutboxEntry entry) async {
    sent.add(entry);
    final respond = this.respond;
    return respond == null ? const Ok(null) : await respond(entry);
  }
}
