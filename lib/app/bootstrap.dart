import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/app/app.dart';
import 'package:nexo_familia/app/composition.dart';
import 'package:nexo_familia/app/session_providers.dart';
import 'package:nexo_familia/core/config/app_config.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';
import 'package:path_provider/path_provider.dart';

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

  // Application Support: excluido de copias en la nube (ver AppDelegate y
  // data_extraction_rules.xml).
  final db = AppDatabase(
    driftDatabase(
      name: 'nexo_familia',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    ),
  );

  final composition = switch (config.backend) {
    BackendMode.demo => AppComposition.demo(db: db),
    BackendMode.firebase => throw UnsupportedError(
      'El backend Firebase se conecta en el incremento 4.',
    ),
  };
  WidgetsBinding.instance.addObserver(composition.coordinator);

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        activeFamilyIdOverride,
        ...composition.overrides,
      ],
      child: const NexoApp(),
    ),
  );
}
