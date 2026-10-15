import 'package:flutter/material.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';

/// Encabezado de sección con acción opcional ("Ver todo").
class NxSectionHeader extends StatelessWidget {
  const new({required this.title, super.key, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: NxSpace.lg, bottom: NxSpace.xs),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: context.text.titleMedium),
          ),
        ),
        ?action,
      ],
    ),
  );
}

/// Superficie con borde fino, sin sombra. Úsala con moderación: la mayoría
/// del contenido va directamente sobre el fondo.
class NxSurface extends StatelessWidget {
  const new({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(NxSpace.md),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    return Material(
      color: color ?? c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: NxRadius.lgAll,
        side: BorderSide(color: c.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Contenedor de pantalla: márgenes, ancho máximo y desplazamiento.
class NxPageBody extends StatelessWidget {
  const new({required this.children, super.key, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: NxSpace.maxContentWidth),
      child: ListView(
        padding:
            padding ??
            const EdgeInsets.fromLTRB(
              NxSpace.gutter,
              NxSpace.xs,
              NxSpace.gutter,
              NxSpace.xxl,
            ),
        children: children,
      ),
    ),
  );
}
