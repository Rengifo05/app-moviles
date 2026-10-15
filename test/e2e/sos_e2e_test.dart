import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/design_system/components/nx_hold_button.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';

import 'e2e_flows.dart';
import 'e2e_harness.dart';

void main() {
  testWidgets('SOS: se activa manteniendo presionado, informa con honestidad '
      'y solo cuenta como confirmada con el "Lo vi" de otra persona', (
    tester,
  ) async {
    final app = await E2EApp.start(tester);
    await app.completeOnboarding(tester);

    // Ana crea la familia e invita a Luis.
    await app.signUp(tester, name: 'Ana', email: 'ana@example.com');
    await app.createFamily(tester, 'Familia Prueba');
    final code = await app.inviteCode(tester);
    await app.signOut(tester);
    await app.signUp(tester, name: 'Luis', email: 'luis@example.com');
    await app.joinWithCode(tester, code);

    // Luis abre el SOS. Un toque corto no envía nada.
    app.push(tester, AppRoutes.sos);
    await app.waitFor(tester, find.byType(NxHoldButton));
    await tester.tap(find.byType(NxHoldButton));
    await app.settle(tester);
    expect(find.text('La alerta se enviará en'), findsNothing);

    // Mantener presionado inicia la cuenta atrás cancelable.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(NxHoldButton)),
    );
    await app.settle(tester, rounds: 25);
    await gesture.up();
    await app.waitFor(tester, find.text('La alerta se enviará en'));
    expect(find.text('Cancelar'), findsOneWidget);

    // Al terminar: registrada. El modo demo no tiene push, así que la app lo
    // dice sin fingir que alguien recibió el aviso.
    await app.waitFor(tester, find.text('Alerta registrada'), maxRounds: 150);
    await app.waitFor(
      tester,
      find.text('Nadie pudo ser notificado. Llama al 123 si lo necesitas.'),
    );
    expect(find.textContaining('recibid'), findsNothing);
    expect(find.text('Nadie ha confirmado todavía que la vio.'), findsOne);
    final store = app.composition.demoStore!;
    final familyId = store.serverList('families').single.split('/').last;
    expect(store.serverList('families/$familyId/emergencies'), hasLength(1));

    // Ana la ve en Inicio y confirma que la vio.
    await app.signOut(tester);
    await app.signIn(tester, email: 'ana@example.com');
    await app.waitFor(tester, find.text('Luis pidió ayuda'));
    await app.tapText(tester, 'Lo vi');
    await app.waitFor(tester, find.text('Confirmaste que la viste'));

    // Luis ve la confirmación de Ana.
    await app.signOut(tester);
    await app.signIn(tester, email: 'luis@example.com');
    await app.waitFor(tester, find.byType(NavigationBar));
    app.push(tester, AppRoutes.sos);
    await app.waitFor(tester, find.textContaining('Ana confirmó que la vio'));
    expect(find.text('Nadie ha confirmado todavía que la vio.'), findsNothing);

    await app.stop(tester);
  });
}
