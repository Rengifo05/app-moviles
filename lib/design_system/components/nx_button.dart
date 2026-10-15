import 'package:flutter/material.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';

enum NxButtonVariant { primary, secondary, tertiary, destructive }

/// Botón de la app. Ocupa todo el ancho por defecto (uso con una mano) y
/// garantiza un área táctil ≥ 48 dp. Con [loading] se desactiva y anuncia
/// el progreso a los lectores de pantalla.
class NxButton extends StatelessWidget {
  const new({
    required this.label,
    required this.onPressed,
    super.key,
    this.variant = NxButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final NxButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    final enabled = onPressed != null && !loading;
    final (background, foreground, border) = switch (variant) {
      NxButtonVariant.primary => (c.primary, c.onPrimary, null),
      NxButtonVariant.secondary => (
        c.surface,
        c.ink,
        BorderSide(color: c.outlineStrong),
      ),
      NxButtonVariant.tertiary => (Colors.transparent, c.secondary, null),
      NxButtonVariant.destructive => (
        c.surface,
        c.emergency,
        BorderSide(color: c.emergency),
      ),
    };

    final child = loading
        ? SizedBox.square(
            dimension: NxSize.iconSm,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: nxScaledIcon(context, NxSize.iconSm)),
                const SizedBox(width: NxSpace.xs),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  // En varias líneas, el ancho es el de la línea más larga:
                  // el ícono queda junto al texto y no en el borde.
                  textWidthBasis: TextWidthBasis.longestLine,
                ),
              ),
            ],
          );

    final button = TextButton(
      onPressed: enabled ? onPressed : null,
      style: TextButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: variant == NxButtonVariant.tertiary
            ? Colors.transparent
            : c.surfaceAlt,
        disabledForegroundColor: c.inkMuted,
        minimumSize: const Size(NxSize.minTouchTarget, NxSize.minTouchTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: NxSpace.lg,
          vertical: NxSpace.sm + 2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: NxRadius.mdAll,
          side: enabled ? (border ?? BorderSide.none) : BorderSide.none,
        ),
        textStyle: context.text.labelLarge,
      ),
      child: child,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? label : null,
      excludeSemantics: loading,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}
