import 'package:flutter/material.dart';
import 'package:nexo_familia/design_system/components/map/nx_map.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/components/nx_status_pill.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';
import 'package:nexo_familia/features/geofences/presentation/geofence_editor_logic.dart';
import 'package:nexo_familia/features/geofences/presentation/geofence_text.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Línea de texto con un ícono decorativo: avisos y explicaciones dentro
/// del contenido, sin tarjetas.
class GeofenceNote extends StatelessWidget {
  const new({required this.icon, required this.text, super.key, this.color});

  final IconData icon;
  final String text;

  /// Color del ícono y del texto (por defecto, texto principal con ícono
  /// atenuado).
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: NxSpace.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Alinea el ícono con la primera línea del texto.
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: ExcludeSemantics(
            child: Icon(
              icon,
              size: nxScaledIcon(context, NxSize.iconMd - 4),
              color: color ?? context.nx.inkMuted,
            ),
          ),
        ),
        const SizedBox(width: NxSpace.sm),
        Expanded(
          child: Text(
            text,
            style: context.text.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    ),
  );
}

/// Radio de la zona: valor visible ("Radio: 200 m"), control deslizante de
/// 100 a 2000 m en pasos de 50 m y el rango permitido.
///
/// El lector de pantalla anuncia el control con el mismo texto del valor;
/// subir o bajar mueve un paso (50 m).
class GeofenceRadiusField extends StatelessWidget {
  const new({required this.meters, required this.onChanged, super.key});

  final double meters;

  /// Nulo para desactivarlo (p. ej. mientras se guarda).
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = l10n.geofenceRadiusValue(meters.round());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // El control ya anuncia el valor: el texto visible no se repite.
        ExcludeSemantics(child: Text(value, style: context.text.titleMedium)),
        Slider(
          value: meters,
          min: GeofenceRules.minRadiusMeters,
          max: GeofenceRules.maxRadiusMeters,
          divisions: geofenceRadiusDivisions,
          label: value,
          semanticFormatterCallback: (v) => l10n.geofenceRadiusValue(v.round()),
          onChanged: onChanged,
          padding: const EdgeInsets.symmetric(vertical: NxSpace.sm),
        ),
        Text(
          l10n.geofenceRadiusRange(
            GeofenceRules.minRadiusMeters.round(),
            GeofenceRules.maxRadiusMeters.round(),
          ),
          style: context.text.bodySmall,
        ),
      ],
    );
  }
}

/// Estado del centro elegido, sin coordenadas: "Centro elegido · precisión
/// ±12 m", "Centro elegido en el mapa"…
class GeofenceCenterStatus extends StatelessWidget {
  const new({required this.center, required this.showError, super.key});

  final ZoneCenter? center;

  /// Se intentó guardar sin centro.
  final bool showError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final center = this.center;
    final text = geofenceCenterText(l10n, center);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (center == null)
          GeofenceNote(icon: Icons.place_outlined, text: text)
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NxSpace.xs),
            child: NxStatusPill(
              label: text,
              icon: switch (center) {
                SavedCenter() => Icons.place_outlined,
                CurrentLocationCenter() ||
                MapPickedCenter() => Icons.check_circle_outline,
              },
              tone: switch (center) {
                SavedCenter() => NxTone.neutral,
                CurrentLocationCenter() || MapPickedCenter() => NxTone.positive,
              },
            ),
          ),
        if (center case CurrentLocationCenter(isLowAccuracy: true))
          GeofenceNote(
            icon: Icons.gps_not_fixed,
            text: l10n.geofenceCenterLowAccuracy,
          ),
        if (showError && center == null)
          Semantics(
            liveRegion: true,
            child: GeofenceNote(
              icon: Icons.error_outline,
              text: l10n.geofenceErrorCenterRequired,
              color: context.nx.emergency,
            ),
          ),
      ],
    );
  }
}

/// Mapa del proveedor (si lo hay) con un alto acotado y bordes redondeados.
class GeofenceMapBox extends StatelessWidget {
  const new({required this.builder, required this.data, super.key});

  final NxMapBuilder builder;
  final NxMapData data;

  @override
  Widget build(BuildContext context) {
    final height = (MediaQuery.sizeOf(context).height * 0.3).clamp(
      200.0,
      320.0,
    );
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: NxRadius.lgAll,
        child: builder(context, data),
      ),
    );
  }
}

/// Explicación propia **antes** del diálogo de permiso del sistema. Devuelve
/// `true` solo si la persona elige continuar.
Future<bool> showGeofenceLocationRationale(BuildContext context) async {
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const GeofenceLocationRationale(),
  );
  return accepted ?? false;
}

class GeofenceLocationRationale extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        NxSpace.gutter,
        0,
        NxSpace.gutter,
        NxSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.geofenceLocationRationaleTitle,
              style: context.text.titleLarge,
            ),
          ),
          const SizedBox(height: NxSpace.sm),
          GeofenceNote(
            icon: Icons.my_location,
            text: l10n.geofenceLocationRationaleOnce,
          ),
          GeofenceNote(
            icon: Icons.groups_outlined,
            text: l10n.geofenceLocationRationaleVisible,
          ),
          GeofenceNote(
            icon: Icons.settings_outlined,
            text: l10n.geofenceLocationRationaleSettings,
          ),
          const SizedBox(height: NxSpace.xs),
          Text(
            l10n.geofenceLocationRationaleNext,
            style: context.text.bodyMedium?.copyWith(
              color: context.nx.inkMuted,
            ),
          ),
          const SizedBox(height: NxSpace.lg),
          NxButton(
            label: l10n.geofenceLocationRationaleContinue,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: NxSpace.xs),
          NxButton(
            label: l10n.geofenceLocationRationaleNotNow,
            variant: NxButtonVariant.tertiary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}

/// Confirma la eliminación de una zona. Devuelve `true` solo si se
/// confirma.
Future<bool> confirmGeofenceDelete(BuildContext context, String name) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.geofenceDeleteTitle(name)),
      content: SingleChildScrollView(child: Text(l10n.geofenceDeleteBody)),
      actions: [
        NxButton(
          label: l10n.commonCancel,
          variant: NxButtonVariant.tertiary,
          expand: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        NxButton(
          label: l10n.geofenceDelete,
          variant: NxButtonVariant.destructive,
          expand: false,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
