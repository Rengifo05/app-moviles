import 'package:flutter/widgets.dart';

/// Espaciado en una escala de 4 pt.
abstract final class NxSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Margen lateral de las pantallas.
  static const double gutter = 20;

  /// Ancho máximo del contenido en tabletas y pantallas anchas.
  static const double maxContentWidth = 640;
}

abstract final class NxRadius {
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 22;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

abstract final class NxSize {
  /// Área táctil mínima (Android 48 dp; iOS 44 pt).
  static const double minTouchTarget = 48;
  static const double iconSm = 18;
  static const double iconMd = 24;
  static const double iconLg = 32;
  static const double avatarMd = 44;
  static const double avatarLg = 72;
  static const double sosButton = 168;
}

/// Duraciones de animación. Las animaciones son sutiles y funcionales y se
/// desactivan cuando el sistema pide reducir el movimiento.
abstract final class NxMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Curve standard = Curves.easeOutCubic;

  /// Duración efectiva según la preferencia de movimiento reducido.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// Tamaño de un ícono que acompaña a un texto: crece con el tamaño de texto
/// del sistema (hasta el doble) para mantener la proporción.
double nxScaledIcon(BuildContext context, double size) =>
    MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2).scale(size);
