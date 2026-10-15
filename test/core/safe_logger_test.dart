import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';

import '../helpers/fakes.dart';

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

  group('SafeLogger', () {
    test('descarta campos fuera de la lista blanca y los cuenta', () {
      final fields = logged({
        'lat': 4.7110,
        'lng': -74.0721,
        'email': 'ana@example.com',
        'operation': 'check_in',
      });
      expect(fields, {'operation': 'check_in', 'redacted': 3});
    });

    test('redacta decimales que podrían ser coordenadas', () {
      expect(logged({'count': 4.7110})['count'], SafeLogger.redactedValue);
      expect(logged({'count': 3.0})['count'], 3);
    });

    test('redacta texto con forma de coordenada en campos permitidos', () {
      expect(
        logged({'status': '4.71100,-74.07210'})['status'],
        SafeLogger.redactedValue,
      );
      expect(logged({'code': '-74.0721'})['code'], SafeLogger.redactedValue);
    });

    test('redacta correos, teléfonos y tokens en campos permitidos', () {
      expect(logged({'code': 'ana@example.com'})['code'], '[redacted]');
      expect(logged({'code': '+573001234567'})['code'], '[redacted]');
      expect(
        logged({
          'code': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload',
        })['code'],
        '[redacted]',
      );
    });

    test('redacta texto libre con espacios', () {
      expect(logged({'status': 'Ana está en casa'})['status'], '[redacted]');
    });

    test('conserva identificadores técnicos, UUID, enteros y enums', () {
      final fields = logged({
        'opId': '0192f1c4-7a2b-7c3d-8e4f-0123456789ab',
        'attempt': 3,
        'kind': FailureKind.network,
        'durationMs': const Duration(milliseconds: 250),
        'feature': 'emergency',
      });
      expect(fields, {
        'opId': '0192f1c4-7a2b-7c3d-8e4f-0123456789ab',
        'attempt': 3,
        'kind': 'network',
        'durationMs': 250,
        'feature': 'emergency',
      });
    });

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

    test('rechaza nombres de evento no constantes', () {
      logger.info('Ubicación de Ana: 4.711,-74.07');
      expect(sink.entries.single.event, 'invalid_event');
    });

    test('registra nivel y hora del reloj inyectado', () {
      logger.warning('location.stale');
      final entry = sink.entries.single;
      expect(entry.level, LogLevel.warning);
      expect(entry.time, DateTime.utc(2026, 1, 1, 12));
    });
  });
}
