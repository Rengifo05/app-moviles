import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/app/app.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';

import 'e2e_harness.dart';

/// Pasa la bienvenida (solo la primera vez en el dispositivo).
Future<void> _completeOnboarding(WidgetTester tester, E2EApp app) async {
  await app.waitFor(tester, find.text('Siguiente'));
  for (var i = 0; i < 3; i++) {
    await app.tapText(tester, 'Siguiente');
  }
  await app.tapText(tester, 'Entendido, empezar');
}

/// Crea una cuenta desde la pantalla de inicio de sesión.
Future<void> _signUp(
  WidgetTester tester,
  E2EApp app, {
  required String name,
  required String email,
}) async {
  await app.waitFor(tester, find.text('Inicia sesión'));
  await app.tapText(tester, '¿No tienes cuenta? Crear una');
  await app.enterField(tester, 'Tu nombre', name);
  await app.enterField(tester, 'Correo electrónico', email);
  await app.enterField(tester, 'Contraseña', 'contraseña-segura');
  await app.tapText(tester, 'Confirmo que tengo 18 años o más');
  await app.tapText(tester, 'Acepto la política de privacidad');
  await app.tapText(tester, 'Crear cuenta');
}

Future<void> _openTab(WidgetTester tester, E2EApp app, String label) async {
  final tab = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );
  await app.waitFor(tester, tab);
  await tester.tap(tab);
  await app.settle(tester);
}

/// Código de invitación tal como se muestra (ABCDE-FGHJK).
final Finder _codeFinder = find.byWidgetPredicate(
  (w) =>
      w is Text && RegExp(r'^[A-Z0-9]{5}-[A-Z0-9]{5}$').hasMatch(w.data ?? ''),
);

void main() {
  testWidgets('crear una familia, invitar y unirse con el código desde otra '
      'cuenta', (tester) async {
    final app = await E2EApp.start(tester);
    await _completeOnboarding(tester, app);

    // Ana crea la familia.
    await _signUp(tester, app, name: 'Ana', email: 'ana@example.com');
    await app.waitFor(tester, find.text('Crear una familia'));
    await app.tapText(tester, 'Crear una familia');
    await app.enterField(tester, 'Nombre de la familia', '  Familia Prueba  ');
    await app.tapText(tester, 'Crear familia');

    // Con la membresía sincronizada la sesión queda lista: barra de pestañas.
    await _openTab(tester, app, 'Familia');
    await app.waitFor(tester, find.text('Familia Prueba'));
    expect(find.text('1 integrante'), findsOneWidget);

    // Genera un código de invitación de un solo uso.
    await app.tapText(tester, 'Invitar a alguien');
    await app.tapText(tester, 'Generar código');
    await app.waitFor(tester, _codeFinder);
    final code = tester.widget<Text>(_codeFinder.first).data!;

    // Cierra sesión (la pantalla de Cuenta llega en otro incremento; aquí
    // se usa el repositorio de la app, el mismo que usaría esa pantalla).
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NexoApp)),
    );
    await tester.runAsync(
      () => container.read(authRepositoryProvider).signOut(),
    );
    await app.settle(tester);

    // Luis se registra y se une con el código, escrito en minúsculas y con
    // espacios: la app lo normaliza.
    await _signUp(tester, app, name: 'Luis', email: 'luis@example.com');
    await app.waitFor(tester, find.text('Unirme con un código'));
    await app.tapText(tester, 'Unirme con un código');
    await app.enterField(
      tester,
      'Código de invitación',
      ' ${code.toLowerCase()} ',
    );
    await app.tapText(tester, 'Unirme');

    await _openTab(tester, app, 'Familia');
    await app.waitFor(tester, find.text('2 integrantes'));
    expect(find.text('Familia Prueba'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Luis'), findsOneWidget);
    // Luis entra como integrante: no puede invitar.
    expect(find.text('Invitar a alguien'), findsNothing);

    await app.stop(tester);
  });

  testWidgets('un código inexistente da un error que no confirma nada', (
    tester,
  ) async {
    final app = await E2EApp.start(tester);
    await _completeOnboarding(tester, app);
    await _signUp(tester, app, name: 'Sofía', email: 'sofia@example.com');
    await app.waitFor(tester, find.text('Unirme con un código'));
    await app.tapText(tester, 'Unirme con un código');
    await app.enterField(tester, 'Código de invitación', 'ABCDE-FGHJK');
    await app.tapText(tester, 'Unirme');
    await app.waitFor(
      tester,
      find.text(
        'El código no es válido o ya venció. Pide uno nuevo a quien te '
        'invitó.',
      ),
    );
    await app.stop(tester);
  });
}
