import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/design_system/components/nx_state_views.dart';
import 'package:nexo_familia/features/activity/domain/activity.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';

import 'activity_test_support.dart';

void main() {
  testWidgets('agrupa por día con "Hoy", "Ayer" y la fecha', (tester) async {
    await tester.pumpWidget(
      activityTestApp(overrides: activityOverrides(activity: sampleActivity)),
    );
    await settle(tester);
    expect(find.text('Hoy'), findsOneWidget);
    expect(find.text('Ayer'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Domingo, 8 de marzo'), 200);
    expect(find.text('Domingo, 8 de marzo'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Ayer')).dy,
      lessThan(tester.getTopLeft(find.text('Domingo, 8 de marzo')).dy),
    );
  });

  testWidgets('describe cada tipo de evento con nombres actuales', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 1400) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      activityTestApp(overrides: activityOverrides(activity: sampleActivity)),
    );
    await settle(tester);
    expect(find.text('Ana: Estoy bien'), findsOneWidget);
    expect(find.text('“Ya llegué a la casa”'), findsOneWidget);
    expect(find.text('hace 3 min'), findsOneWidget);
    expect(find.text('Luis pidió ayuda (SOS)'), findsOneWidget);
    expect(find.text('Sofía entró a Casa'), findsOneWidget);
    expect(find.text('Luis: Necesito ayuda'), findsOneWidget);
    expect(find.text('Sofía salió de Colegio'), findsOneWidget);
    // Carlos ya no es integrante: no se muestra su nombre.
    expect(find.text('Un ex integrante salió de la familia'), findsOneWidget);
    expect(find.text('Sofía se unió a la familia'), findsOneWidget);
    expect(visibleText(tester), isNot(contains(forbiddenClaims)));
  });

  testWidgets('expulsiones: nombra a quien quitó y a quien salió', (
    tester,
  ) async {
    await tester.pumpWidget(
      activityTestApp(
        overrides: activityOverrides(
          activity: [
            MembershipActivity(
              id: 'r1',
              familyId: familyId,
              actorUid: 'ana',
              occurredAt: testNow,
              change: MembershipChange.removed,
              targetUid: 'carlos',
            ),
            MembershipActivity(
              id: 'r2',
              familyId: familyId,
              actorUid: 'ana',
              occurredAt: testNow.subtract(const Duration(minutes: 1)),
              change: MembershipChange.removed,
            ),
          ],
        ),
      ),
    );
    await settle(tester);
    expect(
      find.text('Ana quitó a un ex integrante de la familia'),
      findsOneWidget,
    );
    expect(
      find.text('Ana quitó a un integrante de la familia'),
      findsOneWidget,
    );
  });

  testWidgets('si no se pueden leer los integrantes, no dice "ex integrante"', (
    tester,
  ) async {
    await tester.pumpWidget(
      activityTestApp(
        overrides: activityOverrides(
          activity: sampleActivity.take(1).toList(),
          membersError: const Failure.unexpected('boom'),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Un integrante: Estoy bien'), findsOneWidget);
    expect(find.textContaining('ex integrante'), findsNothing);
  });

  testWidgets('estado vacío con explicación', (tester) async {
    await tester.pumpWidget(activityTestApp(overrides: activityOverrides()));
    await settle(tester);
    expect(find.text('Aún no hay actividad'), findsOneWidget);
    expect(
      find.text(
        'Aquí verás check-ins, alertas y cambios en la familia de los '
        'últimos 30 días.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('cargando', (tester) async {
    await tester.pumpWidget(
      activityTestApp(overrides: activityOverrides(activity: null)),
    );
    await settle(tester);
    expect(find.byType(NxLoadingView), findsOneWidget);
  });

  testWidgets('error con opción de reintentar', (tester) async {
    await tester.pumpWidget(
      activityTestApp(
        overrides: activityOverrides(
          activityError: const Failure.network('down'),
        ),
      ),
    );
    await settle(tester);
    expect(
      find.text('No hay conexión. Revisa tu red e inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('sin conexión muestra el aviso y los datos guardados', (
    tester,
  ) async {
    await tester.pumpWidget(
      activityTestApp(
        overrides: activityOverrides(
          activity: sampleActivity,
          sync: SyncStatus.offline,
        ),
      ),
    );
    await settle(tester);
    expect(
      find.text('Sin conexión. Mostramos los últimos datos guardados.'),
      findsOneWidget,
    );
    expect(find.text('Ana: Estoy bien'), findsOneWidget);
  });

  testWidgets('sin familia activa ofrece crear o unirse', (tester) async {
    await tester.pumpWidget(
      activityTestApp(overrides: activityOverrides(activeFamilyId: null)),
    );
    await settle(tester);
    expect(find.text('Sin familia activa'), findsOneWidget);
    await tester.tap(find.text('Crear o unirme a una familia'));
    await settle(tester);
    expect(find.text('ruta:/family-setup'), findsOneWidget);
  });

  testWidgets('cada evento es un solo nodo para el lector de pantalla', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      activityTestApp(
        overrides: activityOverrides(activity: sampleActivity.take(1).toList()),
      ),
    );
    await settle(tester);
    expect(
      find.bySemanticsLabel(
        RegExp(
          'Ana: Estoy bien.*Ya llegué a la casa.*hace 3 min',
          dotAll: true,
        ),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('con texto al 200 % no hay desbordes', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      activityTestApp(
        overrides: activityOverrides(
          activity: sampleActivity,
          sync: SyncStatus.offline,
        ),
        textScale: 2,
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
