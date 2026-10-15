@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/features/emergency/domain/emergency.dart';
import 'package:nexo_familia/features/emergency/presentation/active_alerts_banner.dart';
import 'package:nexo_familia/features/emergency/presentation/sos_screen.dart';

import '../../../helpers/fakes.dart';
import '../../../helpers/fonts.dart';
import 'sos_test_support.dart';

/// Pantalla SOS: estado inicial, cuenta atrás, alerta notificada a nadie y
/// alerta notificada a dos dispositivos y confirmada por otro integrante; y
/// el aviso de Inicio para los demás integrantes.
/// Para regenerar: `flutter test --update-goldens <este archivo>`.
void main() {
  setUpAll(loadAppFonts);

  final themes = [
    ('claro_x1', NxTheme.light(), 1.0),
    ('oscuro_x2', NxTheme.dark(), 2.0),
  ];

  Future<FakeClock> pumpScreen(
    WidgetTester tester, {
    required ThemeData theme,
    required double scale,
    Widget home = const SosScreen(),
    List<EmergencyAlert> alerts = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = FakeClock(testNow);
    await tester.pumpWidget(
      sosTestApp(
        overrides: sosOverrides(
          repository: FakeEmergencyRepository(alerts),
          clock: clock,
        ),
        home: home,
        theme: theme,
        textScale: scale,
      ),
    );
    await settle(tester);
    return clock;
  }

  for (final (name, theme, scale) in themes) {
    testWidgets('inicial $name', (tester) async {
      await pumpScreen(tester, theme: theme, scale: scale);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(SosScreen),
        matchesGoldenFile('goldens/sos_inicial_$name.png'),
      );
    });

    testWidgets('cuenta atrás $name', (tester) async {
      final clock = await pumpScreen(tester, theme: theme, scale: scale);
      await holdSos(tester, clock);
      await elapse(tester, clock, const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(SosScreen),
        matchesGoldenFile('goldens/sos_cuenta_atras_$name.png'),
      );
    });

    testWidgets('notificada a nadie $name', (tester) async {
      await pumpScreen(
        tester,
        theme: theme,
        scale: scale,
        alerts: [alertOf(notifiedCount: 0)],
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(SosScreen),
        matchesGoldenFile('goldens/sos_notificada_cero_$name.png'),
      );
    });

    testWidgets('confirmada $name', (tester) async {
      await pumpScreen(
        tester,
        theme: theme,
        scale: scale,
        alerts: [
          alertOf(
            notifiedCount: 2,
            acks: [
              EmergencyAck(uid: 'luis', at: DateTime.utc(2026, 3, 10, 14, 32)),
            ],
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(SosScreen),
        matchesGoldenFile('goldens/sos_confirmada_$name.png'),
      );
    });

    testWidgets('aviso en Inicio $name', (tester) async {
      await pumpScreen(
        tester,
        theme: theme,
        scale: scale,
        alerts: [
          alertOf(id: 'a', uid: 'luis', age: const Duration(minutes: 3)),
          alertOf(
            id: 'b',
            uid: 'marta',
            withLocation: false,
            age: const Duration(hours: 1),
            acks: [EmergencyAck(uid: myUid, at: testNow)],
          ),
        ],
        home: const Scaffold(
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: SingleChildScrollView(child: ActiveAlertsBanner()),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/aviso_inicio_$name.png'),
      );
    });
  }
}
