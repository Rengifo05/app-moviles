import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/emergency/presentation/emergency_providers.dart';
import 'package:nexo_familia/features/emergency/presentation/sos_text.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// "Llamar al 123": abre el marcador con el número configurado
/// (`AppConfig.emergencyNumber`). Si el dispositivo no puede, muestra el
/// número para marcarlo a mano. La app nunca llama por su cuenta.
class SosCallButton extends ConsumerStatefulWidget {
  const new({super.key, this.prominent = false});

  /// Botón principal (cuando llamar es lo más útil: nadie fue notificado,
  /// la alerta no salió…).
  final bool prominent;

  @override
  ConsumerState<SosCallButton> createState() => _SosCallButtonState();
}

class _SosCallButtonState extends ConsumerState<SosCallButton> {
  bool _failed = false;
  bool _opening = false;

  Future<void> _call(String number) async {
    setState(() => _opening = true);
    final opened = await ref.read(emergencyDialerProvider).dial(number);
    if (!mounted) return;
    setState(() {
      _opening = false;
      _failed = !opened;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final number = ref.watch(appConfigProvider).emergencyNumber;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NxButton(
          label: l10n.emergencyCall(number),
          icon: Icons.phone_outlined,
          variant: widget.prominent
              ? NxButtonVariant.primary
              : NxButtonVariant.secondary,
          onPressed: _opening ? null : () => _call(number),
        ),
        if (_failed) ...[
          const SizedBox(height: NxSpace.xs),
          Semantics(
            container: true,
            liveRegion: true,
            label:
                '${l10n.emergencyCallFailed} '
                '${l10n.emergencyCallNumberSemantics(number)}',
            excludeSemantics: true,
            child: Column(
              children: [
                Text(
                  l10n.emergencyCallFailed,
                  style: context.text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                SelectableText(
                  number,
                  style: context.text.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Anillo de la cuenta atrás con la cifra de segundos. El anuncio accesible
/// del tiempo restante va en [semanticsLabel] (región viva).
class SosCountdownRing extends StatelessWidget {
  const new({
    required this.secondsLeft,
    required this.fraction,
    required this.semanticsLabel,
    super.key,
  });

  final int secondsLeft;
  final double fraction;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    return Semantics(
      container: true,
      liveRegion: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: NxSize.sosButton,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CircularProgressIndicator(
                value: fraction.clamp(0, 1),
                strokeWidth: 8,
                color: c.emergency,
                backgroundColor: c.emergencyContainer,
              ),
            ),
            Text(
              '$secondsLeft',
              // El anillo tiene tamaño fijo: la cifra crece hasta 1,5×.
              textScaler: MediaQuery.textScalerOf(context)
                  .clamp(maxScaleFactor: 1.5),
              style: context.text.displayLarge?.copyWith(
                color: c.ink,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Línea de estados de la alerta propia: un paso por fila, con ícono, texto
/// y color (nunca solo color).
class SosStepList extends StatelessWidget {
  const new({required this.steps, super.key});

  final List<SosStep> steps;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, step) in steps.indexed)
        _StepRow(step: step, isLast: index == steps.length - 1),
    ],
  );
}

class _StepRow extends StatelessWidget {
  const new({required this.step, required this.isLast});

  final SosStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    final iconSize = nxScaledIcon(context, NxSize.iconMd);
    final (IconData? icon, Color color) = switch (step.kind) {
      SosStepKind.done => (Icons.check_circle_outline, c.positive),
      SosStepKind.inProgress => (null, c.secondary),
      SosStepKind.waiting => (Icons.schedule, c.inkMuted),
      SosStepKind.warning => (Icons.error_outline, c.warning),
      SosStepKind.error => (Icons.cancel_outlined, c.emergency),
    };
    final leading = icon == null
        ? SizedBox.square(
            dimension: iconSize,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
            ),
          )
        : Icon(icon, size: iconSize, color: color);
    return MergeSemantics(
      child: Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : NxSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: leading),
            const SizedBox(width: NxSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.text,
                    style: context.text.bodyLarge?.copyWith(
                      color: step.kind == SosStepKind.waiting
                          ? c.inkMuted
                          : c.ink,
                      // Se destaca lo que pide atención; lo hecho y lo que
                      // se espera van en peso normal.
                      fontWeight: switch (step.kind) {
                        SosStepKind.done || SosStepKind.waiting => null,
                        SosStepKind.inProgress ||
                        SosStepKind.warning ||
                        SosStepKind.error => FontWeight.w600,
                      },
                    ),
                  ),
                  if (step.note case final note?) ...[
                    const SizedBox(height: NxSpace.xxs),
                    Text(
                      note,
                      style: context.text.bodyMedium?.copyWith(
                        color: c.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
