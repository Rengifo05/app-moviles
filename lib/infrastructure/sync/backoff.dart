import 'dart:math' as math;

/// Espera exponencial con *jitter* para reintentos (ADR-004).
final class BackoffPolicy {
  const new({
    this.base = const Duration(seconds: 2),
    this.max = const Duration(minutes: 5),
    this.jitter = 0.2,
  }) : assert(jitter >= 0 && jitter <= 1, 'jitter debe estar en [0, 1]');

  /// Política del SOS: reintentos rápidos, tope de 30 s.
  static const sos = BackoffPolicy(max: Duration(seconds: 30));

  /// A partir de aquí el exponente deja de crecer: con cualquier base
  /// representable el resultado ya es infinito o supera el tope, y se evita
  /// calcular potencias enormes.
  static const int _maxExponent = 62;

  final Duration base;

  /// Tope absoluto: el retraso nunca lo supera, tampoco con *jitter*.
  final Duration max;

  /// Fracción aleatoria (±) aplicada al retraso para evitar ráfagas.
  final double jitter;

  /// Retraso antes del intento número [attempt] (1 = primer reintento; 0 o
  /// negativo cuentan como el primero).
  /// [random] en [0, 1) se inyecta para que las pruebas sean deterministas;
  /// fuera de ese rango se acota.
  Duration delayFor(int attempt, {double random = 0.5}) {
    // `attempt - 1` desborda con el entero más negativo: se compara antes.
    final exponent = attempt <= 1 ? 0 : math.min(attempt - 1, _maxExponent);
    final maxMs = math.max(0, max.inMilliseconds).toDouble();
    // En `double` para que el producto no desborde el entero de 64 bits.
    final raw = base.inMilliseconds * math.pow(2.0, exponent);
    final capped = math.min(raw, maxMs);
    final unit = random.isNaN ? 0.5 : random.clamp(0.0, 1.0);
    final jittered = capped * (1 + jitter * (2 * unit - 1));
    return Duration(milliseconds: jittered.clamp(0.0, maxMs).round());
  }
}
