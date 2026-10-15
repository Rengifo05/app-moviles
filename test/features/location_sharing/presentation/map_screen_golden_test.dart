@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/features/location_sharing/presentation/map_screen.dart';

import '../../../helpers/fonts.dart';
import 'location_test_support.dart';

/// Pantalla Mapa con la lista accesible (sin proveedor de mapas): un
/// integrante reciente, uno sin actualización reciente y uno aproximado.
/// Para regenerar: `flutter test --update-goldens <este archivo>`.
void main() {
  setUpAll(loadAppFonts);

  for (final (name, theme, scale) in [
    ('claro_x1', NxTheme.light(), 1.0),
    ('oscuro_x2', NxTheme.dark(), 2.0),
  ]) {
    testWidgets('mapa $name', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        locationTestApp(
          overrides: locationOverrides(
            repository: FakeLocationRepository(locations: sampleLocations()),
            device: FakeDeviceLocation(),
            zones: [zone('z1', 'Casa'), zone('z2', 'Colegio', radius: 400)],
          ),
          home: const MapScreen(),
          theme: theme,
          textScale: scale,
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MapScreen),
        matchesGoldenFile('goldens/map_$name.png'),
      );
    });
  }
}
