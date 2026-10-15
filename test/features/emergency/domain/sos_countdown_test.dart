import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/features/emergency/domain/emergency.dart';
import 'package:nexo_familia/features/emergency/domain/sos_countdown.dart';

import '../../../helpers/fakes.dart';

void main() {
  late FakeClock clock;
  late SosCountdown countdown;

  setUp(() {
    clock = FakeClock();
    countdown = SosCountdown(clock);
  });

  test('usa la ventana de SosRules y empieza sin contar', () {
    expect(countdown.window, SosRules.cancelWindow);
    expect(countdown.phase, SosCountdownPhase.idle);
    expect(countdown.remaining, SosRules.cancelWindow);
    expect(countdown.remainingSeconds, 5);
    expect(countdown.poll(), isFalse);
  });

  test('cuenta 5, 4, 3, 2, 1 y se completa una sola vez', () {
    countdown.start();
    final seen = <int>[];
    for (var i = 0; i < 5; i++) {
      seen.add(countdown.remainingSeconds);
      expect(countdown.poll(), isFalse);
      clock.advance(const Duration(seconds: 1));
    }
    expect(seen, [5, 4, 3, 2, 1]);
    expect(countdown.poll(), isTrue);
    expect(countdown.phase, SosCountdownPhase.completed);
    expect(countdown.remaining, Duration.zero);
    // Consultas posteriores no vuelven a disparar la alerta.
    expect(countdown.poll(), isFalse);
    clock.advance(const Duration(minutes: 1));
    expect(countdown.poll(), isFalse);
  });

  test('redondea hacia arriba: nunca muestra 0 mientras se puede cancelar', () {
    countdown.start();
    clock.advance(const Duration(milliseconds: 4999));
    expect(countdown.remainingSeconds, 1);
    expect(countdown.fractionRemaining, closeTo(0.0002, 1e-6));
    expect(countdown.poll(), isFalse);
  });

  test('cancelar a tiempo impide completar', () {
    countdown.start();
    clock.advance(const Duration(seconds: 3));
    expect(countdown.cancel(), isTrue);
    expect(countdown.phase, SosCountdownPhase.cancelled);
    clock.advance(const Duration(seconds: 10));
    expect(countdown.poll(), isFalse);
    expect(countdown.phase, SosCountdownPhase.cancelled);
  });

  test('un toque tardío no cancela una cuenta atrás ya cumplida', () {
    countdown.start();
    clock.advance(const Duration(seconds: 5));
    expect(countdown.cancel(), isFalse);
    expect(countdown.poll(), isTrue);
    expect(countdown.cancel(), isFalse);
    expect(countdown.phase, SosCountdownPhase.completed);
  });

  test('cancelar sin haber empezado no hace nada', () {
    expect(countdown.cancel(), isFalse);
    expect(countdown.phase, SosCountdownPhase.idle);
  });

  test('tras cancelar se puede reiniciar y volver a empezar', () {
    countdown
      ..start()
      ..cancel()
      ..reset();
    expect(countdown.phase, SosCountdownPhase.idle);
    expect(countdown.remaining, SosRules.cancelWindow);

    clock.advance(const Duration(minutes: 1));
    countdown.start();
    expect(countdown.remainingSeconds, 5);
    clock.advance(const Duration(seconds: 5));
    expect(countdown.poll(), isTrue);
  });

  test('start en curso no reinicia el tiempo; completada no reinicia', () {
    countdown.start();
    clock.advance(const Duration(seconds: 3));
    countdown.start();
    expect(countdown.remainingSeconds, 2);
    clock.advance(const Duration(seconds: 2));
    expect(countdown.poll(), isTrue);
    countdown
      ..start()
      ..reset();
    expect(countdown.phase, SosCountdownPhase.completed);
  });

  test('un reloj que retrocede no alarga la espera más allá de la ventana', () {
    countdown.start();
    clock.advance(const Duration(seconds: -30));
    expect(countdown.remaining, SosRules.cancelWindow);
    expect(countdown.fractionRemaining, 1);
    expect(countdown.poll(), isFalse);
  });

  test('admite otra ventana', () {
    final short = SosCountdown(clock, window: const Duration(seconds: 2))
      ..start();
    expect(short.remainingSeconds, 2);
    clock.advance(const Duration(seconds: 2));
    expect(short.poll(), isTrue);
  });
}
