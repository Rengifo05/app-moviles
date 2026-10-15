import 'package:flutter/material.dart';
import 'package:nexo_familia/design_system/components/map/nx_map.dart';
import 'package:nexo_familia/design_system/components/nx_avatar.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';

/// Textos que necesita [NxListMap] (los aporta la pantalla, localizados).
@immutable
final class NxListMapStrings {
  const new({
    required this.title,
    required this.emptyMarkers,
    required this.zonesTitle,
    required this.radiusLabel,
  });

  final String title;
  final String emptyMarkers;
  final String zonesTitle;

  /// Formatea el radio de una zona, p. ej. "Radio de 200 m".
  final String Function(double meters) radiusLabel;
}

/// Representación del mapa como lista. Se usa cuando no hay proveedor de
/// mapas configurado, en pruebas en el host y como vista accesible
/// alternativa. Nunca muestra coordenadas.
class NxListMap extends StatelessWidget {
  const new({required this.data, required this.strings, super.key});

  final NxMapData data;
  final NxListMapStrings strings;

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    return ListView(
      padding: const EdgeInsets.all(NxSpace.md),
      children: [
        Semantics(
          header: true,
          child: Text(strings.title, style: context.text.titleMedium),
        ),
        const SizedBox(height: NxSpace.xs),
        if (data.markers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NxSpace.md),
            child: Text(
              strings.emptyMarkers,
              style: context.text.bodyMedium?.copyWith(color: c.inkMuted),
            ),
          ),
        for (final (index, marker) in data.markers.indexed)
          Semantics(
            selected: marker.id == data.selectedMarkerId,
            child: ListTile(
              leading: NxAvatar(name: marker.label, colorSeed: index),
              title: Text(marker.label),
              subtitle: Text(marker.semanticsLabel),
              trailing: Icon(
                switch (marker.tone) {
                  NxMarkerTone.recent => Icons.location_on_outlined,
                  NxMarkerTone.stale => Icons.history_toggle_off,
                  NxMarkerTone.emergency => Icons.sos_outlined,
                },
                color: marker.tone == NxMarkerTone.emergency
                    ? c.emergency
                    : c.inkMuted,
              ),
              selected: marker.id == data.selectedMarkerId,
              onTap: data.onMarkerTap == null
                  ? null
                  : () => data.onMarkerTap!(marker.id),
            ),
          ),
        if (data.zones.isNotEmpty) ...[
          const SizedBox(height: NxSpace.md),
          Semantics(
            header: true,
            child: Text(strings.zonesTitle, style: context.text.titleMedium),
          ),
          for (final zone in data.zones)
            ListTile(
              leading: const Icon(Icons.radio_button_checked_outlined),
              title: Text(zone.name),
              subtitle: Text(strings.radiusLabel(zone.radiusMeters)),
            ),
        ],
      ],
    );
  }
}
