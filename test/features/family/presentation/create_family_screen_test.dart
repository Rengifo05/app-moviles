import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';

import 'family_test_harness.dart';

void main() {
  Future<FamilyTestEnv> open(WidgetTester tester) async {
    final env = FamilyTestEnv(activeFamilyId: null);
    await pumpFamilyApp(tester, env, initialLocation: AppRoutes.createFamily);
    return env;
  }

  Future<void> submit(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextField), name);
    await tester.tap(find.text('Crear familia'));
    await pumpFrames(tester);
  }

  testWidgets('un nombre vacío se explica sin llamar al servidor', (
    tester,
  ) async {
    final env = await open(tester);
    await submit(tester, '   ');
    expect(find.text('Escribe un nombre para la familia.'), findsOneWidget);
    expect(env.families.createCalls, isEmpty);
  });

  testWidgets('crea con el nombre recortado y la activa en preferencias', (
    tester,
  ) async {
    final env = await open(tester);
    await submit(tester, '  Familia Gómez  ');
    expect(env.families.createCalls, ['Familia Gómez']);
    expect(env.preferences.prefs.value.activeFamilyId, 'fam-new');
  });

  testWidgets('si ya tenía una familia, al crear vuelve a la pestaña Familia', (
    tester,
  ) async {
    final env = FamilyTestEnv();
    final router = await pumpFamilyApp(
      tester,
      env,
      initialLocation: AppRoutes.createFamily,
    );
    await submit(tester, 'Familia Gómez');
    expect(router.state.uri.path, AppRoutes.family);
    expect(env.preferences.prefs.value.activeFamilyId, 'fam-new');
  });

  testWidgets('sin familia previa espera al cambio de sesión (sigue ocupado)', (
    tester,
  ) async {
    final env = FamilyTestEnv(
      activeFamilyId: null,
      families: FakeFamilyRepository(),
    );
    final router = await pumpFamilyApp(
      tester,
      env,
      initialLocation: AppRoutes.createFamily,
    );
    await submit(tester, 'Familia Gómez');
    expect(router.state.uri.path, AppRoutes.createFamily);
    expect(tester.widget<NxButton>(find.byType(NxButton)).loading, isTrue);
  });

  testWidgets('mientras crea, el botón muestra progreso y no repite', (
    tester,
  ) async {
    final env = FamilyTestEnv(activeFamilyId: null);
    env.families.create.hold();
    await pumpFamilyApp(tester, env, initialLocation: AppRoutes.createFamily);
    await tester.enterText(find.byType(TextField), 'Familia');
    await tester.tap(find.text('Crear familia'));
    await tester.pump();
    final button = tester.widget<NxButton>(find.byType(NxButton));
    expect(button.loading, isTrue);
    await tester.tap(find.byType(NxButton));
    expect(env.families.createCalls, hasLength(1));
    env.families.create.release();
    await pumpFrames(tester);
  });

  final cases = <String, (Failure, String)>{
    'demasiadas familias': (
      const Failure(FailureKind.rateLimited, 'too-many-families'),
      'Ya perteneces al número máximo de familias. Para crear otra, primero '
          'sal de alguna.',
    ),
    'nombre inválido': (
      const Failure.validation('family-name-invalid'),
      'Ese nombre no es válido. Usa entre 1 y 40 caracteres, con al menos '
          'una letra o un número.',
    ),
    'sin conexión': (
      const Failure.network(),
      'No hay conexión. Revisa tu red e inténtalo de nuevo.',
    ),
  };
  for (final MapEntry(key: name, value: (failure, message)) in cases.entries) {
    testWidgets('error del servidor: $name', (tester) async {
      final env = FamilyTestEnv(activeFamilyId: null);
      env.families.create.result = Err(failure);
      await pumpFamilyApp(tester, env, initialLocation: AppRoutes.createFamily);
      await submit(tester, 'Familia');
      expect(find.text(message), findsOneWidget);
      expect(env.preferences.prefs.value.activeFamilyId, isNull);
      // Tras el error se puede volver a intentar.
      final button = tester.widget<NxButton>(find.byType(NxButton));
      expect(button.loading, isFalse);
    });
  }
}
