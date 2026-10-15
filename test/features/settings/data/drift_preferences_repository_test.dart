import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/features/settings/data/drift_preferences_repository.dart';
import 'package:nexo_familia/features/settings/domain/preferences.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';

void main() {
  late AppDatabase db;
  late DriftPreferencesRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftPreferencesRepository(db);
  });

  tearDown(() => db.close());

  test('sin datos devuelve las preferencias por defecto', () async {
    final prefs = await repo.read();
    expect(prefs.onboardingCompleted, isFalse);
    expect(prefs.activeFamilyId, isNull);
    expect(prefs.hideNotificationDetails, isFalse);
  });

  test('guarda, emite cambios y permite borrar la familia activa', () async {
    final emitted = <AppPreferences>[];
    final sub = repo.watch().listen(emitted.add);

    await repo.update(
      (p) => p.copyWith(
        onboardingCompleted: true,
        activeFamilyId: () => 'fam-1',
        hideNotificationDetails: true,
      ),
    );
    var prefs = await repo.read();
    expect(prefs.onboardingCompleted, isTrue);
    expect(prefs.activeFamilyId, 'fam-1');
    expect(prefs.hideNotificationDetails, isTrue);

    await repo.update((p) => p.copyWith(activeFamilyId: () => null));
    prefs = await repo.read();
    expect(prefs.activeFamilyId, isNull);
    expect(prefs.onboardingCompleted, isTrue);

    await pumpEventQueue();
    expect(emitted.last.activeFamilyId, isNull);
    await sub.cancel();
  });

  test('clear borra todo', () async {
    await repo.update((p) => p.copyWith(onboardingCompleted: true));
    await repo.clear();
    expect((await repo.read()).onboardingCompleted, isFalse);
  });
}
