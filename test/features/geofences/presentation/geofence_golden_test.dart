@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/family/domain/family.dart';

import '../../../helpers/fonts.dart';
import 'geofence_test_support.dart';

/// Capturas del editor de zonas para revisión visual, en claro al 100 % y
/// en oscuro al 200 %, con el mapa no disponible. Para regenerarlas:
/// `flutter test --update-goldens test/features/geofences/presentation/geofence_golden_test.dart`.
typedef _Case = ({
  String name,
  String location,
  GeofenceTestEnv Function() env,
  Future<void> Function(WidgetTester tester)? act,
});

Future<void> _chooseCenter(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'Colegio');
  await pumpFrames(tester, frames: 3);
  await scrollAndTap(
    tester,
    find.widgetWithText(TextButton, 'Usar mi ubicación actual'),
  );
  // Vuelve arriba para la captura principal.
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
  await pumpFrames(tester);
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
  await pumpFrames(tester);
}

final List<_Case> _cases = [
  (
    name: 'nueva_centro',
    location: AppRoutes.newZone,
    env: GeofenceTestEnv.new,
    act: _chooseCenter,
  ),
  (
    name: 'nueva_centro_fin',
    location: AppRoutes.newZone,
    env: GeofenceTestEnv.new,
    act: (tester) async {
      await _chooseCenter(tester);
      await _scrollToEnd(tester);
    },
  ),
  (
    name: 'nueva_errores',
    location: AppRoutes.newZone,
    env: GeofenceTestEnv.new,
    act: (tester) async {
      await scrollAndTap(
        tester,
        find.widgetWithText(TextButton, 'Guardar zona'),
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
      await pumpFrames(tester);
    },
  ),
  (
    name: 'editar_conflicto',
    location: AppRoutes.zone('z1'),
    env: () {
      final env = GeofenceTestEnv();
      env.repository.updateResult = const Err(
        Failure.conflict('geofence-conflict'),
      );
      return env;
    },
    act: (tester) async {
      await scrollAndTap(
        tester,
        find.widgetWithText(TextButton, 'Guardar cambios'),
      );
    },
  ),
  (
    name: 'editar_fin',
    location: AppRoutes.zone('z1'),
    env: GeofenceTestEnv.new,
    act: _scrollToEnd,
  ),
  (
    name: 'solo_lectura',
    location: AppRoutes.zone('z1'),
    env: () => GeofenceTestEnv(role: MemberRole.member),
    act: null,
  ),
];

void main() {
  setUpAll(loadAppFonts);

  for (final c in _cases) {
    for (final (theme, scale) in [('claro', 1.0), ('oscuro', 2.0)]) {
      testWidgets('${c.name} $theme al ${(scale * 100).round()} %', (
        tester,
      ) async {
        await pumpGeofenceApp(
          tester,
          c.env(),
          location: c.location,
          theme: theme == 'claro' ? NxTheme.light() : NxTheme.dark(),
          textScale: scale,
        );
        if (c.act case final act?) await act(tester);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${c.name}_${theme}_x${scale.round()}.png'),
        );
      });
    }
  }
}
