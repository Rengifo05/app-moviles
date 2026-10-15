import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/core/id_generator.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';

/// Reloj controlable para pruebas deterministas.
final class FakeClock implements Clock {
  new([DateTime? start]) : _now = start ?? DateTime.utc(2026, 1, 1, 12);

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration duration) => _now = _now.add(duration);

  // Sin getter a propósito: `now()` es la única lectura del reloj.
  // ignore: avoid_setters_without_getters
  set current(DateTime value) => _now = value.toUtc();
}

/// Genera `id-1`, `id-2`… para aserciones legibles.
final class SequentialIdGenerator implements IdGenerator {
  int _next = 1;

  @override
  String newId() => 'id-${_next++}';
}

/// Captura las entradas de registro para inspeccionarlas.
final class MemoryLogSink implements LogSink {
  final List<LogEntry> entries = [];

  @override
  void write(LogEntry entry) => entries.add(entry);
}
