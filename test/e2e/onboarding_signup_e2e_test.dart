import 'package:flutter_test/flutter_test.dart';

import 'e2e_harness.dart';

void main() {
  testWidgets('primer uso: bienvenida → registro → configurar familia', (
    tester,
  ) async {
    final app = await E2EApp.start(tester);
    await app.waitFor(tester, find.text('Tu familia, cerca y tranquila'));

    // Bienvenida: cuatro pasos; el último advierte que no sustituye a
    // emergencias y muestra el número configurado.
    expect(find.text('Tu familia, cerca y tranquila'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await app.tapText(tester, 'Siguiente');
    }
    expect(find.textContaining('llama al 123'), findsOneWidget);
    await app.tapText(tester, 'Entendido, empezar');

    // Sin sesión: inicio de sesión → crear cuenta.
    await app.waitFor(tester, find.text('Inicia sesión'));
    await app.tapText(tester, '¿No tienes cuenta? Crear una');
    expect(find.text('Crea tu cuenta'), findsOneWidget);

    // El registro exige mayoría de edad y aceptar la privacidad.
    await app.enterField(tester, 'Tu nombre', 'Ana');
    await app.enterField(tester, 'Correo electrónico', 'ana@example.com');
    await app.enterField(tester, 'Contraseña', 'contraseña-segura');
    await app.tapText(tester, 'Crear cuenta');
    expect(
      find.text('Debes confirmar que eres mayor de edad.'),
      findsOneWidget,
    );
    expect(
      find.text('Debes aceptar la política de privacidad para continuar.'),
      findsOneWidget,
    );

    await app.tapText(tester, 'Confirmo que tengo 18 años o más');
    await app.tapText(tester, 'Acepto la política de privacidad');
    await app.tapText(tester, 'Crear cuenta');

    // Con sesión y sin familia, el enrutador lleva a configurar la familia.
    await app.waitFor(tester, find.text('Familia'));
    expect(find.text('Crea tu cuenta'), findsNothing);

    await app.stop(tester);
  });

  testWidgets('credenciales incorrectas muestran un error genérico', (
    tester,
  ) async {
    final app = await E2EApp.start(tester);
    await app.waitFor(tester, find.text('Siguiente'));
    for (var i = 0; i < 3; i++) {
      await app.tapText(tester, 'Siguiente');
    }
    await app.tapText(tester, 'Entendido, empezar');
    await app.waitFor(tester, find.text('Inicia sesión'));
    await app.enterField(tester, 'Correo electrónico', 'nadie@example.com');
    await app.enterField(tester, 'Contraseña', 'incorrecta');
    await app.tapText(tester, 'Iniciar sesión');
    await app.waitFor(tester, find.text('Correo o contraseña incorrectos.'));
    await app.stop(tester);
  });
}
