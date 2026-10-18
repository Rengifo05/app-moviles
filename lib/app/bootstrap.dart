import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/app/app.dart';
import 'package:nexo_familia/app/composition.dart';
import 'package:nexo_familia/app/firebase_setup.dart';
import 'package:nexo_familia/app/session_providers.dart';
import 'package:nexo_familia/core/config/app_config.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/features/service_status/presentation/service_status_providers.dart';
import 'package:nexo_familia/features/settings/presentation/settings_providers.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
    BackendMode.firebase => AppComposition.firebase(
      db: db,
      firebase: await initializeFirebase(
        FirebaseConfig.fromEnvironment(),
        useEmulators: config.useFirebaseEmulators,
      ),
    ),
  };
  WidgetsBinding.instance.addObserver(composition.coordinator);
  final build = await _buildInfo();

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        activeFamilyIdOverride,
        appVersionProvider.overrideWithValue(build?.label),
        appBuildNumberProvider.overrideWithValue(build?.number),
        ...composition.overrides,
      ],
      child: const NexoApp(),
    ),
  );
}

/// Versión y número de compilación del paquete instalado, o `null` si la
/// plataforma no los da (nunca impide arrancar).
Future<({String label, int? number})?> _buildInfo() async {
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isEmpty) return null;
    return (
      label: info.buildNumber.isEmpty
          ? info.version
          : '${info.version} (${info.buildNumber})',
      number: int.tryParse(info.buildNumber),
    );
  } on Object {
    return null;
  }
}
