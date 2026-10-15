import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/document_cache.dart';

/// Objeto cuyo `toString` contiene un dato que no debe filtrarse.
final class _Secret {
  @override
  String toString() => 'dato-privado';
}

Json _roundTrip(Json data) => DocumentCodec.decode(DocumentCodec.encode(data));

void main() {
  group('fechas', () {
    test('vuelven en UTC con precisión de milisegundos', () {
      final at = DateTime.utc(2026, 3, 4, 5, 6, 7, 890);
      final decoded = _roundTrip({'at': at});
      expect(decoded['at'], at);
      expect((decoded['at']! as DateTime).isUtc, isTrue);
    });

    test('una fecha local se guarda como el mismo instante en UTC', () {
      final local = DateTime(2026, 7, 1, 8, 30);
      final decoded = _roundTrip({'at': local})['at']! as DateTime;
      expect(decoded.isUtc, isTrue);
      expect(decoded.isAtSameMomentAs(local), isTrue);
    });

    test('los microsegundos se descartan', () {
      final at = DateTime.utc(2026, 1, 1, 0, 0, 0, 123, 999);
      expect(
        _roundTrip({'at': at})['at'],
        DateTime.utc(2026, 1, 1, 0, 0, 0, 123),
      );
    });

    test('fechas anteriores a 1970 y la época Unix', () {
      final data = {
        'antes': DateTime.utc(1969, 12, 31, 23, 59, 59, 1),
        'epoca': DateTime.utc(1970),
      };
      expect(_roundTrip(data), data);
    });

    test('anidadas en mapas y listas', () {
      final a = DateTime.utc(2026, 1, 1, 12);
      final b = DateTime.utc(2026, 1, 2, 12, 0, 0, 5);
      final data = {
        'evento': {
          'createdAt': a,
          'historial': [
            a,
            {'at': b, 'tipo': 'checkIn'},
            [b, null],
          ],
        },
        'lista': <Object?>[],
        'mapa': <String, Object?>{},
      };
      expect(_roundTrip(data), data);
    });

    test(r'usa el formato documentado {"$date": milisegundos}', () {
      final json = DocumentCodec.encode({
        'at': DateTime.utc(1970, 1, 1, 0, 0, 1),
      });
      expect(json, r'{"at":{"$date":1000}}');
      expect(DocumentCodec.decode(r'{"at":{"$date":1000}}'), {
        'at': DateTime.utc(1970, 1, 1, 0, 0, 1),
      });
    });
  });

  group('mapas que se parecen a una fecha', () {
    test(r'un mapa {"$date": x} con más claves no se confunde', () {
      final data = {
        'campo': {r'$date': 1000, 'otra': 'clave'},
      };
      expect(_roundTrip(data), data);
      expect(
        DocumentCodec.decode(r'{"campo":{"$date":1000,"otra":"clave"}}'),
        data,
      );
    });

    test(r'un mapa con solo la clave $date tampoco se confunde', () {
      final data = {
        'numero': {r'$date': 1000},
        'texto': {r'$date': 'ayer'},
        'enLista': [
          {r'$date': 0},
        ],
      };
      final decoded = _roundTrip(data);
      expect(decoded, data);
      expect(decoded['numero'], isA<Map<String, Object?>>());
    });

    test(r'la clave de escape $map también se conserva', () {
      final data = {
        'escape': {
          r'$map': {r'$date': 5},
        },
        'doble': {
          r'$map': {
            r'$map': {'x': 1},
          },
        },
      };
      expect(_roundTrip(data), data);
    });

    test(r'el documento raíz con solo $date sigue siendo un mapa', () {
      final data = {r'$date': 1000};
      expect(_roundTrip(data), data);
    });

    test(r'un $date no entero en el JSON guardado no es una fecha', () {
      expect(DocumentCodec.decode(r'{"a":{"$date":1.5}}'), {
        'a': {r'$date': 1.5},
      });
    });
  });

  group('tipos JSON', () {
    test('se conservan los tipos básicos', () {
      final data = {
        'int': 42,
        'negativo': -7,
        'double': 3.25,
        'bool': true,
        'nulo': null,
        'texto': 'Hola, ñandú 🌎 "comillas"',
        'vacio': '',
      };
      expect(_roundTrip(data), data);
    });

    test('acepta mapas sin tipar con claves de texto', () {
      final data = <String, Object?>{
        'dinamico': <dynamic, dynamic>{
          'a': 1,
          'b': <dynamic>[2],
        },
      };
      expect(_roundTrip(data), {
        'dinamico': {
          'a': 1,
          'b': [2],
        },
      });
    });

    test('los tipos no serializables lanzan UnsupportedError', () {
      final unsupported = <Object>[
        Object(),
        serverTimestamp,
        const Duration(seconds: 1),
        {1, 2},
        double.nan,
        double.infinity,
        <int, String>{1: 'uno'},
      ];
      for (final value in unsupported) {
        expect(
          () => DocumentCodec.encode({'valor': value}),
          throwsUnsupportedError,
          reason: '$value',
        );
        expect(
          () => DocumentCodec.encode({
            'anidado': [
              {'valor': value},
            ],
          }),
          throwsUnsupportedError,
          reason: 'anidado: $value',
        );
      }
    });

    test('el error nombra el tipo pero no el valor', () {
      expect(
        () => DocumentCodec.encode({'valor': _Secret()}),
        throwsA(
          isA<UnsupportedError>()
              .having((e) => e.message, 'message', contains('_Secret'))
              .having(
                (e) => e.message,
                'message',
                isNot(contains('dato-privado')),
              ),
        ),
      );
    });
  });
}
