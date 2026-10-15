import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/family/presentation/family_actions.dart';
import 'package:nexo_familia/features/settings/domain/preferences.dart';

import '../../../helpers/fakes.dart';
import 'family_test_harness.dart';

/// Caso de uso de la interfaz: operaciones de familia + familia activa.
void main() {
  late FakeFamilyRepository repo;
  late FakePreferencesRepository prefs;
  late MemoryLogSink logs;
  late FamilyActions actions;

  setUp(() {
    repo = FakeFamilyRepository();
    prefs = FakePreferencesRepository();
    logs = MemoryLogSink();
    actions = FamilyActions(
      families: repo,
      preferences: prefs,
      logger: SafeLogger(sink: logs, clock: FakeClock(testNow)),
    );
  });

  test('crear recorta el nombre y activa la nueva familia', () async {
    final result = await actions.createFamily('  Familia Nueva  ');
    expect(result.isOk, isTrue);
    expect(repo.createCalls, ['Familia Nueva']);
    expect(prefs.prefs.value.activeFamilyId, 'fam-new');
  });

  test(
    'si crear falla no cambia la familia activa y registra solo el código',
    () async {
      repo.create.result = const Err(
        Failure(FailureKind.rateLimited, 'too-many-families'),
      );
      final result = await actions.createFamily('Familia Secreta');
      expect(result.failureOrNull?.code, 'too-many-families');
      expect(prefs.prefs.value.activeFamilyId, isNull);
      final entry = logs.entries.single;
      expect(entry.fields['code'], 'too-many-families');
      expect(entry.fields['operation'], 'createFamily');
      expect(entry.toString(), isNot(contains('Secreta')));
    },
  );

  test('unirse activa la familia devuelta por el servidor', () async {
    final result = await actions.joinWithCode(' abcde-fghjk ');
    expect(result.valueOrNull, 'fam-joined');
    expect(repo.acceptCalls, ['abcde-fghjk']);
    expect(prefs.prefs.value.activeFamilyId, 'fam-joined');
  });

  test('un código rechazado no cambia la familia activa', () async {
    repo.accept.result = const Err(Failure.notFound('invitation-invalid'));
    await actions.joinWithCode('ABCDE-FGHJK');
    expect(prefs.prefs.value.activeFamilyId, isNull);
  });

  test('salir olvida la familia activa si era esa', () async {
    await prefs.update((p) => p.copyWith(activeFamilyId: () => familyId));
    expect((await actions.leave(familyId)).isOk, isTrue);
    expect(repo.leaveCalls, [familyId]);
    expect(prefs.prefs.value.activeFamilyId, isNull);
  });

  test('salir de otra familia conserva la activa', () async {
    await prefs.update((p) => p.copyWith(activeFamilyId: () => 'otra'));
    await actions.leave(familyId);
    expect(prefs.prefs.value.activeFamilyId, 'otra');
  });

  test('si salir falla, la familia activa no cambia', () async {
    await prefs.update((p) => p.copyWith(activeFamilyId: () => familyId));
    repo.leave.result = const Err(Failure.network());
    final result = await actions.leave(familyId);
    expect(result.failureOrNull, const Failure.network());
    expect(prefs.prefs.value.activeFamilyId, familyId);
  });

  test('quitar a un integrante delega en el repositorio', () async {
    await actions.removeMember(familyId, 'luis');
    expect(repo.removeCalls, [(familyId, 'luis')]);
  });

  test('cambiar de familia guarda la preferencia', () async {
    expect((await actions.switchTo('fam-2')).isOk, isTrue);
    expect(prefs.prefs.value.activeFamilyId, 'fam-2');
  });

  test('un fallo al guardar preferencias se devuelve como Err', () async {
    prefs.failWith = StateError('disco lleno');
    final result = await actions.switchTo('fam-2');
    expect(result.failureOrNull?.code, 'preferences-write');
    expect(prefs.prefs.value, isA<AppPreferences>());
  });

  test(
    'si guardar la preferencia falla tras crear, la creación sigue Ok',
    () async {
      prefs.failWith = StateError('disco lleno');
      final result = await actions.createFamily('Familia');
      expect(result.isOk, isTrue);
    },
  );
}
