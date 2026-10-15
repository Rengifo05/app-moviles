import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_state_views.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/settings/domain/preferences.dart';

import 'family_test_harness.dart';

void main() {
  Future<FamilyTestEnv> open(WidgetTester tester, [FamilyTestEnv? env]) async {
    final e = env ?? FamilyTestEnv();
    await pumpFamilyApp(tester, e, initialLocation: AppRoutes.family);
    return e;
  }

  FamilyTestEnv envWithRole(MemberRole role, {int families = 1}) =>
      FamilyTestEnv(
        families: FakeFamilyRepository(
          families: [
            familyGroup(role: role),
            if (families > 1)
              familyGroup(id: 'fam-2', name: 'Casa de la abuela', role: role),
          ],
          members: {familyId: sampleMembers()},
        ),
      );

  testWidgets('lista integrantes con su rol en texto y marca "Tú"', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Familia Gómez'), findsOneWidget);
    expect(find.text('4 integrantes'), findsOneWidget);
    for (final name in ['Ana', 'Marta Ruiz', 'Luis', 'Sofía']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Administra el grupo'), findsOneWidget);
    expect(find.text('Ayuda a administrar'), findsOneWidget);
    expect(find.text('Integrante'), findsNWidgets(2));
    expect(find.text('Tú'), findsOneWidget);
    // "Tú" está en la fila de Ana (el usuario actual).
    final anaTile = find.ancestor(
      of: find.text('Ana'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: anaTile, matching: find.text('Tú')),
      findsOneWidget,
    );
  });

  testWidgets('el owner y los admin ven "Invitar"; los demás no', (
    tester,
  ) async {
    await open(tester, envWithRole(MemberRole.admin));
    expect(find.text('Invitar a alguien'), findsOneWidget);

    await open(tester, envWithRole(MemberRole.member));
    expect(find.text('Invitar a alguien'), findsNothing);
  });

  testWidgets('"Invitar a alguien" abre la pantalla de invitación', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Invitar a alguien'));
    await pumpFrames(tester);
    expect(find.text('Generar código'), findsOneWidget);
  });

  testWidgets('tocar un integrante abre su detalle', (tester) async {
    await open(tester);
    await tester.tap(find.text('Luis'));
    await pumpFrames(tester);
    expect(find.textContaining('En el grupo desde'), findsOneWidget);
  });

  testWidgets('con una sola familia se puede crear o unirse a otra', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Cambiar de familia'));
    await pumpFrames(tester);
    expect(find.text('Unirme a otra con un código'), findsOneWidget);
    await tester.tap(find.text('Crear otra familia'));
    await pumpFrames(tester);
    expect(find.text('Nombre de la familia'), findsOneWidget);
    // Atrás vuelve a la familia actual.
    await tester.tap(find.byType(BackButton));
    await pumpFrames(tester);
    expect(find.text('Invitar a alguien'), findsOneWidget);
  });

  testWidgets('con varias familias se puede cambiar la activa', (tester) async {
    final env = await open(tester, envWithRole(MemberRole.owner, families: 2));
    await tester.tap(find.text('Cambiar de familia'));
    await pumpFrames(tester);
    expect(find.text('Tus familias'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Familia activa')), findsOneWidget);
    await tester.tap(find.text('Casa de la abuela'));
    await pumpFrames(tester);
    expect(env.preferences.prefs.value.activeFamilyId, 'fam-2');
    expect(find.text('Ahora ves Casa de la abuela.'), findsOneWidget);
  });

  group('salir del grupo', () {
    Future<void> openDialog(WidgetTester tester) async {
      await scrollAndTap(tester, find.text('Salir del grupo'));
      await pumpFrames(tester);
    }

    testWidgets('el diálogo explica las consecuencias; cancelar no sale', (
      tester,
    ) async {
      final env = await open(tester, envWithRole(MemberRole.member));
      await openDialog(tester);
      expect(find.text('¿Salir de Familia Gómez?'), findsOneWidget);
      expect(
        find.text('Dejarás de ver la ubicación y la actividad de este grupo.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Dejarás de compartir tu ubicación con el grupo y se borrará la '
          'última que publicaste aquí.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('más antigüedad'), findsNothing);
      await tester.tap(find.text('Cancelar'));
      await pumpFrames(tester);
      expect(env.families.leaveCalls, isEmpty);
    });

    testWidgets('el owner sabe que otra persona pasará a administrar', (
      tester,
    ) async {
      await open(tester);
      await openDialog(tester);
      expect(
        find.text(
          'Como administras el grupo, pasará a administrarlo la persona con '
          'más antigüedad.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('la última persona sabe que el grupo se eliminará', (
      tester,
    ) async {
      final env = FamilyTestEnv(
        families: FakeFamilyRepository(
          families: [familyGroup()],
          members: {
            familyId: [familyMember('ana', 'Ana', MemberRole.owner)],
          },
        ),
      );
      await open(tester, env);
      await openDialog(tester);
      expect(
        find.text(
          'Eres la única persona del grupo, así que el grupo se eliminará.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('confirmar sale, olvida la familia activa y lo confirma', (
      tester,
    ) async {
      final env = FamilyTestEnv(
        preferences: FakePreferencesRepository(
          const AppPreferences(
            onboardingCompleted: true,
            activeFamilyId: familyId,
          ),
        ),
      );
      await open(tester, env);
      await openDialog(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Salir del grupo'),
        ),
      );
      await pumpFrames(tester);
      expect(env.families.leaveCalls, [familyId]);
      expect(env.preferences.prefs.value.activeFamilyId, isNull);
      expect(find.text('Saliste de Familia Gómez.'), findsOneWidget);
    });

    testWidgets('si falla, lo explica y no afirma haber salido', (
      tester,
    ) async {
      final env = FamilyTestEnv();
      env.families.leave.result = const Err(Failure.network());
      await open(tester, env);
      await openDialog(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Salir del grupo'),
        ),
      );
      await pumpFrames(tester);
      expect(
        find.text('No hay conexión. Revisa tu red e inténtalo de nuevo.'),
        findsOneWidget,
      );
      expect(find.textContaining('Saliste'), findsNothing);
    });
  });

  testWidgets('sin conexión muestra el aviso y los datos guardados', (
    tester,
  ) async {
    await open(tester, FamilyTestEnv(syncStatus: SyncStatus.offline));
    expect(find.byType(NxBanner), findsOneWidget);
    expect(
      find.text('Sin conexión. Mostramos los últimos datos guardados.'),
      findsOneWidget,
    );
    expect(find.text('Luis'), findsOneWidget);
  });

  testWidgets('mientras carga muestra un indicador accesible', (tester) async {
    final env = FamilyTestEnv();
    env.families.neverLoads.add(familyId);
    await open(tester, env);
    expect(find.byType(NxLoadingView), findsOneWidget);
    expect(find.bySemanticsLabel('Cargando…'), findsOneWidget);
  });

  testWidgets('un error se explica y se puede reintentar', (tester) async {
    final env = FamilyTestEnv();
    env.families.failingMembers[familyId] = const Failure.unavailable();
    await open(tester, env);
    expect(
      find.text(
        'El servicio no está disponible en este momento. Inténtalo en unos '
        'minutos.',
      ),
      findsOneWidget,
    );
    env.families.failingMembers.clear();
    await tester.tap(find.text('Reintentar'));
    await pumpFrames(tester);
    expect(find.text('Luis'), findsOneWidget);
  });

  testWidgets('sin integrantes sincronizados muestra un estado vacío', (
    tester,
  ) async {
    final env = FamilyTestEnv(
      families: FakeFamilyRepository(
        families: [familyGroup()],
        members: {familyId: const []},
      ),
    );
    await open(tester, env);
    expect(find.text('Aún no vemos integrantes'), findsOneWidget);
    expect(find.text('Invitar a alguien'), findsOneWidget);
  });

  testWidgets('sin familia activa lo indica', (tester) async {
    await open(tester, FamilyTestEnv(activeFamilyId: null));
    expect(find.text('No tienes una familia activa'), findsOneWidget);
  });

  testWidgets('cada integrante es un destino táctil de al menos 48 dp', (
    tester,
  ) async {
    await open(tester);
    final tile = find.ancestor(
      of: find.text('Luis'),
      matching: find.byType(ListTile),
    );
    expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  testWidgets('al 200 % de texto no se desborda', (tester) async {
    await pumpFamilyApp(
      tester,
      envWithRole(MemberRole.owner, families: 2),
      initialLocation: AppRoutes.family,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Salir del grupo'), 200);
    expect(tester.takeException(), isNull);
  });
}
