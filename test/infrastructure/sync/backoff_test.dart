import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/infrastructure/sync/backoff.dart';

/// Entero más negativo del VM: `attempt - 1` desbordaría.
const int _minInt = -0x7FFFFFFFFFFFFFFF - 1;
const int _maxInt = 0x7FFFFFFFFFFFFFFF;

/// Construcción no constante para que el `assert` se evalúe en ejecución.
BackoffPolicy _policyWithJitter(double jitter) => BackoffPolicy(jitter: jitter);

void main() {
  const policy = BackoffPolicy();
  const sos = BackoffPolicy.sos;

  int seconds(Duration d) => d.inSeconds;

  group('BackoffPolicy por defecto', () {
    test('duplica la espera: 2, 4, 8, 16 s…', () {
      expect(
        [
          for (var attempt = 1; attempt <= 8; attempt++)
            policy.delayFor(attempt),
        ],
        [
          for (final s in [2, 4, 8, 16, 32, 64, 128, 256]) Duration(seconds: s),
        ],
      );
    });

    test('se detiene en el tope de 5 min', () {
      expect(policy.delayFor(9), const Duration(minutes: 5));
      expect(policy.delayFor(10), const Duration(minutes: 5));
      expect(policy.delayFor(50), const Duration(minutes: 5));
    });

    test('el intento 0 o negativo cuenta como el primero', () {
      for (final attempt in [0, -1, -1000, _minInt]) {
        expect(
          policy.delayFor(attempt),
          const Duration(seconds: 2),
          reason: 'attempt $attempt',
        );
      }
    });

    test('exponentes enormes no desbordan: siempre el tope', () {
      for (final attempt in [21, 62, 63, 64, 1000, 1 << 40, _maxInt]) {
        expect(
          policy.delayFor(attempt),
          const Duration(minutes: 5),
          reason: 'attempt $attempt',
        );
      }
    });
  });

  group('jitter', () {
    test('random 0 resta el 20 % y random 0.999 suma casi el 20 %', () {
      expect(policy.delayFor(1, random: 0), const Duration(milliseconds: 1600));
      expect(
        policy.delayFor(1, random: 0.999),
        const Duration(milliseconds: 2399),
      );
      expect(policy.delayFor(3, random: 0), const Duration(milliseconds: 6400));
      expect(
        policy.delayFor(3, random: 0.999),
        const Duration(milliseconds: 9597),
      );
    });

    test('en el tope solo puede acortar la espera, nunca superarla', () {
      expect(policy.delayFor(20, random: 0.999), const Duration(minutes: 5));
      expect(policy.delayFor(20, random: 0), const Duration(minutes: 4));
      expect(sos.delayFor(20, random: 0.999), const Duration(seconds: 30));
      expect(sos.delayFor(20, random: 0), const Duration(seconds: 24));
    });

    test('un random fuera de [0, 1) se acota y NaN cuenta como 0.5', () {
      expect(policy.delayFor(1, random: -5), policy.delayFor(1, random: 0));
      expect(policy.delayFor(1, random: 7), policy.delayFor(1, random: 1));
      expect(
        policy.delayFor(1, random: double.nan),
        const Duration(seconds: 2),
      );
      expect(
        policy.delayFor(1, random: double.infinity),
        policy.delayFor(1, random: 1),
      );
    });

    test('sin jitter el retraso es exacto', () {
      const exact = BackoffPolicy(jitter: 0);
      expect(exact.delayFor(1, random: 0), const Duration(seconds: 2));
      expect(exact.delayFor(1, random: 0.999), const Duration(seconds: 2));
    });

    test('un jitter fuera de [0, 1] es un error de programación', () {
      expect(() => _policyWithJitter(1.5), throwsA(isA<AssertionError>()));
      expect(() => _policyWithJitter(-0.1), throwsA(isA<AssertionError>()));
    });
  });

  group('política del SOS', () {
    test('mismo arranque de 2 s y tope de 30 s', () {
      expect(
        [for (var attempt = 1; attempt <= 6; attempt++) sos.delayFor(attempt)]
            .map(seconds),
        [2, 4, 8, 16, 30, 30],
      );
    });

    test('exponentes enormes no desbordan', () {
      expect(sos.delayFor(_maxInt), const Duration(seconds: 30));
      expect(sos.delayFor(_minInt), const Duration(seconds: 2));
    });
  });

  test('nunca es negativo ni supera el tope y no decrece', () {
    for (final p in [policy, sos]) {
      for (final random in [0.0, 0.25, 0.5, 0.75, 0.999]) {
        var previous = Duration.zero;
        for (var attempt = -2; attempt <= 80; attempt++) {
          final delay = p.delayFor(attempt, random: random);
          expect(delay.isNegative, isFalse);
          expect(delay <= p.max, isTrue, reason: 'attempt $attempt');
          expect(delay >= previous, isTrue, reason: 'attempt $attempt');
          previous = delay;
        }
      }
    }
  });

  test('bases y topes enormes no desbordan el entero de 64 bits', () {
    const huge = BackoffPolicy(
      base: Duration(days: 365 * 100),
      max: Duration(days: 365 * 1000),
    );
    expect(huge.delayFor(40), const Duration(days: 365 * 1000));
    expect(huge.delayFor(_maxInt, random: 0.999), huge.max);
    expect(huge.delayFor(1), const Duration(days: 365 * 100));
  });

  test('una base cero o mayor que el tope se comporta de forma segura', () {
    const zero = BackoffPolicy(base: Duration.zero);
    expect(zero.delayFor(1), Duration.zero);
    expect(zero.delayFor(_maxInt), Duration.zero);
    const inverted = BackoffPolicy(
      base: Duration(minutes: 10),
      max: Duration(minutes: 1),
    );
    expect(inverted.delayFor(1, random: 0.999), const Duration(minutes: 1));
  });
}
