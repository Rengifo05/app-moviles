import 'package:flutter/material.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';

/// Tono de un estado. El color nunca va solo: siempre hay ícono y texto.
enum NxTone { neutral, info, positive, warning, emergency }

/// Etiqueta compacta de estado ("Actualizada hace 2 min", "Sin conexión").
class NxStatusPill extends StatelessWidget {
  const new({
    required this.label,
    required this.icon,
    super.key,
    this.tone = NxTone.neutral,
  });

  final String label;
  final IconData icon;
  final NxTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    final (background, foreground) = switch (tone) {
      NxTone.neutral => (c.surfaceAlt, c.ink),
      NxTone.info => (c.secondaryContainer, c.onSecondaryContainer),
      NxTone.positive => (c.positiveContainer, c.onPositiveContainer),
      NxTone.warning => (c.warningContainer, c.onWarningContainer),
      NxTone.emergency => (c.emergencyContainer, c.onEmergencyContainer),
    };
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: NxRadius.pillAll,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NxSpace.sm,
            vertical: NxSpace.xxs + 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: nxScaledIcon(context, NxSize.iconSm - 2),
                color: foreground,
              ),
              const SizedBox(width: NxSpace.xxs + 2),
              Flexible(
                child: Text(
                  label,
                  style: context.text.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
