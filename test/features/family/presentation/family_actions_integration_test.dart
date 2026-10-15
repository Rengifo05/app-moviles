import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/features/family/data/family_repository_impl.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_actions.dart';
import 'package:nexo_familia/features/family/presentation/family_text.dart';
import 'package:nexo_familia/features/settings/data/drift_preferences_repository.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';
import 'package:nexo_familia/infrastructure/database/drift_stores.dart';
import 'package:nexo_familia/infrastructure/demo/demo_functions.dart';
import 'package:nexo_familia/infrastructure/demo/in_memory_remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/document_cache.dart';
import 'package:nexo_familia/infrastructure/sync/remote_mirror.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

import '../../../helpers/fakes.dart';
import 'family_test_harness.dart';

/// Integración de las acciones de la interfaz con el backend de
/// demostración: repositorio real + funciones + espejo + caché Drift.
void main() {
  final l10n = lookupAppLocalizations(const Locale('es'));
  late FakeClock clock;
  late InMemoryRemoteStore store;
  late AppDatabase db;
  late DriftDocumentCache cache;
  late RemoteMirror mirror;
  late MemoryLogSink logs;
  String? uid;

  FamilyRepositoryImpl repo() => FamilyRepositoryImpl(
    functions: DemoFunctionsClient(
      store: store,
      currentUid: () => uid,
      clock: clock,
      random: math.Random(3),
    ),
    cache: cache,
    currentUid: () => uid,
  );

  FamilyActions actionsWith(FakePreferencesRepository prefs) => FamilyActions(
    families: repo(),
    preferences: prefs,
    logger: SafeLogger(sink: logs, clock: clock),
  );

  setUp(() {
    clock = FakeClock(testNow);
    store = InMemoryRemoteStore(clock: clock);
    db = AppDatabase(NativeDatabase.memory());
    cache = DriftDocumentCache(db);
    logs = MemoryLogSink();
    mirror = RemoteMirror(
      remote: store,
      cache: cache,
      clock: clock,
      logger: SafeLogger(sink: logs, clock: clock),
    );
    store
      ..serverWrite('users/ana', {'displayName': 'Ana'})
      ..serverWrite('users/luis', {'displayName': 'Luis'});
  });

  tearDown(() async {
    await mirror.dispose();
    await db.close();
  });

  test('crear activa la familia y aparece en "mis familias"', () async {
    uid = 'ana';
    final prefs = FakePreferencesRepository();
    mirror.start(DocumentCache.userScope, [
      MirrorSpec(BackendPaths.memberships('ana')),
    ]);
    final created = await actionsWith(prefs).createFamily('  Familia Gómez ');
    final id = created.valueOrNull!.id;
    expect(prefs.prefs.value.activeFamilyId, id);
    final families = await repo().watchMyFamilies().firstWhere(
      (f) => f.isNotEmpty,
    );
    expect(families.single.name, 'Familia Gómez');
    expect(families.single.myRole, MemberRole.owner);
  });

  test('las preferencias reales (Drift) guardan la familia activa', () async {
    uid = 'ana';
    final prefsRepo = DriftPreferencesRepository(db);
    final actions = FamilyActions(
      families: repo(),
      preferences: prefsRepo,
      logger: SafeLogger(sink: logs, clock: clock),
    );
    final id = (await actions.createFamily('Familia')).valueOrNull!.id;
    expect((await prefsRepo.read()).activeFamilyId, id);
  });

  test(
    'invitar, unirse con el código escrito a mano y no reutilizarlo',
    () async {
      uid = 'ana';
      final anaPrefs = FakePreferencesRepository();
      final ana = actionsWith(anaPrefs);
      final familyId = (await ana.createFamily('Familia')).valueOrNull!.id;
      final invitation = (await ana.createInvitation(familyId)).valueOrNull!;
      expect(
        invitation.expiresAt.difference(clock.now()),
        const Duration(hours: 48),
      );
      expect(
        inviteExpiresText(l10n, invitation.expiresAt.difference(clock.now())),
        'Vence en 48 h',
      );

      uid = 'luis';
      final luisPrefs = FakePreferencesRepository();
      final luis = actionsWith(luisPrefs);
      final typed =
          ' ${FamilyRules.formatCode(invitation.code).toLowerCase()} ';
      expect((await luis.joinWithCode(typed)).valueOrNull, familyId);
      expect(luisPrefs.prefs.value.activeFamilyId, familyId);

      // Un solo uso: el mismo código ya no sirve, con el mensaje genérico.
      store.serverWrite('users/sofia', {'displayName': 'Sofía'});
      uid = 'sofia';
      final reused = await actionsWith(FakePreferencesRepository())
          .joinWithCode(invitation.code);
      expect(
        familyFailureMessage(l10n, reused.failureOrNull!, FamilyOperation.join),
        'El código no es válido o ya venció. Pide uno nuevo a quien te '
        'invitó.',
      );
    },
  );

  test('un integrante sin permisos no puede invitar ni quitar', () async {
    uid = 'ana';
    final ana = actionsWith(FakePreferencesRepository());
    final familyId = (await ana.createFamily('Familia')).valueOrNull!.id;
    final code = (await ana.createInvitation(familyId)).valueOrNull!.code;
    uid = 'luis';
    final luis = actionsWith(FakePreferencesRepository());
    await luis.joinWithCode(code);

    final invite = await luis.createInvitation(familyId);
    expect(
      familyFailureMessage(l10n, invite.failureOrNull!, FamilyOperation.invite),
      'Solo quienes administran el grupo pueden invitar.',
    );
    final remove = await luis.removeMember(familyId, 'ana');
    expect(
      familyFailureMessage(l10n, remove.failureOrNull!, FamilyOperation.remove),
      l10n.familyErrorNotAllowedRemove,
    );
  });

  test(
    'salir borra la membresía, purga la caché y olvida la familia activa',
    () async {
      uid = 'ana';
      final ana = actionsWith(FakePreferencesRepository());
      final familyId = (await ana.createFamily('Familia')).valueOrNull!.id;
      final code = (await ana.createInvitation(familyId)).valueOrNull!.code;
      uid = 'luis';
      final luisPrefs = FakePreferencesRepository();
      final luis = actionsWith(luisPrefs);
      await luis.joinWithCode(code);
      expect(luisPrefs.prefs.value.activeFamilyId, familyId);

      expect((await luis.leave(familyId)).isOk, isTrue);
      expect(luisPrefs.prefs.value.activeFamilyId, isNull);
      expect(store.snapshot['users/luis/memberships/$familyId'], isNull);
      expect(store.snapshot['families/$familyId/members/luis'], isNull);
      expect(await repo().watchMembers(familyId).first, isEmpty);
    },
  );

  test('el owner quita a un integrante', () async {
    uid = 'ana';
    final ana = actionsWith(FakePreferencesRepository());
    final familyId = (await ana.createFamily('Familia')).valueOrNull!.id;
    final code = (await ana.createInvitation(familyId)).valueOrNull!.code;
    uid = 'luis';
    await actionsWith(FakePreferencesRepository()).joinWithCode(code);

    uid = 'ana';
    expect((await ana.removeMember(familyId, 'luis')).isOk, isTrue);
    expect(store.snapshot['families/$familyId/members/luis'], isNull);
    // El owner no puede quitarse a sí mismo (para eso está salir).
    final self = await ana.removeMember(familyId, 'ana');
    expect(self.failureOrNull?.code, 'not-allowed');
  });
}
