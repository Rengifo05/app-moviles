import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';

/// Botón circular que solo se activa tras mantenerlo pulsado [holdDuration].
///
/// Pensado para el SOS: es fácil de encontrar pero resistente a toques
/// accidentales. Un toque corto no hace nada salvo mostrar [hint]. Para
/// lectores de pantalla, la acción de "mantener pulsado" del sistema
/// (doble toque sostenido) activa el botón.
class NxHoldButton extends StatefulWidget {
  const new({
    required this.label,
    required this.hint,
    required this.onConfirmed,
    super.key,
    this.holdDuration = const Duration(seconds: 2),
    this.size = NxSize.sosButton,
    this.icon,
  });

  final String label;

  /// Instrucción ("Mantén pulsado 2 segundos").
  final String hint;
  final VoidCallback onConfirmed;
  final Duration holdDuration;
  final double size;

  /// Ícono opcional sobre la etiqueta.
  final IconData? icon;

  @override
  State<NxHoldButton> createState() => _NxHoldButtonState();
}

class _NxHoldButtonState extends State<NxHoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  )..addStatusListener(_onStatus);

  bool _showHint = false;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      unawaited(HapticFeedback.heavyImpact());
      _progress.reset();
      widget.onConfirmed();
    }
  }

  void _start() {
    unawaited(HapticFeedback.selectionClick());
    setState(() => _showHint = false);
    _progress.forward(from: 0);
  }

  void _cancel() {
    if (_progress.isAnimating) {
      _progress.reverse();
      setState(() => _showHint = true);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: widget.label,
          hint: widget.hint,
          onLongPress: widget.onConfirmed,
          excludeSemantics: true,
          child: GestureDetector(
            onTapDown: (_) => _start(),
            onTapUp: (_) => _cancel(),
            onTapCancel: _cancel,
            child: SizedBox.square(
              dimension: widget.size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _progress,
                      builder: (context, _) => CircularProgressIndicator(
                        value: _progress.value,
                        strokeWidth: 6,
                        color: c.emergency,
                        backgroundColor: c.emergencyContainer,
                      ),
                    ),
                  ),
                  Container(
                    width: widget.size - 20,
                    height: widget.size - 20,
                    decoration: BoxDecoration(
                      color: c.emergencyFill,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon case final icon?) ...[
                          Icon(
                            icon,
                            color: c.onEmergencyFill,
                            size: NxSize.iconLg + 8,
                          ),
                          const SizedBox(height: NxSpace.xxs),
                        ],
                        Text(
                          widget.label,
                          // El círculo tiene tamaño fijo: se limita el
                          // escalado para que la etiqueta no se desborde.
                          textScaler: MediaQuery.textScalerOf(context)
                              .clamp(maxScaleFactor: 1.3),
                          style: context.text.headlineSmall?.copyWith(
                            color: c.onEmergencyFill,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: NxSpace.sm),
        AnimatedOpacity(
          opacity: _showHint ? 1 : 0.85,
          duration: NxMotion.of(context, NxMotion.fast),
          child: Text(
            widget.hint,
            style: context.text.bodyMedium?.copyWith(
              color: _showHint ? c.ink : c.inkMuted,
              fontWeight: _showHint ? FontWeight.w600 : null,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
