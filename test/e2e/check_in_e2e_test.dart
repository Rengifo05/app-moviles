import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';

import 'e2e_harness.dart';

void main() {
  testWidgets('un check-in sin conexión queda guardado y se envía una sola '
      'vez al volver la red', (tester) async {
    final app = await E2EApp.start(tester);
    final store = app.composition.demoStore!;
    await app.waitFor(tester, find.text('Siguiente'));
    for (var i = 0; i < 3; i++) {
      await app.tapText(tester, 'Siguiente');
    }
    await app.tapText(tester, 'Entendido, empezar');
    await app.waitFor(tester, find.text('Inicia sesión'));
    await app.tapText(tester, '¿No tienes cuenta? Crear una');
    await app.enterField(tester, 'Tu nombre', 'Ana');
    await app.enterField(tester, 'Correo electrónico', 'ana@example.com');
    await app.enterField(tester, 'Contraseña', 'contraseña-segura');
    await app.tapText(tester, 'Confirmo que tengo 18 años o más');
    await app.tapText(tester, 'Acepto la política de privacidad');
    await app.tapText(tester, 'Crear cuenta');
    await app.waitFor(tester, find.text('Crear una familia'));
    await app.tapText(tester, 'Crear una familia');
    await app.enterField(tester, 'Nombre de la familia', 'Familia Prueba');
    await app.tapText(tester, 'Crear familia');
    await app.waitFor(tester, find.byType(NavigationBar));
    final familyId = store.serverList('families').single.split('/').last;
    List<Map<String, Object?>> checkIns() => [
      for (final path in store.serverList('families/$familyId/events'))
        if (store.serverRead(path)!['type'] == 'checkIn')
          store.serverRead(path)!,
    ];

    // Sin red: el servidor no responde.
    store.simulatedFailure = const Failure.network();
    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .push(AppRoutes.checkIn)
        .ignore();
    await app.waitFor(tester, find.text('Estoy bien'));
    await app.tapText(tester, 'Estoy bien');
    await app.tapText(tester, 'Enviar');
    await app.waitFor(
      tester,
      find.text('Guardado. Se enviará al recuperar la conexión.'),
    );
    expect(checkIns(), isEmpty);
    expect(find.text('Enviado a tu familia'), findsNothing);

    // Vuelve la red: la bandeja lo reintenta sola, sin volver a enviarlo.
    store.simulatedFailure = null;
    await app.waitFor(
      tester,
      find.text('Enviado a tu familia'),
      maxRounds: 600,
    );
    expect(checkIns(), hasLength(1));
    expect(checkIns().single['kind'], 'ok');
    expect(checkIns().single['expireAt'], isA<DateTime>());

    await app.stop(tester);
  });
}
