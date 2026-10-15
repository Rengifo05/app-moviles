import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/core/config/app_config.dart';
import 'package:nexo_familia/core/id_generator.dart';
import 'package:nexo_familia/core/logging/console_log_sink.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:riverpod/riverpod.dart';

/// Configuración activa. Se sobrescribe siempre en el arranque
/// (`app/bootstrap.dart`) y en las pruebas.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider se define en bootstrap'),
);

final clockProvider = Provider<Clock>((ref) => const SystemClock());

final idGeneratorProvider = Provider<IdGenerator>(
  (ref) => const UuidV7IdGenerator(),
);

final loggerProvider = Provider<SafeLogger>(
  (ref) =>
      SafeLogger(sink: const ConsoleLogSink(), clock: ref.watch(clockProvider)),
);
