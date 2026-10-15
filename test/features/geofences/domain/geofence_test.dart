import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';

// Centro sintético en el océano Atlántico sur.
final _center = GeoPoint(-40, -30);

/// Metros por grado de latitud en el modelo esférico de GeoPoint.
const double _metersPerDegree = 6371008.8 * math.pi / 180;

Geofence _geofence({GeoPoint? center, double radiusMeters = 200}) => Geofence(
  id: 'g1',
  familyId: 'f1',
  name: 'Casa',
  center: center ?? _center,
  radiusMeters: radiusMeters,
  createdBy: 'u1',
  version: 1,
  updatedAt: DateTime.utc(2026),
);

/// Punto a [meters] al norte de [_center], siguiendo el meridiano.
GeoPoint _north(double meters) =>
    GeoPoint(_center.latitude + meters / _metersPerDegree, _center.longitude);

void main() {
  group('GeofenceRules: constantes del contrato', () {
    test('radio entre 100 y 2000 m, 200 por defecto y 10 por familia', () {
      expect(GeofenceRules.minRadiusMeters, 100);
      expect(GeofenceRules.maxRadiusMeters, 2000);
      expect(GeofenceRules.defaultRadiusMeters, 200);
      expect(GeofenceRules.maxNameLength, 40);
      expect(GeofenceRules.maxPerFamily, 10);
      expect(
        GeofenceRules.validate(
          name: 'Casa',
          radiusMeters: GeofenceRules.defaultRadiusMeters,
        ),
        isEmpty,
      );
    });
  });

  group('GeofenceRules.validate: radio', () {
    List<String> radius(double meters) =>
        GeofenceRules.validate(name: 'Casa', radiusMeters: meters);

    test('los extremos 100 y 2000 son válidos', () {
      expect(radius(100), isEmpty);
      expect(radius(2000), isEmpty);
      expect(radius(150.5), isEmpty);
    });

    test('justo fuera de los extremos es inválido', () {
      for (final meters in <double>[99.999, 2000.001, 0, -100, -2000]) {
        expect(radius(meters), [
          'geofence-radius-out-of-range',
        ], reason: '$meters');
      }
    });

    test('NaN e infinitos son inválidos', () {
      for (final meters in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(radius(meters), [
          'geofence-radius-out-of-range',
        ], reason: '$meters');
      }
    });
  });

  group('GeofenceRules.validate: nombre', () {
    List<String> name(String value) =>
        GeofenceRules.validate(name: value, radiusMeters: 200);

    test('exige un nombre que no sea solo espacios', () {
      for (final value in ['', '   ', '\t\n']) {
        expect(name(value), ['geofence-name-required'], reason: value);
      }
    });

    test('admite hasta 40 caracteres tras recortar (límite incluido)', () {
      expect(name('C'), isEmpty);
      expect(name('a' * 40), isEmpty);
      expect(name('  ${'a' * 40}  '), isEmpty);
      expect(name('a' * 41), ['geofence-name-too-long']);
    });

    test('un nombre vacío no es además demasiado largo', () {
      expect(name(' ' * 50), ['geofence-name-required']);
    });
  });

  test('acumula los errores de nombre y radio en orden estable', () {
    expect(GeofenceRules.validate(name: '', radiusMeters: double.nan), [
      'geofence-name-required',
      'geofence-radius-out-of-range',
    ]);
    expect(GeofenceRules.validate(name: 'a' * 41, radiusMeters: 50), [
      'geofence-name-too-long',
      'geofence-radius-out-of-range',
    ]);
  });

  test('los códigos son kebab-case sin dígitos', () {
    final codes = {
      ...GeofenceRules.validate(name: '', radiusMeters: 0),
      ...GeofenceRules.validate(name: 'a' * 41, radiusMeters: 0),
    };
    expect(codes, hasLength(3));
    for (final code in codes) {
      expect(code, matches(RegExp(r'^[a-z]+(-[a-z]+)*$')));
    }
  });

  group('Geofence.contains', () {
    test('contiene su centro', () {
      expect(_geofence().contains(_center), isTrue);
    });

    test('distingue puntos justo dentro y justo fuera del radio', () {
      final geofence = _geofence();
      expect(geofence.contains(_north(199)), isTrue);
      expect(geofence.contains(_north(201)), isFalse);
      expect(geofence.contains(_north(5000)), isFalse);
    });

    test('el borde exacto cuenta como dentro', () {
      final point = _north(150);
      final exact = _center.distanceTo(point);
      expect(_geofence(radiusMeters: exact).contains(point), isTrue);
      expect(_geofence(radiusMeters: exact - 1e-6).contains(point), isFalse);
    });

    test('funciona en todas las direcciones, no solo hacia el norte', () {
      final geofence = _geofence(radiusMeters: 1000);
      // 0,005° de latitud ≈ 556 m; 0,005° de longitud a -40° ≈ 426 m.
      for (final (dLat, dLng) in [
        (0.005, 0.0),
        (-0.005, 0.0),
        (0.0, 0.005),
        (0.0, -0.005),
        (0.005, 0.005),
        (-0.005, -0.005),
      ]) {
        final point = GeoPoint(
          _center.latitude + dLat,
          _center.longitude + dLng,
        );
        expect(geofence.contains(point), isTrue, reason: '($dLat, $dLng)');
      }
      expect(geofence.contains(GeoPoint(-40, -29.98)), isFalse); // ≈ 1,7 km.
    });

    test('al otro lado del antimeridiano también mide bien', () {
      final geofence = _geofence(
        center: GeoPoint(0, 179.999),
        radiusMeters: 500,
      );
      // 0,002° de longitud en el ecuador ≈ 222 m, cruzando ±180.
      expect(geofence.contains(GeoPoint(0, -179.999)), isTrue);
      expect(geofence.contains(GeoPoint(0, -179.99)), isFalse);
    });

    test('un radio inválido (NaN) no contiene ningún punto', () {
      final geofence = _geofence(radiusMeters: double.nan);
      expect(geofence.contains(_center), isFalse);
    });
  });
}
