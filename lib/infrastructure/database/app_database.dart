import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// Fechas como milisegundos UTC desde la época Unix.
///
/// El modo por defecto de Drift guarda segundos y lee en hora local: se
/// perdería el orden de operaciones creadas en el mismo segundo y los
/// reintentos se adelantarían hasta un segundo.
final class UtcMillisConverter extends TypeConverter<DateTime, int> {
  const new();

  @override
  DateTime fromSql(int fromDb) =>
      DateTime.fromMillisecondsSinceEpoch(fromDb, isUtc: true);

  @override
  int toSql(DateTime value) => value.millisecondsSinceEpoch;
}

/// Preferencias locales (clave-valor).
class KeyValues extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Bandeja de salida: operaciones remotas creadas en el dispositivo y aún no
/// confirmadas por el servidor (ADR-004).
class OutboxOperations extends Table {
  /// Clave de idempotencia (UUID v7). Es también el id del documento remoto.
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get familyId => text()();

  /// JSON con lo mínimo necesario para enviar la operación.
  TextColumn get payload => text()();

  /// Mayor = antes (el SOS tiene la prioridad más alta).
  IntColumn get priority => integer().withDefault(const Constant(0))();

  /// pending | sending | failed
  TextColumn get status => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptAt =>
      integer().nullable().map(const UtcMillisConverter())();
  TextColumn get lastErrorCode => text().nullable()();
  IntColumn get createdAt => integer().map(const UtcMillisConverter())();
  IntColumn get updatedAt => integer().map(const UtcMillisConverter())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Copia local de documentos remotos de la familia activa. La UI lee de aquí
/// para funcionar sin conexión y mostrar la antigüedad de los datos.
class CachedDocuments extends Table {
  /// Ruta de la colección remota, p. ej. `families/f1/members`.
  TextColumn get collection => text()();
  TextColumn get docId => text()();
  TextColumn get familyId => text()();
  TextColumn get data => text()();

  /// Última vez que este documento llegó del servidor.
  IntColumn get syncedAt => integer().map(const UtcMillisConverter())();

  @override
  Set<Column<Object>> get primaryKey => {collection, docId};
}

@DriftDatabase(tables: [KeyValues, OutboxOperations, CachedDocuments])
class AppDatabase extends _$AppDatabase {
  new(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // Sin esto, lo borrado (caché de una familia que se abandonó,
      // ubicaciones incluidas) sigue en páginas libres del archivo. Es por
      // conexión: se fija en cada apertura.
      await customStatement('PRAGMA secure_delete = ON');
    },
  );
}
