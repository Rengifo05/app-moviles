import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/features/family/data/family_repository_impl.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';
import 'package:nexo_familia/infrastructure/database/drift_stores.dart';
import 'package:nexo_familia/infrastructure/demo/demo_functions.dart';
import 'package:nexo_familia/infrastructure/demo/in_memory_remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/document_cache.dart';
import 'package:nexo_familia/infrastructure/sync/remote_mirror.dart';

import '../../../helpers/fakes.dart';

/// Integración: repositorio + funciones de demostración + espejo + caché.
void main() {
  late FakeClock clock;
  late InMemoryRemoteStore store;
  late AppDatabase db;
  late DriftDocumentCache cache;
  late RemoteMirror mirror;
  String? uid;

  FamilyRepositoryImpl repoFor() => FamilyRepositoryImpl(
    functions: DemoFunctionsClient(
      store: store,
      currentUid: () => uid,
      clock: clock,
      random: math.Random(7),
    ),
    cache: cache,
    currentUid: () => uid,
  );

  void mirrorUser(String id) => mirror.start(DocumentCache.userScope, [
    MirrorSpec(BackendPaths.memberships(id)),
  ]);

  setUp(() {
    clock = FakeClock();
    store = InMemoryRemoteStore(clock: clock);
    db = AppDatabase(NativeDatabase.memory());
    cache = DriftDocumentCache(db);
    mirror = RemoteMirror(
      remote: store,
      cache: cache,
      clock: clock,
      logger: SafeLogger(sink: MemoryLogSink(), clock: clock),
    );
    store
      ..serverWrite('users/ana', {'displayName': 'Ana'})
      ..serverWrite('users/luis', {'displayName': 'Luis'});
  });

  tearDown(() async {
    await mirror.dispose();
    await db.close();
  });

  test(
    'crear una familia la muestra en "mis familias" vía el espejo',
    () async {
      uid = 'ana';
      final repo = repoFor();
      mirrorUser('ana');
      final created = await repo.createFamily('  Familia Gómez  ');
      expect(created.valueOrNull?.name, 'Familia Gómez');

      final families = await repo.watchMyFamilies().firstWhere(
        (f) => f.isNotEmpty,
      );
      expect(families.single.id, created.valueOrNull!.id);
      expect(families.single.name, 'Familia Gómez');
    },
  );

  test('valida el nombre antes de llamar al servidor', () async {
    uid = 'ana';
    final result = await repoFor().createFamily('   ');
    expect(
      result.failureOrNull,
      const Failure.validation('family-name-required'),
    );
    expect(
      store.snapshot.keys.where((k) => k.startsWith('families/')),
      isEmpty,
    );
  });

  test(
    'invitar y unirse; los integrantes se ordenan por rol y nombre',
    () async {
      uid = 'ana';
      final anaRepo = repoFor();
      final familyId = (await anaRepo.createFamily('Familia')).valueOrNull!.id;
      final invitation = (await anaRepo.createInvitation(familyId))
          .valueOrNull!;
      expect(invitation.expiresAt.isAfter(clock.now()), isTrue);

      uid = 'luis';
      final joined = await repoFor().acceptInvitation(
        FamilyRules.formatCode(invitation.code).toLowerCase(),
      );
      expect(joined.valueOrNull, familyId);

      mirror.start(familyId, [MirrorSpec(BackendPaths.members(familyId))]);
      final members = await repoFor()
          .watchMembers(familyId)
          .firstWhere((m) => m.length == 2);
      expect(members.map((m) => m.displayName), ['Ana', 'Luis']);
      expect(members.first.role, MemberRole.owner);
    },
  );

  test('un código mal formado se rechaza sin consultar al servidor', () async {
    uid = 'luis';
    final result = await repoFor().acceptInvitation('no-es-un-código');
    expect(result.failureOrNull?.code, 'invitation-format');
  });

  test('un código inválido devuelve el error genérico del servidor', () async {
    uid = 'luis';
    final result = await repoFor().acceptInvitation('ABCDE-FGHJK');
    expect(result.failureOrNull?.code, 'invitation-invalid');
  });

  test('salir de la familia purga su copia local', () async {
    uid = 'ana';
    final repo = repoFor();
    final familyId = (await repo.createFamily('Familia')).valueOrNull!.id;
    mirror.start(familyId, [MirrorSpec(BackendPaths.members(familyId))]);
    await repo.watchMembers(familyId).firstWhere((m) => m.isNotEmpty);

    await mirror.stop(familyId);
    expect((await repo.leaveFamily(familyId)).isOk, isTrue);
    expect(await repo.watchMembers(familyId).first, isEmpty);
  });

  test('sin sesión no hay familias ni se puede crear una', () async {
    uid = null;
    final repo = repoFor();
    expect(await repo.watchMyFamilies().first, isEmpty);
    expect(
      (await repo.createFamily('X')).failureOrNull?.kind,
      FailureKind.unauthenticated,
    );
  });
}
