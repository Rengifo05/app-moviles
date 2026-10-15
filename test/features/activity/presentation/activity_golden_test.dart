@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/features/activity/domain/activity.dart';
import 'package:nexo_familia/features/activity/presentation/activity_screen.dart';

import '../../../helpers/fonts.dart';
import 'activity_test_support.dart';

/// Actividad: historial de hoy, ayer y el domingo (check-ins, SOS, zonas y
/// cambios de integrantes, con un ex integrante) y el estado vacío.
/// Para regenerar: `flutter test --update-goldens <este archivo>`.
void main() {
  setUpAll(loadAppFonts);

  final themes = [
    ('claro_x1', NxTheme.light(), 1.0),
    ('oscuro_x2', NxTheme.dark(), 2.0),
  ];

  Future<void> pumpScreen(
    WidgetTester tester, {
    required ThemeData theme,
    required double scale,
    required List<ActivityItem> activity,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      activityTestApp(
        overrides: activityOverrides(activity: activity),
        theme: theme,
        textScale: scale,
      ),
    );
    await settle(tester);
  }

  for (final (name, theme, scale) in themes) {
    testWidgets('historial $name', (tester) async {
      await pumpScreen(
        tester,
        theme: theme,
        scale: scale,
        activity: sampleActivity,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(ActivityScreen),
        matchesGoldenFile('goldens/actividad_$name.png'),
      );
    });

    testWidgets('vacío $name', (tester) async {
      await pumpScreen(tester, theme: theme, scale: scale, activity: const []);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(ActivityScreen),
        matchesGoldenFile('goldens/actividad_vacia_$name.png'),
      );
    });
  }
}
