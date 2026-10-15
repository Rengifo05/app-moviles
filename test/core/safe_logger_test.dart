import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';

import '../helpers/fakes.dart';

const String redacted = SafeLogger.redactedValue;
const uuidV7 = '0192f1c4-7a2b-7c3d-8e4f-0123456789ab';

void main() {
  late MemoryLogSink sink;
  late SafeLogger logger;

  setUp(() {
    sink = MemoryLogSink();
    logger = SafeLogger(sink: sink, clock: FakeClock());
  });

  Map<String, Object> logged(Map<String, Object?> fields) {
    logger.info('test.event', fields: fields);
    return sink.entries.last.fields;
  }

  group('campos', () {
    test('descarta campos fuera del esquema y los cuenta', () {
      final fields = logged({
        'lat': 4.7110,
        'lng': -74.0721,
        'email': 'ana@example.com',
        'operation': 'check_in',
      });
      expect(fields, {'operation': 'check_in', 'redacted': 3});
    });

    test('conserva identificadores técnicos válidos', () {
      final fields = logged({
        'opId': uuidV7,
        'attempt': 3,
        'kind': FailureKind.devicePermissionDenied,
        'durationMs': const Duration(milliseconds: 250),
        'feature': 'emergency',
        'code': 'permission-denied',
        'status': 'needHelp',
        'platform': 'android',
        'count': 12.0,
      });
      expect(fields, {
        'opId': uuidV7,
        'attempt': 3,
        'kind': 'devicePermissionDenied',
        'durationMs': 250,
        'feature': 'emergency',
        'code': 'permission-denied',
        'status': 'needHelp',
        'platform': 'android',
        'count': 12,
      });
    });

    test('los valores nulos se omiten sin contarse', () {
      expect(logged({'code': null, 'attempt': 1}), {'attempt': 1});
    });
  });

  group('redacta valores que no cumplen su esquema', () {
    // Evasiones demostradas en la revisión adversarial del incremento 1.
    final cases = <String, Map<String, Object?>>{
      'token hex de 128 bits': {'code': '9f86d081884c7d659a2feaa0c55ad015'},
      'token base64url de 128 bits': {'code': 'n4bQgYhMfWWaL-qgxVrQFa'},
      'UUID v4 (no lo genera la app)': {
        'opId': '3b241101-e2bb-4255-8caf-4136c566a962',
      },
      'UUID en un campo que no es opId': {'code': uuidV7},
      'OTP de 6 dígitos': {'code': '482913'},
      'uid de Firebase': {'opId': 'kZ3q9XyR2bT7mN4pL8sV1wQ6uE0a'},
      'coordenada decimal': {'count': 4.7110},
      'coordenada como texto': {'status': '4.71100,-74.07210'},
      'coordenada en microgrados (entero)': {'count': 4711000000},
      'coordenada negativa en microgrados': {'attempt': -74072100},
      'teléfono como entero': {'count': 3001234567},
      'teléfono como texto': {'code': '+573001234567'},
      'correo': {'code': 'ana@example.com'},
      'JWT': {'code': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload'},
      'texto libre': {'status': 'Ana está en casa'},
      'nombre de lugar': {'feature': 'casa_de_maria'},
      'infinito': {'durationMs': double.infinity},
      'menos infinito': {'count': double.negativeInfinity},
      'NaN': {'attempt': double.nan},
      'lista': {
        'status': ['a'],
      },
      'mapa': {
        'status': {'lat': 4.7},
      },
      'objeto arbitrario': {'status': Object()},
    };

    for (final MapEntry(key: name, value: fields) in cases.entries) {
      test(name, () {
        final result = logged(fields);
        expect(result.values.whereType<String>(), everyElement(redacted));
        expect(sink.entries.last.toString(), isNot(contains('4.71')));
      });
    }
  });

  group('eventos', () {
    test('acepta nombres constantes con puntos y guiones bajos', () {
      expect(
        SafeLogger.safeEventName('outbox.retry_scheduled'),
        'outbox.retry_scheduled',
      );
    });

    for (final event in [
      'Ubicación de Ana: 4.711,-74.07',
      'invite.sent.3001234567',
      'loc.n4711000.w74072100',
      'auth.refresh.9f86d081884c7d659a2feaa0c55ad015',
      'a${'b' * 64}',
      '',
    ]) {
      test('rechaza "$event"', () {
        logger.info(event);
        expect(sink.entries.last.event, 'invalid_event');
      });
    }
  });

  group('fallos', () {
    test('de un Failure registra solo categoría y código, nunca la causa', () {
      logger.error(
        'sync.failed',
        failure: Failure.network('timeout', Exception('lat=4.7110 token=abc')),
      );
      final entry = sink.entries.single;
      expect(entry.fields, {'kind': 'network', 'code': 'timeout'});
      expect(entry.toString(), isNot(contains('4.7110')));
      expect(entry.toString(), isNot(contains('token')));
    });

    test('nunca lanza, aunque el destino falle', () {
      final failing = SafeLogger(sink: _ThrowingSink(), clock: FakeClock());
      expect(
        () => failing.error('x.y', fields: {'durationMs': double.infinity}),
        returnsNormally,
      );
    });

    test('registra nivel y hora del reloj inyectado', () {
      logger.warning('location.stale');
      final entry = sink.entries.single;
      expect(entry.level, LogLevel.warning);
      expect(entry.time, DateTime.utc(2026, 1, 1, 12));
    });
  });
}

final class _ThrowingSink implements LogSink {
  @override
  void write(LogEntry entry) => throw StateError('destino caído');
}
