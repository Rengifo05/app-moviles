import 'package:flutter/widgets.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';

/// Estado visual de un marcador. Siempre se acompaña de texto accesible.
enum NxMarkerTone { recent, stale, emergency }

/// Marcador de un integrante en el mapa.
@immutable
final class NxMapMarker {
  const new({
    required this.id,
    required this.label,
    required this.point,
    required this.tone,
    required this.semanticsLabel,
    this.isSelf = false,
    this.isApproximate = false,
  });

  final String id;

  /// Texto corto sobre el marcador (nombre o iniciales).
  final String label;
  final GeoPoint point;
  final NxMarkerTone tone;

  /// Descripción completa para lectores de pantalla, p. ej.
  /// "Ana. Ubicación actualizada hace 3 minutos".
  final String semanticsLabel;
  final bool isSelf;

  /// La persona comparte una ubicación aproximada (≈ 1 km).
  final bool isApproximate;
}

/// Zona segura dibujada como círculo.
@immutable
final class NxMapZone {
  const new({
    required this.id,
    required this.name,
    required this.center,
    required this.radiusMeters,
  });

  final String id;
  final String name;
  final GeoPoint center;
  final double radiusMeters;
}

/// Datos que recibe cualquier implementación del mapa.
@immutable
final class NxMapData {
  const new({
    required this.markers,
    required this.zones,
    this.selectedMarkerId,
    this.onMarkerTap,
    this.onPickPoint,
    this.pickedPoint,
    this.initialCenter,
  });

  final List<NxMapMarker> markers;
  final List<NxMapZone> zones;
  final String? selectedMarkerId;
  final ValueChanged<String>? onMarkerTap;

  /// Si no es nulo, el mapa permite elegir un punto (crear una zona).
  final ValueChanged<GeoPoint>? onPickPoint;
  final GeoPoint? pickedPoint;
  final GeoPoint? initialCenter;
}

/// Construye la vista del mapa. La implementación concreta (Google Maps,
/// MapKit o la lista accesible) la inyecta la raíz de composición, de modo
/// que ni la lógica de negocio ni las pantallas dependen del proveedor
/// (ADR-002).
typedef NxMapBuilder = Widget Function(BuildContext context, NxMapData data);
