import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/emergency/domain/emergency.dart';
import 'package:nexo_familia/features/emergency/presentation/active_alerts_banner.dart';

import '../../../helpers/fakes.dart';
import 'sos_test_support.dart';

void main() {
  late FakeClock clock;

  setUp(() => clock = FakeClock(testNow));

  Future<FakeEmergencyRepository> pumpBanner(
    WidgetTester tester,
    List<EmergencyAlert> alerts, {
    String? activeFamilyId = familyId,
  }) async {
    final repository = FakeEmergencyRepository(alerts);
    await tester.pumpWidget(
      sosTestApp(
        overrides: sosOverrides(
          repository: repository,
          clock: clock,
          activeFamilyId: activeFamilyId,
        ),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: const [Text('Inicio'), ActiveAlertsBanner()],
          ),
        ),
      ),
    );
    await settle(tester);
    return repository;
  }

  testWidgets('muestra quién pidió ayuda, hace cuánto y si hay ubicación', (
    tester,
  ) async {
    await pumpBanner(tester, [alertOf(uid: 'luis', notifiedCount: 2)]);
    expect(find.text('Luis pidió ayuda'), findsOneWidget);
    expect(find.text('Alerta enviada hace 2 min'), findsOneWidget);
    expect(find.text('Ubicación incluida'), findsOneWidget);
    expect(find.text('Lo vi'), findsOneWidget);
    // Nunca coordenadas.
    expect(find.textContaining('4.6'), findsNothing);
    expect(find.textContaining('-74'), findsNothing);
    expect(visibleText(tester), isNot(matches(forbiddenClaims)));
  });

  testWidgets('sin ubicación lo dice', (tester) async {
    await pumpBanner(tester, [alertOf(uid: 'luis', withLocation: false)]);
    expect(find.text('Sin ubicación'), findsOneWidget);
  });

  testWidgets('no muestra las propias, las terminadas ni las no enviadas', (
    tester,
  ) async {
    await pumpBanner(tester, [
      alertOf(id: 'mia'),
      alertOf(id: 'terminada', uid: 'luis', resolvedAt: testNow),
      alertOf(id: 'pendiente', uid: 'marta', delivery: SosDelivery.queued),
    ]);
    expect(find.textContaining('pidió ayuda'), findsNothing);
    expect(find.text('Lo vi'), findsNothing);
  });

  testWidgets('sin familia activa no muestra nada', (tester) async {
    await pumpBanner(tester, [alertOf(uid: 'luis')], activeFamilyId: null);
    expect(find.textContaining('pidió ayuda'), findsNothing);
  });

  testWidgets('las más recientes primero', (tester) async {
    await pumpBanner(tester, [
      alertOf(id: 'a', uid: 'luis', age: const Duration(hours: 1)),
      alertOf(id: 'b', uid: 'marta', age: const Duration(minutes: 5)),
    ]);
    final marta = tester.getTopLeft(find.text('Marta pidió ayuda'));
    final luis = tester.getTopLeft(find.text('Luis pidió ayuda'));
    expect(marta.dy, lessThan(luis.dy));
    expect(find.text('Alerta enviada hace 1 h'), findsOneWidget);
  });

  testWidgets('"Lo vi" confirma y lo indica solo tras la respuesta', (
    tester,
  ) async {
    final repository = await pumpBanner(tester, [alertOf(uid: 'luis')]);
    await tester.tap(find.text('Lo vi'));
    await settle(tester);
    expect(repository.acknowledged, ['sos-1']);
    expect(find.text('Confirmaste que la viste'), findsOneWidget);
    expect(find.text('Lo vi'), findsNothing);
  });

  testWidgets('si ya la confirmé no vuelve a pedirlo', (tester) async {
    await pumpBanner(tester, [
      alertOf(
        uid: 'luis',
        acks: [EmergencyAck(uid: myUid, at: testNow)],
      ),
    ]);
    expect(find.text('Confirmaste que la viste'), findsOneWidget);
    expect(find.text('Lo vi'), findsNothing);
  });

  testWidgets('si confirmar falla, no se da por hecho y se explica', (
    tester,
  ) async {
    final repository = FakeEmergencyRepository([alertOf(uid: 'luis')])
      ..ackResult = const Err(Failure.network());
    await tester.pumpWidget(
      sosTestApp(
        overrides: sosOverrides(repository: repository, clock: clock),
        home: const Scaffold(body: ActiveAlertsBanner()),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Lo vi'));
    await settle(tester);
    expect(find.text('Confirmaste que la viste'), findsNothing);
    expect(find.text('Lo vi'), findsOneWidget);
    expect(
      find.text('No hay conexión. Revisa tu red e inténtalo de nuevo.'),
      findsOneWidget,
    );
  });

  testWidgets('nombre de respaldo si no se conoce a la autora', (tester) async {
    await pumpBanner(tester, [alertOf(uid: 'desconocido')]);
    expect(find.text('Un integrante pidió ayuda'), findsOneWidget);
  });
}
