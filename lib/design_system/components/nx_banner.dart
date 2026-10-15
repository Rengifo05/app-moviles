import 'package:flutter/material.dart';
import 'package:nexo_familia/design_system/components/nx_status_pill.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';

/// Aviso persistente en la parte superior de una pantalla (sin conexión,
/// permiso denegado, datos antiguos…). Incluye una acción concreta.
class NxBanner extends StatelessWidget {
  const new({
    required this.icon,
    required this.message,
    super.key,
    this.tone = NxTone.warning,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final NxTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

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
      liveRegion: true,
      child: Material(
        color: background,
        borderRadius: NxRadius.mdAll,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            NxSpace.md,
            NxSpace.sm,
            NxSpace.xs,
            NxSpace.sm,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final icon = Icon(
                this.icon,
                color: foreground,
                size: nxScaledIcon(context, NxSize.iconMd),
              );
              final text = Text(
                message,
                style: context.text.bodyMedium?.copyWith(color: foreground),
              );
              final action = actionLabel == null
                  ? null
                  : TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: foreground,
                        minimumSize: const Size(
                          NxSize.minTouchTarget,
                          NxSize.minTouchTarget,
                        ),
                        textStyle: context.text.labelLarge,
                      ),
                      child: Text(actionLabel!),
                    );
              // Con texto grande o poco ancho, la acción va debajo para no
              // partir el mensaje en fragmentos ilegibles.
              final stacked =
                  MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
                  constraints.maxWidth < 320;
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        icon,
                        const SizedBox(width: NxSpace.sm),
                        Expanded(child: text),
                      ],
                    ),
                    if (action != null)
                      Align(alignment: Alignment.centerRight, child: action),
                  ],
                );
              }
              return Row(
                children: [
                  icon,
                  const SizedBox(width: NxSpace.sm),
                  Expanded(child: text),
                  ?action,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
