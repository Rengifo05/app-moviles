import 'dart:developer' as developer;

import 'package:nexo_familia/core/logging/safe_logger.dart';

/// Envía los registros a la consola de depuración. En compilaciones de
/// producción no escribe nada: el registro remoto de errores se añadirá con
/// su propio [LogSink] cuando se apruebe un proveedor.
final class ConsoleLogSink implements LogSink {
  const new();

  static const bool _isProduct = bool.fromEnvironment('dart.vm.product');

  @override
  void write(LogEntry entry) {
    if (_isProduct) return;
    developer.log(
      entry.toString(),
      name: 'nexo',
      level: switch (entry.level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warning => 900,
        LogLevel.error => 1000,
      },
    );
  }
}
