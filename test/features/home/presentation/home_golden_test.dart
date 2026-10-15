@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/home/presentation/home_screen.dart';

import '../../../helpers/fonts.dart';
import 'home_test_support.dart';

/// Inicio con una alerta SOS activa de otro integrante (Luis), un
/// integrante con ubicación reciente (Luis), otro sin actualización
/// reciente (Marta) y otra que no comparte (Sofía).
/// Para regenerar: `flutter test --update-goldens <este archivo>`.
void main() {
  setUpAll(loadAppFonts);

  final themes = [
    ('claro_x1', NxTheme.light(), 1.0),
    ('oscuro_x2', NxTheme.dark(), 2.0),
  ];

  Future<void> pumpHome(
    WidgetTester tester, {
    required ThemeData theme,
    required double scale,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      homeTestApp(
        overrides: homeOverrides(alerts: [alertOf()]),
        theme: theme,
        textScale: scale,
      ),
    );
    await settle(tester);
  }

  for (final (name, theme, scale) in themes) {
    testWidgets('inicio $name', (tester) async {
      await pumpHome(tester, theme: theme, scale: scale);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(HomeScreen),
        matchesGoldenFile('goldens/inicio_$name.png'),
      );
    });

    // Parte inferior: acciones rápidas e integrantes.
    testWidgets('inicio integrantes $name', (tester) async {
      await pumpHome(tester, theme: theme, scale: scale);
      await tester.scrollUntilVisible(
        find.text('Tu familia'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(tester.element(find.text('Tu familia')));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(HomeScreen),
        matchesGoldenFile('goldens/inicio_integrantes_$name.png'),
      );
    });
  }

  testWidgets('pendientes y sin conexión claro_x1', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      homeTestApp(
        overrides: homeOverrides(
          sync: SyncStatus.offline,
          pending: [pendingCheckIn('c1')],
        ),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/inicio_pendientes_claro_x1.png'),
    );
  });
}
