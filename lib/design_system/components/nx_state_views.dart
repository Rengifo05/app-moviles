import 'package:flutter/material.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';

/// Estado vacío, de error o informativo a pantalla (o sección) completa.
/// Siempre explica el problema y el siguiente paso.
class NxMessageView extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    super.key,
    this.body,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(NxSpace.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: NxSize.iconLg + 8, color: c.inkMuted),
              const SizedBox(height: NxSpace.md),
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: context.text.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              if (body case final body? when body.isNotEmpty) ...[
                const SizedBox(height: NxSpace.xs),
                Text(
                  body,
                  style: context.text.bodyMedium?.copyWith(color: c.inkMuted),
                  textAlign: TextAlign.center,
                ),
              ],
              if (actionLabel != null) ...[
                const SizedBox(height: NxSpace.lg),
                NxButton(label: actionLabel!, onPressed: onAction),
              ],
              if (secondaryActionLabel != null) ...[
                const SizedBox(height: NxSpace.xs),
                NxButton(
                  label: secondaryActionLabel!,
                  onPressed: onSecondaryAction,
                  variant: NxButtonVariant.tertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Indicador de carga accesible.
class NxLoadingView extends StatelessWidget {
  const new({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      label: label,
      liveRegion: true,
      child: const CircularProgressIndicator(),
    ),
  );
}
