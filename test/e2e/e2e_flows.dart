import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/app/app.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';

import 'e2e_harness.dart';

/// Pasos de usuario reutilizables en las pruebas de extremo a extremo.
extension E2EFlows on E2EApp {
  Future<void> completeOnboarding(WidgetTester tester) async {
    await waitFor(tester, find.text('Siguiente'));
    for (var i = 0; i < 3; i++) {
      await tapText(tester, 'Siguiente');
    }
    await tapText(tester, 'Entendido, empezar');
  }

  Future<void> signUp(
    WidgetTester tester, {
    required String name,
    required String email,
  }) async {
    await waitFor(tester, find.text('Inicia sesión'));
    await tapText(tester, '¿No tienes cuenta? Crear una');
    await enterField(tester, 'Tu nombre', name);
    await enterField(tester, 'Correo electrónico', email);
    await enterField(tester, 'Contraseña', 'contraseña-segura');
    await tapText(tester, 'Confirmo que tengo 18 años o más');
    await tapText(tester, 'Acepto la política de privacidad');
    await tapText(tester, 'Crear cuenta');
  }

  Future<void> signIn(WidgetTester tester, {required String email}) async {
    await waitFor(tester, find.text('Inicia sesión'));
    await enterField(tester, 'Correo electrónico', email);
    await enterField(tester, 'Contraseña', 'contraseña-segura');
    await tapText(tester, 'Iniciar sesión');
  }

  /// Cierra la sesión con el repositorio de la app (el mismo que usa la
  /// pantalla de Cuenta), sin depender de en qué pestaña se esté.
  Future<void> signOut(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NexoApp)),
    );
    await tester.runAsync(
      () => container.read(authRepositoryProvider).signOut(),
    );
    await settle(tester);
  }

  Future<void> createFamily(WidgetTester tester, String name) async {
    await waitFor(tester, find.text('Crear una familia'));
    await tapText(tester, 'Crear una familia');
    await enterField(tester, 'Nombre de la familia', name);
    await tapText(tester, 'Crear familia');
    await waitFor(tester, find.byType(NavigationBar));
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    final tab = find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );
    await waitFor(tester, tab);
    await tester.tap(tab);
    await settle(tester);
  }

  /// Genera un código de invitación desde la pestaña Familia.
  Future<String> inviteCode(WidgetTester tester) async {
    await openTab(tester, 'Familia');
    await tapText(tester, 'Invitar a alguien');
    await tapText(tester, 'Generar código');
    final code = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          RegExp(r'^[A-Z0-9]{5}-[A-Z0-9]{5}$').hasMatch(w.data ?? ''),
    );
    await waitFor(tester, code);
    return tester.widget<Text>(code.first).data!;
  }

  Future<void> joinWithCode(WidgetTester tester, String code) async {
    await waitFor(tester, find.text('Unirme con un código'));
    await tapText(tester, 'Unirme con un código');
    await enterField(tester, 'Código de invitación', code);
    await tapText(tester, 'Unirme');
    await waitFor(tester, find.byType(NavigationBar));
  }

  /// Abre [route] encima de la pestaña actual (el contexto debe estar
  /// dentro del enrutador: la barra de pestañas lo está).
  void push(WidgetTester tester, String route) =>
      GoRouter.of(tester.element(find.byType(NavigationBar)))
          .push(route)
          .ignore();
}
