import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/notifications/presentation/notifications_providers.dart';

import '../../notifications/push_fakes.dart';
import 'family_test_harness.dart';

void main() {
  testWidgets('saluda, explica qué es una familia y ofrece las dos acciones', (
    tester,
  ) async {
    await pumpFamilyApp(
      tester,
      FamilyTestEnv(),
      initialLocation: AppRoutes.familySetup,
    );
    // La prueba E2E del registro espera el texto "Familia" en esta pantalla.
    expect(find.text('Familia'), findsOneWidget);
    expect(find.text('Hola, Ana'), findsOneWidget);
    expect(find.text('Crear una familia'), findsOneWidget);
    expect(find.text('Unirme con un código'), findsOneWidget);
    expect(find.text('¿Qué es una familia en Nexo?'), findsOneWidget);
    expect(find.textContaining('hasta 12 personas adultas'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Cerrar sesión'), 200);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });

  testWidgets('sin nombre usa una bienvenida genérica', (tester) async {
    await pumpFamilyApp(
      tester,
      FamilyTestEnv(
        user: const AuthUser(uid: 'x', email: 'x@example.com'),
      ),
      initialLocation: AppRoutes.familySetup,
    );
    expect(find.text('Te damos la bienvenida'), findsOneWidget);
  });

  testWidgets('"Crear una familia" abre el formulario', (tester) async {
    await pumpFamilyApp(
      tester,
      FamilyTestEnv(),
      initialLocation: AppRoutes.familySetup,
    );
    await tester.tap(find.text('Crear una familia'));
    await pumpFrames(tester);
    expect(find.text('Nombre de la familia'), findsOneWidget);
  });

  testWidgets('"Unirme con un código" abre el formulario del código', (
    tester,
  ) async {
    await pumpFamilyApp(
      tester,
      FamilyTestEnv(),
      initialLocation: AppRoutes.familySetup,
    );
    await tester.tap(find.text('Unirme con un código'));
    await pumpFrames(tester);
    expect(find.text('Código de invitación'), findsOneWidget);
    expect(find.text('Formato: ABCDE-FGHJK'), findsOneWidget);
  });

  testWidgets('cerrar sesión llama al repositorio de autenticación', (
    tester,
  ) async {
    final env = FamilyTestEnv();
    await pumpFamilyApp(tester, env, initialLocation: AppRoutes.familySetup);
    await scrollAndTap(tester, find.text('Cerrar sesión'));
    await pumpFrames(tester);
    expect(env.auth.signOutCalls, 1);
  });

  testWidgets('cerrar sesión borra antes el registro de avisos del '
      'teléfono', (tester) async {
    final service = FakePushService();
    final registry = FakeDeviceRegistry();
    final env = FamilyTestEnv(
      extraOverrides: [
        pushServiceProvider.overrideWithValue(service),
        deviceRegistryProvider.overrideWithValue(registry),
      ],
    );
    await pumpFamilyApp(tester, env, initialLocation: AppRoutes.familySetup);
    await scrollAndTap(tester, find.text('Cerrar sesión'));
    await pumpFrames(tester);
    expect(registry.unregistered, ['token-a']);
    expect(service.deletedTokens, 1);
    expect(env.auth.signOutCalls, 1);
  });

  testWidgets('si cerrar sesión falla, lo explica', (tester) async {
    final env = FamilyTestEnv();
    env.auth.signOutResult = const Err(Failure.network());
    await pumpFamilyApp(tester, env, initialLocation: AppRoutes.familySetup);
    await scrollAndTap(tester, find.text('Cerrar sesión'));
    await pumpFrames(tester);
    expect(
      find.text('No hay conexión. Revisa tu red e inténtalo de nuevo.'),
      findsOneWidget,
    );
  });

  testWidgets('en inglés muestra los textos traducidos', (tester) async {
    await pumpFamilyApp(
      tester,
      FamilyTestEnv(),
      initialLocation: AppRoutes.familySetup,
      locale: const Locale('en'),
    );
    expect(find.text('Create a family'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
  });
}
