import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/family/domain/family.dart';

import 'family_test_harness.dart';

void main() {
  FamilyTestEnv envAs(MemberRole myRole, {FakeLocationRepository? locations}) {
    final members = [
      familyMember('ana', 'Ana', myRole),
      familyMember(
        'marta',
        'Marta Ruiz',
        myRole == MemberRole.owner ? MemberRole.admin : MemberRole.owner,
      ),
      familyMember('pedro', 'Pedro', MemberRole.admin),
      familyMember('luis', 'Luis', MemberRole.member),
    ];
    return FamilyTestEnv(
      families: FakeFamilyRepository(
        families: [familyGroup(role: myRole)],
        members: {familyId: members},
      ),
      locations: locations,
    );
  }

  Future<FamilyTestEnv> open(
    WidgetTester tester,
    String uid, [
    FamilyTestEnv? env,
  ]) async {
    final e = env ?? envAs(MemberRole.owner);
    // Se entra desde la lista, como en la app, para poder volver.
    final router = await pumpFamilyApp(
      tester,
      e,
      initialLocation: AppRoutes.family,
    );
    unawaited(router.push(AppRoutes.member(uid)));
    await pumpFrames(tester);
    return e;
  }

  testWidgets('muestra nombre, rol y desde cuándo es integrante', (
    tester,
  ) async {
    await open(tester, 'luis');
    expect(find.text('Luis'), findsOneWidget);
    expect(find.text('Integrante'), findsOneWidget);
    expect(
      find.text('En el grupo desde el 2 de marzo de 2026'),
      findsOneWidget,
    );
  });

  testWidgets('ubicación reciente: "Ubicación actualizada hace X"', (
    tester,
  ) async {
    final env = envAs(
      MemberRole.owner,
      locations: FakeLocationRepository([
        sampleLocation('luis', age: const Duration(minutes: 5)),
      ]),
    );
    await open(tester, 'luis', env);
    expect(find.text('Ubicación actualizada hace 5 min'), findsOneWidget);
    expect(
      find.text(
        'La ubicación la reporta el dispositivo y puede no ser exacta.',
      ),
      findsOneWidget,
    );
    // Nunca afirma que la persona esté bien o a salvo.
    expect(find.textContaining('salvo'), findsNothing);
    expect(find.textContaining('segur'), findsNothing);
  });

  testWidgets('la frescura se recalcula con el paso del tiempo', (
    tester,
  ) async {
    final env = envAs(
      MemberRole.owner,
      locations: FakeLocationRepository([
        sampleLocation('luis', age: const Duration(minutes: 25)),
      ]),
    );
    await open(tester, 'luis', env);
    expect(find.text('Ubicación actualizada hace 25 min'), findsOneWidget);
    env.clock.advance(const Duration(minutes: 10));
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Sin actualización reciente'), findsOneWidget);
    expect(find.text('Última actualización hace 35 min'), findsOneWidget);
  });

  testWidgets('ubicación antigua: "Sin actualización reciente"', (
    tester,
  ) async {
    final env = envAs(
      MemberRole.owner,
      locations: FakeLocationRepository([
        sampleLocation(
          'luis',
          age: const Duration(hours: 2),
          approximate: true,
        ),
      ]),
    );
    await open(tester, 'luis', env);
    expect(find.text('Sin actualización reciente'), findsOneWidget);
    expect(find.text('Última actualización hace 2 h'), findsOneWidget);
    expect(find.text('Ubicación aproximada (cerca de 1 km)'), findsOneWidget);
  });

  testWidgets('sin ubicación: "No comparte su ubicación"', (tester) async {
    await open(tester, 'luis');
    expect(find.text('No comparte su ubicación'), findsOneWidget);
    expect(find.textContaining('reporta el dispositivo'), findsNothing);
  });

  testWidgets('si no se puede consultar la ubicación, lo dice', (tester) async {
    final locations = FakeLocationRepository()
      ..failure = const Failure.unavailable();
    await open(tester, 'luis', envAs(MemberRole.owner, locations: locations));
    expect(
      find.text('No pudimos consultar el estado de la ubicación.'),
      findsOneWidget,
    );
    expect(find.text('No comparte su ubicación'), findsNothing);
  });

  testWidgets('para uno mismo: "Tú", enlace a privacidad y sin quitar', (
    tester,
  ) async {
    await open(tester, 'ana');
    expect(find.text('Tú'), findsOneWidget);
    expect(find.text('No estás compartiendo tu ubicación'), findsOneWidget);
    expect(find.text('Quitar del grupo'), findsNothing);
    await tester.tap(find.text('Revisar mi privacidad'));
    await pumpFrames(tester);
    expect(find.text('stub:${AppRoutes.privacy}'), findsOneWidget);
  });

  group('quitar del grupo', () {
    testWidgets('el owner puede quitar a un admin y a un member', (
      tester,
    ) async {
      await open(tester, 'pedro');
      expect(find.text('Quitar del grupo'), findsOneWidget);
    });

    testWidgets('un admin no ve la acción para otro admin ni para el owner', (
      tester,
    ) async {
      await open(tester, 'pedro', envAs(MemberRole.admin));
      expect(find.text('Quitar del grupo'), findsNothing);
      await open(tester, 'marta', envAs(MemberRole.admin));
      expect(find.text('Quitar del grupo'), findsNothing);
      await open(tester, 'luis', envAs(MemberRole.admin));
      expect(find.text('Quitar del grupo'), findsOneWidget);
    });

    testWidgets('un member no puede quitar a nadie', (tester) async {
      await open(tester, 'luis', envAs(MemberRole.member));
      expect(find.text('Quitar del grupo'), findsNothing);
    });

    testWidgets('confirmar quita a la persona y vuelve a la lista', (
      tester,
    ) async {
      final env = await open(tester, 'luis');
      await scrollAndTap(tester, find.text('Quitar del grupo'));
      await pumpFrames(tester);
      expect(find.text('¿Quitar a Luis del grupo?'), findsOneWidget);
      expect(find.textContaining('se borrará la ubicación'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Quitar del grupo'),
        ),
      );
      await pumpFrames(tester);
      expect(env.families.removeCalls, [(familyId, 'luis')]);
      expect(find.text('Luis ya no está en el grupo.'), findsOneWidget);
      // De vuelta en la lista de la familia.
      expect(find.text('Integrantes'), findsOneWidget);
    });

    testWidgets('cancelar no quita a nadie', (tester) async {
      final env = await open(tester, 'luis');
      await scrollAndTap(tester, find.text('Quitar del grupo'));
      await pumpFrames(tester);
      await tester.tap(find.text('Cancelar'));
      await pumpFrames(tester);
      expect(env.families.removeCalls, isEmpty);
    });

    testWidgets('si el servidor lo rechaza, explica el motivo', (tester) async {
      final env = envAs(MemberRole.owner);
      env.families.remove.result = const Err(
        Failure.permissionDenied('not-allowed'),
      );
      await open(tester, 'luis', env);
      await scrollAndTap(tester, find.text('Quitar del grupo'));
      await pumpFrames(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Quitar del grupo'),
        ),
      );
      await pumpFrames(tester);
      expect(
        find.text('No tienes permiso para quitar a esta persona del grupo.'),
        findsOneWidget,
      );
      expect(
        find.text('En el grupo desde el 2 de marzo de 2026'),
        findsOneWidget,
      );
    });
  });

  testWidgets('si la persona ya no está en el grupo, lo dice', (tester) async {
    await open(tester, 'desconocido');
    expect(find.text('Esta persona ya no está en el grupo.'), findsOneWidget);
    await tester.tap(find.text('Volver a Familia'));
    await pumpFrames(tester);
    expect(find.text('Integrantes'), findsOneWidget);
  });
}
