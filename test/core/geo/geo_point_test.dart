import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';

// Todas las coordenadas son sintéticas (puntos en el océano o valores
// redondos); ninguna corresponde a una persona ni a un domicilio.

/// Radio medio de la Tierra (IUGG) que usa el modelo esférico de GeoPoint.
const _r = 6371008.8;

/// Los valores tal como salen del dispositivo (JSON de la bandeja de salida).
String _wire(GeoPoint p) => jsonEncode([p.latitude, p.longitude]);

/// Valores de referencia calculados aparte con la fórmula de Vincenty sobre
/// la esfera (atan2), distinta del haverseno que usa la implementación:
///
/// ```python
/// num = hypot(cos(p2)*sin(dl), cos(p1)*sin(p2) - sin(p1)*cos(p2)*cos(dl))
/// den = sin(p1)*sin(p2) + cos(p1)*cos(p2)*cos(dl)
/// d = 6371008.8 * atan2(num, den)
/// ```
const _references = <(double, double, double, double, double)>[
  // (lat1, lng1, lat2, lng2, metros)
  (0, 0, 0, 90, 10007557.221017962), // Un cuarto de meridiano: πR/2.
  (0, 0, 0, 180, 20015114.442035925), // Antípodas en el ecuador: πR.
  (90, 0, -90, 0, 20015114.442035925), // De polo a polo: πR.
  (45, 45, -45, -135, 20015114.442035925), // Antípodas fuera del ecuador.
  (0, 0, 1, 0, 111195.0802335329), // 1° de latitud.
  (0, 0, 0, 1, 111195.0802335329), // 1° de longitud en el ecuador.
  (0, 179.5, 0, -179.5, 111195.08023353321), // Cruza el antimeridiano.
  (60, 10, 60, 11, 55597.01086489693), // 1° de longitud a 60°: la mitad.
  (89.9, 0, 89.9, 180, 22239.01604670598), // Pasa por encima del polo.
  (-40, -30, -41.5, -25, 452921.62372733175), // Atlántico sur.
  (0.5, -160, -0.5, -160.25, 114617.17963793005), // Pacífico, cruza el ecuador.
  (-40, -30, -40, -29.99, 851.803732704099), // 0,01° de longitud a -40°.
  (-40, -30, -40.01, -30, 1111.9508023354329), // 0,01° de latitud.
];

