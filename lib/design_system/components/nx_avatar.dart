import 'package:flutter/material.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';

/// Avatar con iniciales. No usa fotos: menos datos personales.
class NxAvatar extends StatelessWidget {
  const new({
    required this.name,
    super.key,
    this.size = NxSize.avatarMd,
    this.colorSeed = 0,
  });

  final String name;
  final double size;

  /// Índice estable (p. ej. derivado del uid) para variar el tono.
  final int colorSeed;

  static String initialsOf(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    final letters = words.take(2).map((w) => w.characters.first.toUpperCase());
    return letters.join();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    final palette = [
      (c.secondaryContainer, c.onSecondaryContainer),
      (c.positiveContainer, c.onPositiveContainer),
      (c.warningContainer, c.onWarningContainer),
      (c.surfaceAlt, c.ink),
    ];
    final (background, foreground) = palette[colorSeed.abs() % palette.length];
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        // El tamaño del círculo es fijo y las iniciales son decorativas
        // (el nombre se anuncia aparte), así que no se escalan.
        child: Text(
          initialsOf(name),
          textScaler: TextScaler.noScaling,
          style: context.text.titleMedium?.copyWith(
            color: foreground,
            fontSize: size * 0.38,
          ),
        ),
      ),
    );
  }
}
