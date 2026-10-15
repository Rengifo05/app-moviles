import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/design_system/tokens/nx_colors.dart';

/// Relación de contraste WCAG 2.x entre dos colores opacos.
double contrastRatio(Color a, Color b) {
  double channel(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final la = luminance(a);
  final lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

typedef Pair = (String name, Color foreground, Color background);

/// Todos los pares texto/fondo que usan los componentes.
List<Pair> textPairs(NxColors c) => [
  for (final (bgName, bg) in [
    ('background', c.background),
    ('surface', c.surface),
    ('surfaceAlt', c.surfaceAlt),
  ]) ...[
    ('ink/$bgName', c.ink, bg),
    ('inkMuted/$bgName', c.inkMuted, bg),
    ('secondary/$bgName', c.secondary, bg),
    ('positive/$bgName', c.positive, bg),
    ('warning/$bgName', c.warning, bg),
    ('emergency/$bgName', c.emergency, bg),
  ],
  ('onPrimary/primary', c.onPrimary, c.primary),
  ('onEmergencyFill/emergencyFill', c.onEmergencyFill, c.emergencyFill),
  (
    'onSecondaryContainer/secondaryContainer',
    c.onSecondaryContainer,
    c.secondaryContainer,
  ),
  (
    'onPositiveContainer/positiveContainer',
    c.onPositiveContainer,
    c.positiveContainer,
  ),
  (
    'onWarningContainer/warningContainer',
    c.onWarningContainer,
    c.warningContainer,
  ),
  (
    'onEmergencyContainer/emergencyContainer',
    c.onEmergencyContainer,
    c.emergencyContainer,
  ),
  ('background/ink (snackbar)', c.background, c.ink),
];

/// Pares de elementos no textuales (bordes de controles, foco): ≥ 3:1.
List<Pair> nonTextPairs(NxColors c) => [
  ('outlineStrong/background', c.outlineStrong, c.background),
  ('outlineStrong/surface', c.outlineStrong, c.surface),
  ('focus/background', c.focus, c.background),
  ('focus/surface', c.focus, c.surface),
  ('emergency ring/emergencyContainer', c.emergency, c.emergencyContainer),
];

void main() {
  for (final (mode, colors) in [
    ('claro', NxColors.light),
    ('oscuro', NxColors.dark),
  ]) {
    group('contraste en modo $mode', () {
      for (final (name, fg, bg) in textPairs(colors)) {
        test('texto $name ≥ 4,5:1', () {
          expect(contrastRatio(fg, bg), greaterThanOrEqualTo(4.5));
        });
      }
      for (final (name, fg, bg) in nonTextPairs(colors)) {
        test('elemento $name ≥ 3:1', () {
          expect(contrastRatio(fg, bg), greaterThanOrEqualTo(3));
        });
      }
    });
  }

  test('la fórmula coincide con valores de referencia', () {
    expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
    expect(
      contrastRatio(const Color(0xFF14284B), const Color(0xFFFAF7F0)),
      closeTo(13.68, 0.01),
    );
  });
}
