import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/features/emergency/domain/emergency.dart';

/// Fases de la cuenta atrás que precede a una alerta SOS (`preparing` en la
/// máquina de estados de `docs/architecture/02-modelo-de-datos.md`).
enum SosCountdownPhase {
  /// Aún no empezó (o se reinició tras cancelar).
  idle,

  /// Corriendo: se puede cancelar.
  counting,

  /// La persona la canceló: no se crea ninguna alerta.
  cancelled,

  /// Terminó sin cancelarse: es el momento de crear la alerta.
  completed,
}

/// Cuenta atrás cancelable de [SosRules.cancelWindow] antes de crear una
/// alerta. Dart puro: el tiempo sale del [Clock] inyectado y quien la usa
/// la consulta con [poll] (p. ej. desde un temporizador de la interfaz).
///
/// Garantías:
/// * [poll] devuelve `true` **una sola vez**, al completarse: así se crea
///   una única alerta aunque la interfaz consulte muchas veces.
/// * Cancelar y completar se excluyen: una cuenta atrás cancelada nunca se
///   completa y una completada ya no se puede cancelar.
/// * Un reloj que retrocede no alarga la espera más allá de [window] ni da
///   tiempos negativos.
final class SosCountdown {
  new(this._clock, {this.window = SosRules.cancelWindow})
    : assert(window > Duration.zero, 'La ventana debe ser positiva');

  final Clock _clock;

  /// Tiempo total para cancelar.
  final Duration window;

  SosCountdownPhase _phase = SosCountdownPhase.idle;
  DateTime? _startedAt;

  SosCountdownPhase get phase => _phase;

  /// Empieza a contar. Solo tiene efecto desde `idle` o `cancelled`
  /// (un nuevo intento); en curso o completada no hace nada.
  void start() {
    if (_phase == SosCountdownPhase.counting ||
        _phase == SosCountdownPhase.completed) {
      return;
    }
    _startedAt = _clock.now();
    _phase = SosCountdownPhase.counting;
  }

  /// Cancela la cuenta atrás en curso. Devuelve `true` si se canceló; si ya
  /// se completó (o no estaba en curso) no cambia nada y devuelve `false`.
  ///
  /// Antes de cancelar se comprueba si el tiempo ya se cumplió: un toque
  /// tardío no puede deshacer una alerta que ya debía crearse.
  bool cancel() {
    if (_phase != SosCountdownPhase.counting) return false;
    if (_elapsed() >= window) return false;
    _phase = SosCountdownPhase.cancelled;
    return true;
  }

  /// Vuelve a `idle` desde `cancelled`. Una completada no se reinicia: la
  /// alerta ya se está creando.
  void reset() {
    if (_phase == SosCountdownPhase.cancelled) {
      _phase = SosCountdownPhase.idle;
      _startedAt = null;
    }
  }

  /// Comprueba el reloj. Devuelve `true` exactamente una vez: cuando la
  /// cuenta atrás pasa de `counting` a `completed`.
  bool poll() {
    if (_phase != SosCountdownPhase.counting) return false;
    if (_elapsed() < window) return false;
    _phase = SosCountdownPhase.completed;
    return true;
  }

  /// Tiempo que falta (entre cero y [window]).
  Duration get remaining => switch (_phase) {
    SosCountdownPhase.idle || SosCountdownPhase.cancelled => window,
    SosCountdownPhase.completed => Duration.zero,
    SosCountdownPhase.counting => _clampRemaining(window - _elapsed()),
  };

  /// Segundos enteros que faltan, redondeados hacia arriba ("5, 4, 3…"):
  /// no se muestra 0 mientras aún se puede cancelar.
  int get remainingSeconds {
    final micros = remaining.inMicroseconds;
    return (micros + Duration.microsecondsPerSecond - 1) ~/
        Duration.microsecondsPerSecond;
  }

  /// Fracción que falta, de 1 (recién empezada) a 0 (completada).
  double get fractionRemaining =>
      remaining.inMicroseconds / window.inMicroseconds;

  Duration _elapsed() {
    final started = _startedAt;
    if (started == null) return Duration.zero;
    final elapsed = _clock.now().difference(started);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Duration _clampRemaining(Duration value) {
    if (value.isNegative) return Duration.zero;
    return value > window ? window : value;
  }
}
