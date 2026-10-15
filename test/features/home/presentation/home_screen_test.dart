import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_state_views.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/emergency/presentation/active_alerts_banner.dart';
import 'package:nexo_familia/features/family/domain/family.dart';

import '../../../helpers/fakes.dart';
import 'home_test_support.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(homeTestApp(overrides: homeOverrides()));
    await settle(tester);
  }

  testWidgets('saluda con el nombre y muestra la familia activa', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.text('Hola, Ana'), findsOneWidget);
    expect(find.text('Familia activa: Familia Rojas'), findsOneWidget);
  });

  testWidgets('sin nombre de perfil usa el nombre de integrante', (
    tester,
  ) async {
    await tester.pumpWidget(
      homeTestApp(overrides: homeOverrides(displayName: null)),
    );
    await settle(tester);
    expect(find.text('Hola, Ana Rojas'), findsOneWidget);
  });

  testWidgets('sin ningún nombre saluda con "Hola"', (tester) async {
    await tester.pumpWidget(
      homeTestApp(
        overrides: homeOverrides(
          displayName: '  ',
          members: [member(myUid, ''), member('luis', 'Luis')],
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Hola'), findsOneWidget);
  });

  testWidgets(
    'estado honesto de cada integrante, sin incluir a la persona actual',
    (tester) async {
      await pumpHome(tester);
      expect(find.text('Ubicación actualizada hace 3 min'), findsOneWidget);
      expect(
        find.text('Sin actualización reciente (última: hace 2 h)'),
        findsOneWidget,
      );
      expect(find.text('No comparte su ubicación'), findsOneWidget);
      // Ana es la persona actual: su estado va en la tarjeta de compartición.
      expect(find.text('Ana Rojas'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Luis')).dy,
        lessThan(tester.getTopLeft(find.text('Marta')).dy),
      );
      expect(visibleText(tester), isNot(contains(forbiddenClaims)));
    },
  );

  testWidgets('una ubicación aproximada lo dice', (tester) async {
    await tester.pumpWidget(
      homeTestApp(
        overrides: homeOverrides(
          locations: [
            locationOf(
              'luis',
              age: const Duration(minutes: 10),
              approximate: true,
            ),
          ],
        ),
      ),
    );
    await settle(tester);
    expect(
      find.text('Ubicación aproximada actualizada hace 10 min'),
      findsOneWidget,
    );
  });

  testWidgets('si las ubicaciones fallan no inventa un estado', (tester) async {
    await tester.pumpWidget(
      homeTestApp(
        overrides: homeOverrides(
          locationsError: const Failure.unexpected('boom'),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('No pudimos leer su ubicación'), findsNWidgets(3));
    expect(find.text('No comparte su ubicación'), findsNothing);
  });

  testWidgets(
    'la hora relativa se actualiza mientras la pantalla está abierta',
    (tester) async {
      final clock = FakeClock(testNow);
      await tester.pumpWidget(
        homeTestApp(overrides: homeOverrides(clock: clock)),
      );
      await settle(tester);
      expect(find.text('Ubicación actualizada hace 3 min'), findsOneWidget);

      clock.advance(const Duration(minutes: 30));
      await tester.pump(const Duration(seconds: 31));
      expect(find.text('Ubicación actualizada hace 3 min'), findsNothing);
      expect(
        find.text('Sin actualización reciente (última: hace 33 min)'),
        findsOneWidget,
      );
    },
  );

  testWidgets('muestra arriba el aviso de un SOS activo de otro integrante', (
    tester,
  ) async {
    await tester.pumpWidget(
      homeTestApp(overrides: homeOverrides(alerts: [alertOf()])),
    );
    await settle(tester);
    expect(find.byType(ActiveAlertsBanner), findsOneWidget);
    expect(find.text('Luis pidió ayuda'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Luis pidió ayuda')).dy,
      lessThan(tester.getTopLeft(find.text('Hola, Ana')).dy),
    );
  });

  testWidgets('no muestra como aviso mi propia alerta ni las terminadas', (
    tester,
  ) async {
    await tester.pumpWidget(
      homeTestApp(
        overrides: homeOverrides(
          alerts: [
            alertOf(id: 'mine', uid: myUid),
            alertOf(id: 'old', resolvedAt: testNow),
          ],
        ),
      ),
    );
    await settle(tester);
    expect(find.textContaining('pidió ayuda'), findsNothing);
  });

  testWidgets('sin conexión muestra el aviso', (tester) async {
    await tester.pumpWidget(
      homeTestApp(overrides: homeOverrides(sync: SyncStatus.offline)),
    );
    await settle(tester);
    expect(
      find.text('Sin conexión. Mostramos los últimos datos guardados.'),
      findsOneWidget,
    );
  });

  testWidgets('avisa de check-ins pendientes y fallidos y lleva a revisarlos', (
    tester,
  ) async {
    await tester.pumpWidget(
      homeTestApp(
        overrides: homeOverrides(
          pending: [
            pendingCheckIn('c1'),
            pendingCheckIn('c2'),
            pendingCheckIn('c3', delivery: DeliveryState.failed),
          ],
        ),
      ),
    );
    await settle(tester);
    expect(
      find.text(
        'Tienes 2 check-ins guardados en el teléfono que aún no se envían.',
      ),
      findsOneWidget,
    );
    expect(find.text('1 check-in no se pudo enviar.'), findsOneWidget);
    expect(find.byType(NxBanner), findsNWidgets(2));

    await tester.tap(find.text('Revisar').first);
    await settle(tester);
    expect(find.text('ruta:/check-in'), findsOneWidget);
  });

  testWidgets('cada integrante lleva a su detalle', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('Marta'));
    await settle(tester);
    expect(find.text('ruta:/family/members/marta'), findsOneWidget);
  });

  testWidgets('Check-in abre la pantalla de check-in', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('Check-in'));
    await settle(tester);
    expect(find.text('ruta:/check-in'), findsOneWidget);
  });

  testWidgets('SOS solo abre la pantalla de emergencia: no crea la alerta', (
    tester,
  ) async {
    final emergency = RecordingEmergencyRepository();
    await tester.pumpWidget(
      homeTestApp(overrides: homeOverrides(emergency: emergency)),
    );
    await settle(tester);
    expect(
      find.text(
        'SOS abre la pantalla de emergencia: nada se envía hasta que lo '
        'confirmes allí.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('SOS'));
    await settle(tester);
    expect(find.text('ruta:/sos'), findsOneWidget);
    expect(emergency.raised, isEmpty);
  });

  testWidgets('si es la única persona, invita a otros', (tester) async {
    await tester.pumpWidget(
      homeTestApp(
        overrides: homeOverrides(
          members: [member(myUid, 'Ana Rojas', MemberRole.owner)],
        ),
      ),
    );
    await settle(tester);
    expect(find.textContaining('Aún no hay más integrantes'), findsOneWidget);
    await tester.ensureVisible(find.text('Invitar'));
    await tester.tap(find.text('Invitar'));
    await settle(tester);
    expect(find.text('ruta:/family/invite'), findsOneWidget);
  });

  testWidgets('sin familia activa ofrece crear o unirse', (tester) async {
    await tester.pumpWidget(
      homeTestApp(overrides: homeOverrides(activeFamilyId: null)),
    );
    await settle(tester);
    expect(find.text('Aún no estás en una familia'), findsOneWidget);
    await tester.tap(find.text('Crear o unirme a una familia'));
    await settle(tester);
    expect(find.text('ruta:/family-setup'), findsOneWidget);
  });

  testWidgets('las filas de integrantes son táctiles de al menos 48 dp', (
    tester,
  ) async {
    await pumpHome(tester);
    final row = find.ancestor(
      of: find.text('Luis'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(row.first).height, greaterThanOrEqualTo(48));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  testWidgets('integrantes cargando: indicador compacto', (tester) async {
    await tester.pumpWidget(
      homeTestApp(overrides: homeOverrides(membersLoading: true)),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byType(NxLoadingView),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(NxLoadingView), findsOneWidget);
  });

  testWidgets('integrantes con error: aviso con reintentar', (tester) async {
    await tester.pumpWidget(
      homeTestApp(
        overrides: homeOverrides(membersError: const Failure.network('down')),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Reintentar'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('No hay conexión. Revisa tu red e inténtalo de nuevo.'),
      findsOneWidget,
    );
  });

  testWidgets('con texto al 200 % no hay desbordes', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      homeTestApp(
        overrides: homeOverrides(
          alerts: [alertOf()],
          pending: [pendingCheckIn('c1')],
          sync: SyncStatus.offline,
        ),
        textScale: 2,
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
