@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/design_system/components/map/nx_list_map.dart';
import 'package:nexo_familia/design_system/components/map/nx_map.dart';
import 'package:nexo_familia/design_system/components/nx_avatar.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/components/nx_hold_button.dart';
import 'package:nexo_familia/design_system/components/nx_section.dart';
import 'package:nexo_familia/design_system/components/nx_status_pill.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';

import '../helpers/fonts.dart';

/// Galería del sistema de diseño para revisión visual. Para regenerar las
/// imágenes de referencia: `flutter test --update-goldens --tags golden`.
class _Gallery extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sistema de diseño')),
    body: NxPageBody(
      children: [
        NxBanner(
          icon: Icons.cloud_off_outlined,
          message: 'Sin conexión. Mostramos los últimos datos guardados.',
          actionLabel: 'Reintentar',
          onAction: () {},
        ),
        const NxSectionHeader(title: 'Estados'),
        const Wrap(
          spacing: NxSpace.xs,
          runSpacing: NxSpace.xs,
          children: [
            NxStatusPill(
              label: 'Actualizada hace 2 min',
              icon: Icons.schedule,
              tone: NxTone.positive,
            ),
            NxStatusPill(
              label: 'Sin actualización reciente',
              icon: Icons.history_toggle_off,
              tone: NxTone.warning,
            ),
            NxStatusPill(
              label: 'SOS activo',
              icon: Icons.sos_outlined,
              tone: NxTone.emergency,
            ),
            NxStatusPill(label: 'En pausa', icon: Icons.pause_circle_outline),
          ],
        ),
        const NxSectionHeader(title: 'Integrantes'),
        NxSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const NxAvatar(name: 'Ana Gómez'),
                title: const Text('Ana'),
                subtitle: const Text('Casa · hace 2 min'),
                trailing: Icon(Icons.chevron_right, color: context.nx.inkMuted),
              ),
              const Divider(),
              const ListTile(
                leading: NxAvatar(name: 'Luis', colorSeed: 1),
                title: Text('Luis'),
                subtitle: Text('Sin actualización reciente · hace 3 h'),
              ),
            ],
          ),
        ),
        const NxSectionHeader(title: 'Acciones'),
        NxButton(label: 'Estoy bien', icon: Icons.check, onPressed: () {}),
        const SizedBox(height: NxSpace.xs),
        NxButton(
          label: 'Invitar a la familia',
          onPressed: () {},
          variant: NxButtonVariant.secondary,
        ),
        const SizedBox(height: NxSpace.xs),
        NxButton(
          label: 'Salir del grupo',
          onPressed: () {},
          variant: NxButtonVariant.destructive,
        ),
        const SizedBox(height: NxSpace.lg),
        Center(
          child: NxHoldButton(
            label: 'SOS',
            hint: 'Mantén pulsado 2 segundos',
            onConfirmed: () {},
          ),
        ),
        const SizedBox(height: NxSpace.lg),
        SizedBox(
          height: 260,
          child: NxSurface(
            padding: EdgeInsets.zero,
            child: NxListMap(
              data: NxMapData(
                markers: [
                  NxMapMarker(
                    id: 'a',
                    label: 'Ana',
                    point: GeoPoint(4.65, -74.05),
                    tone: NxMarkerTone.recent,
                    semanticsLabel: 'Actualizada hace 2 min',
                  ),
                  NxMapMarker(
                    id: 'l',
                    label: 'Luis',
                    point: GeoPoint(4.66, -74.06),
                    tone: NxMarkerTone.stale,
                    semanticsLabel: 'Sin actualización reciente',
                  ),
                ],
                zones: const [],
              ),
              strings: NxListMapStrings(
                title: 'Vista de lista',
                emptyMarkers: 'Nadie comparte su ubicación',
                zonesTitle: 'Zonas seguras',
                radiusLabel: (m) => 'Radio de ${m.round()} m',
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

void main() {
  setUpAll(loadAppFonts);

  for (final (name, theme) in [
    ('claro', NxTheme.light()),
    ('oscuro', NxTheme.dark()),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('galería $name al ${(scale * 100).round()} %', (
        tester,
      ) async {
        tester.view
          ..physicalSize = const Size(390, 1700) * 3
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 1700),
                devicePixelRatio: 3,
                textScaler: TextScaler.linear(scale),
              ),
              child: const _Gallery(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(_Gallery),
          matchesGoldenFile('goldens/gallery_${name}_x${scale.round()}.png'),
        );
      });
    }
  }
}
