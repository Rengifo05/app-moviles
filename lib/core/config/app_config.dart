import 'package:meta/meta.dart';

/// Entorno de despliegue.
enum AppEnvironment { dev, staging, prod }

/// Backend con el que arranca la app.
enum BackendMode {
  /// Datos en memoria, sin red ni credenciales. Para desarrollo, pruebas de
  /// extremo a extremo en el host y demostraciones de la interfaz.
  demo,

  /// Firebase real o sus emuladores (según
  /// [AppConfig.useFirebaseEmulators]).
  firebase,
}

/// Configuración de la app. Se lee de `--dart-define-from-file` en el
/// arranque; ningún valor aquí es secreto.
@immutable
final class AppConfig {
  const new({
    required this.appName,
    required this.environment,
    required this.backend,
    required this.useFirebaseEmulators,
    required this.emergencyNumber,
    this.staleLocationAfter = const Duration(minutes: 30),
    this.isReleaseBuild = false,
    this.allowDemoInRelease = false,
  });

  /// Lee los valores definidos en compilación. Ver `config/env.example.json`.
  factory fromEnvironment() => AppConfig(
    appName: const String.fromEnvironment(
      'NX_APP_NAME',
      defaultValue: 'Nexo Familia',
    ),
    environment: _parseEnum(
      AppEnvironment.values,
      'NX_ENV',
      const String.fromEnvironment('NX_ENV', defaultValue: 'dev'),
    ),
    backend: _parseEnum(
      BackendMode.values,
      'NX_BACKEND',
      const String.fromEnvironment('NX_BACKEND', defaultValue: 'demo'),
    ),
    useFirebaseEmulators: const bool.fromEnvironment('NX_USE_EMULATORS'),
    // Dependen de la compilación aunque el analizador los vea constantes.
    // ignore: avoid_redundant_argument_values
    isReleaseBuild: const bool.fromEnvironment('dart.vm.product'),
    // Igual que el anterior: depende de --dart-define.
    // ignore: avoid_redundant_argument_values
    allowDemoInRelease: const bool.fromEnvironment('NX_ALLOW_DEMO_RELEASE'),
    emergencyNumber: const String.fromEnvironment(
      'NX_EMERGENCY_NUMBER',
      defaultValue: '123',
    ),
  );

  /// Nombre visible de la app (provisional y configurable).
  final String appName;
  final AppEnvironment environment;
  final BackendMode backend;
  final bool useFirebaseEmulators;

  /// Número oficial de emergencias que ofrece el flujo SOS (123 en Colombia).
  final String emergencyNumber;

  /// A partir de esta antigüedad una ubicación se muestra como
  /// "Sin actualización reciente".
  final Duration staleLocationAfter;

  /// Compilación *release* (`flutter build --release`).
  final bool isReleaseBuild;

  /// Permite el backend de demostración en *release* (solo para demos
  /// internas; requiere `NX_ALLOW_DEMO_RELEASE=true` explícito).
  final bool allowDemoInRelease;

  /// Errores de configuración que impiden arrancar. Vacío si es válida.
  List<String> validate() => [
    if (appName.trim().isEmpty) 'NX_APP_NAME no puede estar vacío.',
    if (!RegExp(r'^\d{2,6}$').hasMatch(emergencyNumber))
      'NX_EMERGENCY_NUMBER debe ser un número corto (2–6 dígitos).',
    if (environment == AppEnvironment.prod && backend == BackendMode.demo)
      'Producción no puede usar el backend de demostración.',
    if (environment == AppEnvironment.prod && useFirebaseEmulators)
      'Producción no puede usar los emuladores de Firebase.',
    // Una compilación release sin --dart-define no debe arrancar en silencio
    // con datos de demostración.
    if (isReleaseBuild && backend == BackendMode.demo && !allowDemoInRelease)
      'Release con backend demo requiere NX_ALLOW_DEMO_RELEASE=true.',
    if (isReleaseBuild && useFirebaseEmulators)
      'Una compilación release no puede usar los emuladores de Firebase.',
    if (backend == BackendMode.demo && useFirebaseEmulators)
      'NX_USE_EMULATORS solo aplica al backend firebase.',
  ];
}

T _parseEnum<T extends Enum>(List<T> values, String key, String raw) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  throw StateError(
    '$key="$raw" no es válido. Usa: ${values.map((v) => v.name).join(', ')}.',
  );
}
