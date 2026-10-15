import 'package:flutter/material.dart';

/// Paleta semántica de Nexo Familia.
///
/// Cada color de texto o ícono se valida contra los fondos donde se usa
/// (`test/design_system/contrast_test.dart`): ≥ 4,5:1 para texto normal.
/// Los estados nunca se comunican solo con color: siempre acompañan un ícono
/// y un texto.
@immutable
final class NxColors extends ThemeExtension<NxColors> {
  const new({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkMuted,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.positive,
    required this.positiveContainer,
    required this.onPositiveContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.emergency,
    required this.emergencyFill,
    required this.onEmergencyFill,
    required this.emergencyContainer,
    required this.onEmergencyContainer,
    required this.outline,
    required this.outlineStrong,
    required this.focus,
  });

  /// Marfil cálido, azul marino profundo, salvia, azul suave, ámbar y coral.
  static const light = NxColors(
    background: Color(0xFFFAF7F0),
    surface: Color(0xFFFFFDF9),
    surfaceAlt: Color(0xFFF2EDE3),
    ink: Color(0xFF14284B),
    inkMuted: Color(0xFF4B5568),
    primary: Color(0xFF14284B),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF3F64A0),
    secondaryContainer: Color(0xFFDCE6F5),
    onSecondaryContainer: Color(0xFF1C3A6B),
    positive: Color(0xFF4F6F55),
    positiveContainer: Color(0xFFDCE7D8),
    onPositiveContainer: Color(0xFF24402B),
    warning: Color(0xFF8A5A00),
    warningContainer: Color(0xFFF7E6C1),
    onWarningContainer: Color(0xFF5C3D00),
    emergency: Color(0xFFA9352F),
    emergencyFill: Color(0xFFC2413A),
    onEmergencyFill: Color(0xFFFFFFFF),
    emergencyContainer: Color(0xFFF8DDD9),
    onEmergencyContainer: Color(0xFF7A2420),
    outline: Color(0xFFD9D3C7),
    outlineStrong: Color(0xFF857E70),
    focus: Color(0xFF3F64A0),
  );

  static const dark = NxColors(
    background: Color(0xFF0F1828),
    surface: Color(0xFF162236),
    surfaceAlt: Color(0xFF1E2D46),
    ink: Color(0xFFF4EFE6),
    inkMuted: Color(0xFFB9C2D0),
    primary: Color(0xFFBFD3F2),
    onPrimary: Color(0xFF0F1F3D),
    secondary: Color(0xFF9DB8E6),
    secondaryContainer: Color(0xFF1F3354),
    onSecondaryContainer: Color(0xFFD6E3F8),
    positive: Color(0xFF93BD9C),
    positiveContainer: Color(0xFF23382A),
    onPositiveContainer: Color(0xFFC9E3CE),
    warning: Color(0xFFE6B860),
    warningContainer: Color(0xFF3D2E10),
    onWarningContainer: Color(0xFFF6DDA8),
    emergency: Color(0xFFFF9289),
    emergencyFill: Color(0xFFB8382F),
    onEmergencyFill: Color(0xFFFFFFFF),
    emergencyContainer: Color(0xFF4A1F1C),
    onEmergencyContainer: Color(0xFFFFD6D1),
    outline: Color(0xFF2E3D57),
    outlineStrong: Color(0xFF7D8AA0),
    focus: Color(0xFF9DB8E6),
  );

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color ink;
  final Color inkMuted;
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color positive;
  final Color positiveContainer;
  final Color onPositiveContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;

  /// Texto e íconos de emergencia sobre fondos neutros.
  final Color emergency;

  /// Relleno del botón SOS (reservado exclusivamente para emergencias).
  final Color emergencyFill;
  final Color onEmergencyFill;
  final Color emergencyContainer;
  final Color onEmergencyContainer;

  /// Bordes decorativos (no transmiten información).
  final Color outline;

  /// Bordes de controles (≥ 3:1 frente al fondo).
  final Color outlineStrong;
  final Color focus;

  @override
  NxColors copyWith() => this;

  @override
  NxColors lerp(NxColors? other, double t) => t < 0.5 ? this : other ?? this;
}
