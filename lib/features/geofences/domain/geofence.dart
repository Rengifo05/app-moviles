import 'package:meta/meta.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/core/text.dart';

/// Zona segura de una familia ("Casa", "Colegio"…).
@immutable
final class Geofence {
  const new({
    required this.id,
    required this.familyId,
    required this.name,
    required this.center,
    required this.radiusMeters,
    required this.createdBy,
    required this.version,
    required this.updatedAt,
  });

  final String id;
  final String familyId;
  final String name;
  final GeoPoint center;
  final double radiusMeters;
  final String createdBy;

  /// Control de concurrencia optimista: cada edición incrementa la versión.
  final int version;
  final DateTime updatedAt;

  bool contains(GeoPoint point) => center.distanceTo(point) <= radiusMeters;
}

enum GeofenceTransition { enter, exit }

abstract final class GeofenceRules {
  static const double minRadiusMeters = 100;
  static const double maxRadiusMeters = 2000;
  static const double defaultRadiusMeters = 200;
  static const int maxNameLength = 40;

  /// Por debajo del límite de 20 regiones de iOS (ADR-003).
  static const int maxPerFamily = 10;

  static List<String> validate({
    required String name,
    required double radiusMeters,
  }) {
    final trimmed = name.trim();
    return [
      if (trimmed.isEmpty || !hasVisibleContent(trimmed))
        'geofence-name-required',
      if (trimmed.length > maxNameLength) 'geofence-name-too-long',
      if (!radiusMeters.isFinite ||
          radiusMeters < minRadiusMeters ||
          radiusMeters > maxRadiusMeters)
        'geofence-radius-out-of-range',
    ];
  }
}

abstract interface class GeofenceRepository {
  Stream<List<Geofence>> watchGeofences(String familyId);

  Future<Result<Geofence>> create({
    required String familyId,
    required String name,
    required GeoPoint center,
    required double radiusMeters,
  });

  /// Falla con `conflict` si otro integrante la modificó antes.
  Future<Result<Geofence>> update(Geofence updated);

  Future<VoidResult> delete(Geofence geofence);
}
