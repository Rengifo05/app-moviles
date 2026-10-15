import 'dart:math' as math;

import 'package:meta/meta.dart';

/// Coordenada geográfica validada (WGS84, grados decimales).
///
/// Es un dato sensible: nunca se registra en logs (ver `SafeLogger`) y su
/// `toString` no expone los valores.
@immutable
final class GeoPoint {
  /// Lanza [ArgumentError] si la coordenada está fuera de rango o no es
  /// finita. Usa [tryCreate] para datos que vienen de fuera.
  new(this.latitude, this.longitude) {
    if (!isValid(latitude, longitude)) {
      throw ArgumentError('Coordenada fuera de rango');
    }
  }

  static GeoPoint? tryCreate(double latitude, double longitude) =>
      isValid(latitude, longitude) ? GeoPoint(latitude, longitude) : null;

  static bool isValid(double latitude, double longitude) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  final double latitude;
  final double longitude;

  static const double _earthRadiusMeters = 6371008.8;

  /// Distancia ortodrómica (fórmula del haverseno), en metros.
  double distanceTo(GeoPoint other) {
    double rad(double deg) => deg * math.pi / 180;
    final dLat = rad(other.latitude - latitude);
    final dLng = rad(other.longitude - longitude);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(latitude)) *
            math.cos(rad(other.latitude)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * _earthRadiusMeters * math.asin(math.min(1, math.sqrt(a)));
  }

  /// Versión aproximada (≈ 1 km) para la compartición con precisión
  /// reducida: redondea a 2 decimales (0,01° ≈ 1,1 km de latitud).
  ///
  /// El resultado es canónico: dos puntos que caen en la misma posición
  /// aproximada dan exactamente los mismos valores. Si no, lo que se
  /// serializa revelaría más que la celda: el signo de -0,0 (de qué lado del
  /// ecuador o de Greenwich), -180 frente a 180 (de qué lado del
  /// antimeridiano) o la longitud en un polo (el rumbo exacto desde él).
  GeoPoint approximate() {
    // Sumar 0,0 convierte -0,0 en 0,0 (IEEE 754).
    double snap(double degrees) => (degrees * 100).roundToDouble() / 100 + 0.0;
    final lat = snap(latitude);
    if (lat.abs() == 90) return GeoPoint(lat, 0);
    final lng = snap(longitude);
    return GeoPoint(lat, lng == -180 ? 180 : lng);
  }

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  // Sin coordenadas: evita filtrarlas por accidente en registros o errores.
  @override
  String toString() => 'GeoPoint(<oculto>)';
}
