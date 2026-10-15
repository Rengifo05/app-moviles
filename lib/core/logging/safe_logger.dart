import 'package:meta/meta.dart';
import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/core/failure.dart';

enum LogLevel { debug, info, warning, error }

/// Entrada de registro ya depurada: solo contiene datos permitidos.
@immutable
final class LogEntry {
  const new({
    required this.level,
    required this.event,
    required this.fields,
    required this.time,
  });

  final LogLevel level;
  final String event;
  final Map<String, Object> fields;
  final DateTime time;

  @override
  String toString() {
    final extras = fields.entries.map((e) => '${e.key}=${e.value}').join(' ');
    return '${time.toIso8601String()} ${level.name.toUpperCase()} $event'
        '${extras.isEmpty ? '' : ' $extras'}';
  }
}

/// Destino de los registros (consola de depuración, servicio de errores…).
abstract interface class LogSink {
  void write(LogEntry entry);
}

/// Esquema de un campo permitido: decide qué valores son seguros.
sealed class _FieldRule {
  const new();

  /// Valor seguro o `null` si debe redactarse.
  Object? accept(Object value);
}

/// Entero no negativo acotado (contadores, intentos, duraciones).
final class _BoundedInt extends _FieldRule {
  const new(this.max);

  final int max;

  @override
  Object? accept(Object value) {
    final number = switch (value) {
      final int v => v,
      final Duration d => d.inMilliseconds,
      // Solo dobles finitos y enteros; nunca lanza con infinito o NaN.
      final double d when d.isFinite && d == d.truncateToDouble() => d.toInt(),
      _ => null,
    };
    return number != null && number >= 0 && number <= max ? number : null;
  }
}

/// Texto de un vocabulario cerrado: solo letras y separadores, sin dígitos,
/// de longitud acotada. Acepta enums por su nombre.
final class _Vocabulary extends _FieldRule {
  const new(this.pattern);

  final String pattern;

  @override
  Object? accept(Object value) {
    final text = switch (value) {
      final Enum e => e.name,
      final String s => s,
      _ => null,
    };
    return text != null && RegExp(pattern).hasMatch(text) ? text : null;
  }
}

/// Uno de un conjunto fijo de valores.
final class _OneOf extends _FieldRule {
  const new(this.values);

  final Set<String> values;

  @override
  Object? accept(Object value) {
    final text = value is Enum ? value.name : value;
    return values.contains(text) ? text : null;
  }
}

/// Identificador de operación: solo UUID v7 (los que genera la app).
final class _UuidV7 extends _FieldRule {
  const new();

  static final RegExp _pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  @override
  Object? accept(Object value) =>
      value is String && _pattern.hasMatch(value) ? value : null;
}

/// Registro estructurado que **por diseño** no puede emitir datos privados.
///
/// Reglas (ver `docs/privacy/modelo-de-amenazas.md`, amenaza 7):
/// * El nombre del evento es un identificador constante `snake_case` con
///   puntos, sin dígitos y de ≤ 64 caracteres; si no lo es, se sustituye por
///   `invalid_event`.
/// * Solo se admiten los campos de [allowedFields], cada uno con su propio
///   esquema cerrado (lista de valores, vocabulario sin dígitos, entero
///   acotado o UUID v7). Lo demás se
///   descarta y se cuenta en `redacted`; un valor que no cumple su esquema se
///   reemplaza por `[redacted]`. Así no hay heurísticas que evadir: un token,
///   una coordenada o un nombre nunca cumplen ningún esquema.
/// * De un [Failure] solo se registran su categoría y su código, nunca la
///   causa original.
/// * El registro nunca lanza excepciones: un fallo al depurar redacta todo.
final class SafeLogger {
  new({required this._sink, this._clock = const SystemClock()});

  final LogSink _sink;
  final Clock _clock;

  /// Campos permitidos. Ampliar este esquema requiere revisión de
  /// privacidad: nunca añadir coordenadas, nombres, correos ni tokens.
  static const Map<String, _FieldRule> _schema = {
    'attempt': _BoundedInt(1000),
    'count': _BoundedInt(100000),
    'durationMs': _BoundedInt(86400000),
    // Códigos de Failure: kebab-case sin dígitos.
    'code': _Vocabulary(r'^[a-z]+(-[a-z]+)*$'),
    'kind': _Vocabulary(r'^[a-z][a-zA-Z]{0,39}$'),
    'status': _Vocabulary(r'^[a-z][a-zA-Z_]{0,39}$'),
    'feature': _OneOf({
      'activity',
      'app',
      'authentication',
      'check_ins',
      'emergency',
      'family',
      'geofences',
      'location_sharing',
      'onboarding',
      'settings',
      'sync',
    }),
    'operation': _Vocabulary(r'^[a-z][a-zA-Z_]{0,39}$'),
    'platform': _OneOf({'android', 'ios', 'linux', 'macos', 'windows', 'web'}),
    'opId': _UuidV7(),
  };

  /// Nombres de los campos permitidos.
  static Set<String> get allowedFields => _schema.keys.toSet();

  static final RegExp _eventPattern = RegExp(r'^[a-z][a-z_]*(\.[a-z_]+)*$');
  static const int _maxEventLength = 64;

  static const String redactedValue = '[redacted]';

  void debug(String event, {Map<String, Object?> fields = const {}}) =>
      _log(LogLevel.debug, event, fields);

  void info(String event, {Map<String, Object?> fields = const {}}) =>
      _log(LogLevel.info, event, fields);

  void warning(
    String event, {
    Map<String, Object?> fields = const {},
    Failure? failure,
  }) => _log(LogLevel.warning, event, _withFailure(fields, failure));

  void error(
    String event, {
    Map<String, Object?> fields = const {},
    Failure? failure,
  }) => _log(LogLevel.error, event, _withFailure(fields, failure));

  Map<String, Object?> _withFailure(
    Map<String, Object?> fields,
    Failure? failure,
  ) => failure == null
      ? fields
      : {...fields, 'kind': failure.kind.name, 'code': failure.code};

  void _log(LogLevel level, String event, Map<String, Object?> fields) {
    try {
      _sink.write(
        LogEntry(
          level: level,
          event: safeEventName(event),
          fields: sanitize(fields),
          time: _clock.now(),
        ),
      );
    } on Object {
      // Registrar nunca debe romper el flujo que lo invoca (p. ej. un
      // manejador de errores). Si el destino falla, se descarta la entrada.
    }
  }

  @visibleForTesting
  static String safeEventName(String event) =>
      event.length <= _maxEventLength && _eventPattern.hasMatch(event)
      ? event
      : 'invalid_event';

  /// Aplica el esquema por campo.
  @visibleForTesting
  static Map<String, Object> sanitize(Map<String, Object?> fields) {
    final result = <String, Object>{};
    var redacted = 0;
    for (final MapEntry(:key, :value) in fields.entries) {
      if (value == null) continue;
      final rule = _schema[key];
      if (rule == null) {
        redacted++;
        continue;
      }
      Object? accepted;
      try {
        accepted = rule.accept(value);
      } on Object {
        accepted = null;
      }
      result[key] = accepted ?? redactedValue;
    }
    if (redacted > 0) result['redacted'] = redacted;
    return result;
  }
}
