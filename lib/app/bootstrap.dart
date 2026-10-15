import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/app/app.dart';
import 'package:nexo_familia/core/config/app_config.dart';
import 'package:nexo_familia/core/di/core_providers.dart';

/// Raíz de composición: valida la configuración, prepara las dependencias y
/// arranca la interfaz. Es el único lugar que conoce las implementaciones
/// concretas de los repositorios.
Future<void> bootstrap(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();

  final errors = config.validate();
  if (errors.isNotEmpty) {
    // Fallar pronto es preferible a arrancar con una configuración insegura.
    throw StateError('Configuración inválida: ${errors.join(' ')}');
  }

  runApp(
    ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(config)],
      child: const NexoApp(),
    ),
  );
}
