import 'package:flutter/material.dart';
import 'package:nexo_familia/design_system/tokens/nx_colors.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';

/// Tema de la app construido a partir de los tokens.
abstract final class NxTheme {
  static ThemeData light() => _build(NxColors.light, Brightness.light);

  static ThemeData dark() => _build(NxColors.dark, Brightness.dark);

  static ThemeData _build(NxColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.secondary,
      onSecondary: c.onPrimary,
      secondaryContainer: c.secondaryContainer,
      onSecondaryContainer: c.onSecondaryContainer,
      error: c.emergency,
      onError: c.onEmergencyFill,
      errorContainer: c.emergencyContainer,
      onErrorContainer: c.onEmergencyContainer,
      surface: c.background,
      onSurface: c.ink,
      onSurfaceVariant: c.inkMuted,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceAlt,
      surfaceContainerHighest: c.surfaceAlt,
      outline: c.outlineStrong,
      outlineVariant: c.outline,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: c.background,
      extensions: [c],
    );
    // `ThemeData.textTheme` no trae tamaños: Flutter aplica la geometría
    // tipográfica después, en `Theme.of`. Se fusiona aquí para que los
    // estilos que reciben los subtemas (AppBar, NavigationBar…) la tengan.
    final text = _textTheme(
      Typography.englishLike2021.merge(base.textTheme),
      c,
    );

    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.secondaryContainer,
        elevation: 0,
        height: 72,
        labelTextStyle: WidgetStatePropertyAll(
          text.labelMedium?.copyWith(color: c.ink),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? c.onSecondaryContainer
                : c.inkMuted,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.outline, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: c.inkMuted,
        textColor: c.ink,
        minVerticalPadding: NxSpace.sm,
        contentPadding: const EdgeInsets.symmetric(horizontal: NxSpace.md),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(
          borderRadius: NxRadius.mdAll,
          borderSide: BorderSide(color: c.outlineStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: NxRadius.mdAll,
          borderSide: BorderSide(color: c.outlineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: NxRadius.mdAll,
          borderSide: BorderSide(color: c.focus, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: NxRadius.mdAll,
          borderSide: BorderSide(color: c.emergency),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: NxSpace.md,
          vertical: NxSpace.md,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.background),
        shape: const RoundedRectangleBorder(borderRadius: NxRadius.mdAll),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(NxRadius.lg),
          ),
        ),
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
  }

  static TextTheme _textTheme(TextTheme base, NxColors c) {
    TextStyle? tune(TextStyle? s, {FontWeight? weight, double? spacing}) =>
        s?.copyWith(color: c.ink, fontWeight: weight, letterSpacing: spacing);
    return base.copyWith(
      displaySmall: tune(
        base.displaySmall,
        weight: FontWeight.w600,
        spacing: -0.5,
      ),
      headlineMedium: tune(
        base.headlineMedium,
        weight: FontWeight.w600,
        spacing: -0.3,
      ),
      headlineSmall: tune(
        base.headlineSmall,
        weight: FontWeight.w600,
        spacing: -0.2,
      ),
      titleLarge: tune(base.titleLarge, weight: FontWeight.w600),
      titleMedium: tune(base.titleMedium, weight: FontWeight.w600),
      titleSmall: tune(base.titleSmall, weight: FontWeight.w600),
      bodyLarge: tune(base.bodyLarge),
      bodyMedium: tune(base.bodyMedium),
      bodySmall: base.bodySmall?.copyWith(color: c.inkMuted),
      labelLarge: tune(base.labelLarge, weight: FontWeight.w600),
      labelMedium: tune(base.labelMedium),
      labelSmall: base.labelSmall?.copyWith(color: c.inkMuted),
    );
  }
}

/// Acceso cómodo a los tokens desde un `BuildContext`.
extension NxThemeContext on BuildContext {
  NxColors get nx => Theme.of(this).extension<NxColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
}
