import 'package:nexo_familia/features/settings/domain/preferences.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';

/// Preferencias locales guardadas en SQLite (tabla clave-valor).
final class DriftPreferencesRepository implements PreferencesRepository {
  new(this._db);

  final AppDatabase _db;

  static const _onboarding = 'onboardingCompleted';
  static const _activeFamily = 'activeFamilyId';
  static const _hideDetails = 'hideNotificationDetails';

  @override
  Stream<AppPreferences> watch() =>
      _db.select(_db.keyValues).watch().map(_fromRows);

  @override
  Future<AppPreferences> read() async =>
      _fromRows(await _db.select(_db.keyValues).get());

  @override
  Future<void> update(AppPreferences Function(AppPreferences) change) =>
      _db.transaction(() async {
        final next = change(await read());
        await _put(_onboarding, next.onboardingCompleted.toString());
        await _put(_hideDetails, next.hideNotificationDetails.toString());
        final active = next.activeFamilyId;
        if (active == null) {
          await (_db.delete(
            _db.keyValues,
          )..where((t) => t.key.equals(_activeFamily))).go();
        } else {
          await _put(_activeFamily, active);
        }
      });

  @override
  Future<void> clear() => _db.delete(_db.keyValues).go();

  Future<void> _put(String key, String value) => _db
      .into(_db.keyValues)
      .insertOnConflictUpdate(
        KeyValuesCompanion.insert(key: key, value: value),
      );

  static AppPreferences _fromRows(List<KeyValue> rows) {
    final map = {for (final row in rows) row.key: row.value};
    return AppPreferences(
      onboardingCompleted: map[_onboarding] == 'true',
      activeFamilyId: map[_activeFamily],
      hideNotificationDetails: map[_hideDetails] == 'true',
    );
  }
}
