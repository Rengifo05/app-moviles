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

/// Registro estructurado que **por diseño** no puede emitir datos privados.
///
/// Reglas (ver `docs/privacy/modelo-de-amenazas.md`, amenaza 7):
/// * El nombre del evento debe ser un identificador `snake.case` constante;
///   si no lo es, se sustituye por `invalid_event`.
/// * Solo se admiten campos de una lista blanca ([allowedFields]); el resto se
///   descarta y se cuenta en `redacted`.
/// * Los valores permitidos deben ser números, booleanos o identificadores
///   cortos. Cualquier texto con forma de coordenada, correo, teléfono o token
///   se reemplaza por `[redacted]`.
/// * De un [Failure] solo se registran su categoría y su código, nunca la
///   causa original.
final class SafeLogger {
  new({required this._sink, this._clock = const SystemClock()});

  final LogSink _sink;
  final Clock _clock;

  /// Campos técnicos seguros. Ampliar esta lista requiere revisión de
  /// privacidad: nunca añadir coordenadas, nombres, correos ni tokens.
  static const Set<String> allowedFields = {
    'attempt',
    'code',
    'count',
    'durationMs',
    'feature',
    'kind',
    'operation',
    'opId',
    'platform',
    'status',
  };

  static final RegExp _eventPattern = RegExp(
    r'^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*$',
  );

  // Identificador corto y seguro: letras, dígitos, guiones y puntos.
  static final RegExp _safeIdentifier = RegExp(r'^[A-Za-z0-9._:-]{1,64}$');
  static final RegExp _coordinateLike = RegExp(r'-?\d{1,3}\.\d{3,}');
  static final RegExp _emailLike = RegExp(r'[^\s@]+@[^\s@]+');
  static final RegExp _phoneLike = RegExp(r'\+?\d[\d\s-]{6,}\d');
  // Tokens/JWT/claves: cadenas largas sin espacios.
  static final RegExp _tokenLike = RegExp(r'[A-Za-z0-9_\-+/=.]{33,}');
  // Los UUID (IDs de operación generados en el cliente) sí son seguros.
  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

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
    _sink.write(
      LogEntry(
        level: level,
        event: _eventPattern.hasMatch(event) ? event : 'invalid_event',
        fields: sanitize(fields),
        time: _clock.now(),
      ),
    );
  }

  /// Aplica la lista blanca y la depuración de valores.
  @visibleForTesting
  static Map<String, Object> sanitize(Map<String, Object?> fields) {
    final result = <String, Object>{};
    var redacted = 0;
    for (final MapEntry(:key, :value) in fields.entries) {
      if (!allowedFields.contains(key) || value == null) {
        if (value != null) redacted++;
        continue;
      }
      result[key] = _sanitizeValue(value);
    }
    if (redacted > 0) result['redacted'] = redacted;
    return result;
  }

  static Object _sanitizeValue(Object value) {
    if (value is int || value is bool) return value;
    // Un decimal puede ser una coordenada: se permite solo si es entero.
    if (value is double) {
      return value == value.truncateToDouble() ? value.toInt() : redactedValue;
    }
    if (value is Enum) return value.name;
    if (value is Duration) return value.inMilliseconds;
    final text = value is String ? value : null;
    if (text == null || !_safeIdentifier.hasMatch(text)) return redactedValue;
    if (_uuid.hasMatch(text)) return text;
    if (_coordinateLike.hasMatch(text) ||
        _emailLike.hasMatch(text) ||
        _phoneLike.hasMatch(text) ||
        _tokenLike.hasMatch(text)) {
      return redactedValue;
    }
    return text;
  }
}