void main() {
  group('GeoPoint: validación', () {
    test('acepta los extremos exactos ±90 y ±180', () {
      for (final (lat, lng) in [
        (90.0, 180.0),
        (-90.0, -180.0),
        (90.0, -180.0),
        (-90.0, 180.0),
        (0.0, 0.0),
        (-0.0, -0.0),
      ]) {
        expect(GeoPoint.isValid(lat, lng), isTrue, reason: '($lat, $lng)');
        expect(GeoPoint.tryCreate(lat, lng), isNotNull);
        expect(() => GeoPoint(lat, lng), returnsNormally);
      }
    });

    test('rechaza valores justo fuera de rango', () {
      const epsilon = 1e-9;
      for (final (lat, lng) in [
        (90 + epsilon, 0.0),
        (-90 - epsilon, 0.0),
        (0.0, 180 + epsilon),
        (0.0, -180 - epsilon),
        (180.0, 90.0), // Latitud y longitud intercambiadas.
        (-1000.0, 1000.0),
      ]) {
        expect(GeoPoint.isValid(lat, lng), isFalse, reason: '($lat, $lng)');
        expect(GeoPoint.tryCreate(lat, lng), isNull);
        expect(() => GeoPoint(lat, lng), throwsArgumentError);
      }
    });

    test('rechaza NaN e infinitos en cualquiera de los dos ejes', () {
      const invalid = [double.nan, double.infinity, double.negativeInfinity];
      for (final bad in invalid) {
        expect(GeoPoint.isValid(bad, 0), isFalse, reason: 'lat $bad');
        expect(GeoPoint.isValid(0, bad), isFalse, reason: 'lng $bad');
        expect(GeoPoint.tryCreate(bad, 0), isNull);
        expect(GeoPoint.tryCreate(0, bad), isNull);
        expect(() => GeoPoint(bad, 0), throwsArgumentError);
        expect(() => GeoPoint(0, bad), throwsArgumentError);
      }
    });

    test('el error de construcción no incluye la coordenada', () {
      expect(
        () => GeoPoint(91.234567, -12.345678),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'texto',
            allOf(
              contains('Coordenada fuera de rango'),
              isNot(contains('91.2')),
              isNot(contains('12.3')),
            ),
          ),
        ),
      );
    });

    test('tryCreate conserva los valores exactos', () {
      final point = GeoPoint.tryCreate(-12.345678, -98.765432)!;
      expect(point.latitude, -12.345678);
      expect(point.longitude, -98.765432);
    });
  });

  group('GeoPoint: igualdad y texto', () {
    test('dos puntos con las mismas coordenadas son iguales', () {
      final a = GeoPoint(-12.5, -98.25);
      final b = GeoPoint(-12.5, -98.25);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect({a, b}, hasLength(1));
      expect(a, isNot(GeoPoint(-12.5, -98.26)));
      expect(a, isNot(GeoPoint(-12.51, -98.25)));
    });

    test('0,0 y -0,0 son el mismo punto con el mismo hash', () {
      final a = GeoPoint(0, 0);
      final b = GeoPoint(-0, -0);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('toString no expone las coordenadas', () {
      final point = GeoPoint(-12.345678, -98.765432);
      expect(point.toString(), 'GeoPoint(<oculto>)');
      // También al interpolarlo o dentro de una colección.
      final texts = [
        '$point',
        [point].toString(),
        {'p': point}.toString(),
      ];
      for (final text in texts) {
        expect(text, isNot(contains('12.3')));
        expect(text, isNot(contains('98.7')));
        expect(text, isNot(matches(RegExp(r'\d'))));
      }
    });
  });

  group('GeoPoint.distanceTo', () {
    test('coincide con los valores de referencia (Vincenty esférico)', () {
      for (final reference in _references) {
        final (lat1, lng1, lat2, lng2, meters) = reference;
        final a = GeoPoint(lat1, lng1);
        final b = GeoPoint(lat2, lng2);
        // 1 mm o una parte en mil millones, lo que sea mayor.
        final tolerance = math.max(1e-3, meters * 1e-9);
        expect(
          a.distanceTo(b),
          closeTo(meters, tolerance),
          reason: '($lat1, $lng1) → ($lat2, $lng2)',
        );
      }
    });

    test('coincide con las fórmulas cerradas de la esfera', () {
      // Independientes de cualquier implementación: arcos de círculo máximo.
      final origin = GeoPoint(0, 0);
      expect(
        origin.distanceTo(GeoPoint(0, 90)),
        closeTo(math.pi * _r / 2, 1e-3),
      );
      expect(
        GeoPoint(90, 0).distanceTo(GeoPoint(-90, 0)),
        closeTo(math.pi * _r, 1e-3),
      );
      expect(
        origin.distanceTo(GeoPoint(0, 0.01)),
        closeTo(_r * 0.01 * math.pi / 180, 1e-6),
      );
      // A latitud φ, 1° de longitud mide cos(φ) veces lo que en el ecuador
      // solo sobre el paralelo; el círculo máximo es algo más corto.
      final parallel = _r * math.cos(60 * math.pi / 180) * math.pi / 180;
      final greatCircle = GeoPoint(60, 10).distanceTo(GeoPoint(60, 11));
      expect(greatCircle, lessThan(parallel));
      expect(greatCircle, closeTo(parallel, 5));
    });

    test('es cero para el mismo punto y en el polo con otra longitud', () {
      final point = GeoPoint(-12.5, -98.25);
      expect(point.distanceTo(point), 0);
      expect(point.distanceTo(GeoPoint(-12.5, -98.25)), 0);
      // En el polo, la longitud no cambia la posición.
      expect(GeoPoint(90, 0).distanceTo(GeoPoint(90, 180)), closeTo(0, 1e-6));
      expect(
        GeoPoint(-90, -45).distanceTo(GeoPoint(-90, 135)),
        closeTo(0, 1e-6),
      );
      // 180 y -180 son el mismo meridiano.
      expect(
        GeoPoint(10, 180).distanceTo(GeoPoint(10, -180)),
        closeTo(0, 1e-6),
      );
    });

    test('es simétrica, finita y nunca supera media circunferencia', () {
      final random = math.Random(20261015);
      for (var i = 0; i < 2000; i++) {
        final a = GeoPoint(
          random.nextDouble() * 180 - 90,
          random.nextDouble() * 360 - 180,
        );
        final b = GeoPoint(
          random.nextDouble() * 180 - 90,
          random.nextDouble() * 360 - 180,
        );
        final ab = a.distanceTo(b);
        expect(ab.isFinite, isTrue);
        expect(ab, greaterThanOrEqualTo(0));
        expect(ab, lessThanOrEqualTo(math.pi * _r + 1e-6));
        expect(ab, closeTo(b.distanceTo(a), 1e-6));
      }
    });

    test('las antípodas exactas no producen NaN por redondeo', () {
      // sin² y cos² pueden sumar algo más de 1; el código lo acota.
      for (final (lat, lng) in [(0.0, 0.0), (33.3, 44.4), (-89.9, 179.9)]) {
        final antipode = GeoPoint(-lat, lng > 0 ? lng - 180 : lng + 180);
        final d = GeoPoint(lat, lng).distanceTo(antipode);
        expect(d.isNaN, isFalse);
        expect(d, closeTo(math.pi * _r, 1e-3));
      }
    });

    test('cumple la desigualdad triangular', () {
      final a = GeoPoint(-40, -30);
      final b = GeoPoint(-41.5, -25);
      final c = GeoPoint(-38, -20);
      expect(
        a.distanceTo(c),
        lessThanOrEqualTo(a.distanceTo(b) + b.distanceTo(c)),
      );
    });
  });

  group('GeoPoint.approximate', () {
    test('redondea a dos decimales (0,01° ≈ 1,1 km)', () {
      expect(
        GeoPoint(-12.345678, -98.765432).approximate(),
        GeoPoint(-12.35, -98.77),
      );
      expect(
        GeoPoint(12.344999, 98.764999).approximate(),
        GeoPoint(12.34, 98.76),
      );
    });

    test('los medios se alejan del cero de forma simétrica', () {
      // 0,125 × 100 = 12,5 es exacto en binario: no hay error de redondeo.
      expect(GeoPoint(0.125, 0.375).approximate(), GeoPoint(0.13, 0.38));
      expect(GeoPoint(-0.125, -0.375).approximate(), GeoPoint(-0.13, -0.38));
    });

    test('en los bordes ±90 y ±180 no se sale de rango ni lanza', () {
      // En los polos la longitud no indica posición y se fija a 0.
      final cases = <(double, double, double, double)>[
        (90, 180, 90, 0),
        (-90, -180, -90, 0),
        (89.996, 179.996, 90, 0),
        (-89.996, -179.996, -90, 0),
        (89.994, 179.994, 89.99, 179.99),
        (-89.994, -179.994, -89.99, -179.99),
        (-12.5, -179.996, -12.5, 180),
      ];
      for (final (lat, lng, expectedLat, expectedLng) in cases) {
        late GeoPoint approximated;
        expect(
          () => approximated = GeoPoint(lat, lng).approximate(),
          returnsNormally,
          reason: '($lat, $lng)',
        );
        expect(approximated, GeoPoint(expectedLat, expectedLng));
      }
    });

    test('no deja en los valores rastros que distingan puntos de la misma '
        'posición aproximada', () {
      // Del dispositivo sale el número serializado, no la igualdad de Dart:
      // -0,0 == 0,0 es cierto, pero "-0.0" revela de qué lado del ecuador o
      // de Greenwich está la persona dentro de la celda; -180 frente a 180,
      // de qué lado del antimeridiano; y la longitud en el polo, su rumbo
      // exacto (una franja de centímetros de ancho).
      final pairs = <(GeoPoint, GeoPoint)>[
        (GeoPoint(-0.004, 10.5), GeoPoint(0.004, 10.5)),
        (GeoPoint(-12.5, -0.004), GeoPoint(-12.5, 0.004)),
        (GeoPoint(-12.5, -179.996), GeoPoint(-12.5, 179.996)),
        (GeoPoint(-12.5, -180), GeoPoint(-12.5, 180)),
        (GeoPoint(89.996, 37.123), GeoPoint(89.997, -100.5)),
        (GeoPoint(-89.996, -45.678), GeoPoint(-90, 120)),
      ];
      for (final (i, (a, b)) in pairs.indexed) {
        expect(a.approximate(), b.approximate(), reason: 'par $i');
        expect(
          _wire(a.approximate()),
          _wire(b.approximate()),
          reason: 'par $i',
        );
      }
      expect(_wire(GeoPoint(-0.004, -0.004).approximate()), '[0.0,0.0]');
    });

    test('en puntos aleatorios: válido, idempotente, en la rejilla y a menos '
        'de media celda', () {
      final random = math.Random(42);
      // Media diagonal de una celda de 0,01° en el ecuador ≈ 786 m.
      const maxShift = math.sqrt2 * 0.005 * math.pi / 180 * _r;
      for (var i = 0; i < 5000; i++) {
        final point = GeoPoint(
          random.nextDouble() * 180 - 90,
          random.nextDouble() * 360 - 180,
        );
        final approximated = point.approximate();
        expect(
          GeoPoint.isValid(approximated.latitude, approximated.longitude),
          isTrue,
        );
        expect(approximated.approximate(), approximated);
        expect(
          (approximated.latitude - point.latitude).abs(),
          lessThanOrEqualTo(0.005 + 1e-9),
        );
        // La longitud se compara módulo 360 (180 y -180 son el mismo
        // meridiano) y no cuenta en los polos, donde se fija a 0.
        if (approximated.latitude.abs() != 90) {
          final dLng =
              (approximated.longitude - point.longitude + 540) % 360 - 180;
          expect(dLng.abs(), lessThanOrEqualTo(0.005 + 1e-9));
        }
        for (final value in [approximated.latitude, approximated.longitude]) {
          final hundredths = value * 100;
          expect(hundredths, closeTo(hundredths.roundToDouble(), 1e-6));
        }
        expect(
          point.distanceTo(approximated),
          lessThanOrEqualTo(maxShift + 1e-6),
        );
      }
    });

    test('puntos cercanos de la misma celda dan el mismo resultado', () {
      final a = GeoPoint(-12.341, -98.761).approximate();
      final b = GeoPoint(-12.344, -98.764).approximate();
      expect(a, b);
    });
  });
}
