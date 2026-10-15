import 'package:flutter/material.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Explicación propia **antes** del diálogo de permiso del sistema: para qué
/// se usa la ubicación, quién la ve, cuándo y que se puede pausar.
///
/// Devuelve `true` solo si la persona elige continuar; cerrar la hoja o
/// pulsar "Ahora no" no pide nada.
Future<bool> showLocationPermissionRationale(
  BuildContext context, {
  String? familyName,
}) async {
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => LocationPermissionRationale(familyName: familyName),
  );
  return accepted ?? false;
}

class LocationPermissionRationale extends StatelessWidget {
  const new({super.key, this.familyName});

  final String? familyName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = familyName?.trim();
    // Las acciones quedan siempre a la vista; con texto grande se desplaza
    // solo la explicación.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: NxSpace.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.locationRationaleTitle,
                    style: context.text.titleLarge,
                  ),
                ),
                const SizedBox(height: NxSpace.md),
                _Point(
                  icon: Icons.map_outlined,
                  text: l10n.locationRationaleWhat,
                ),
                _Point(
                  icon: Icons.groups_outlined,
                  text: name == null || name.isEmpty
                      ? l10n.locationRationaleWhoGeneric
                      : l10n.locationRationaleWho(name),
                ),
                _Point(
                  icon: Icons.phone_android_outlined,
                  text: l10n.locationRationaleWhen,
                ),
                _Point(
                  icon: Icons.pause_circle_outline,
                  text: l10n.locationRationalePause,
                ),
                const SizedBox(height: NxSpace.xs),
                Text(
                  l10n.locationRationaleNext,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.nx.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NxSpace.gutter,
            NxSpace.md,
            NxSpace.gutter,
            NxSpace.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NxButton(
                label: l10n.locationRationaleContinue,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: NxSpace.xs),
              NxButton(
                label: l10n.locationRationaleNotNow,
                variant: NxButtonVariant.tertiary,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const new({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: NxSpace.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(
            icon,
            color: context.nx.secondary,
            size: nxScaledIcon(context, NxSize.iconMd),
          ),
        ),
        const SizedBox(width: NxSpace.sm),
        Expanded(child: Text(text, style: context.text.bodyLarge)),
      ],
    ),
  );
}
