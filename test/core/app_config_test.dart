import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/config/app_config.dart';
import 'package:nexo_familia/core/id_generator.dart';

AppConfig config({
  String appName = 'Nexo Familia',
  AppEnvironment environment = AppEnvironment.dev,
  BackendMode backend = BackendMode.demo,
  bool useFirebaseEmulators = false,
  String emergencyNumber = '123',
}) => AppConfig(
  appName: appName,
  environment: environment,
  backend: backend,
  useFirebaseEmulators: useFirebaseEmulators,
  emergencyNumber: emergencyNumber,
);

void main() {
  group('AppConfig', () {
    test('los valores por defecto de compilación son válidos', () {
      final defaults = AppConfig.fromEnvironment();
      expect(defaults.appName, 'Nexo Familia');
      expect(defaults.environment, AppEnvironment.dev);
      expect(defaults.backend, BackendMode.demo);
      expect(defaults.emergencyNumber, '123');
      expect(defaults.validate(), isEmpty);
    });

    test('producción no admite backend de demostración ni emuladores', () {
      expect(config(environment: AppEnvironment.prod).validate(), hasLength(1));
      expect(
        config(
          environment: AppEnvironment.prod,
          backend: BackendMode.firebase,
          useFirebaseEmulators: true,
        ).validate(),
        hasLength(1),
      );
      expect(
        config(
          environment: AppEnvironment.prod,
          backend: BackendMode.firebase,
        ).validate(),
        isEmpty,
      );
    });

    test('rechaza nombre vacío y número de emergencia inválido', () {
      expect(config(appName: '  ').validate(), hasLength(1));
      expect(config(emergencyNumber: '12a').validate(), hasLength(1));
      expect(config(emergencyNumber: '1').validate(), hasLength(1));
    });

    test('release no admite demo sin permiso explícito ni emuladores', () {
      AppConfig release({
        BackendMode backend = BackendMode.demo,
        bool emulators = false,
        bool allowDemo = false,
      }) => AppConfig(
        appName: 'Nexo',
        environment: AppEnvironment.staging,
        backend: backend,
        useFirebaseEmulators: emulators,
        emergencyNumber: '123',
        isReleaseBuild: true,
        allowDemoInRelease: allowDemo,
      );
      expect(release().validate(), hasLength(1));
      expect(release(allowDemo: true).validate(), isEmpty);
      expect(
        release(backend: BackendMode.firebase, emulators: true).validate(),
        hasLength(1),
      );
      expect(release(backend: BackendMode.firebase).validate(), isEmpty);
    });

    test('emuladores solo con backend firebase', () {
      expect(config(useFirebaseEmulators: true).validate(), hasLength(1));
    });
  });

  group('UuidV7IdGenerator', () {
    test('genera UUID v7 únicos', () {
      const generator = UuidV7IdGenerator();
      final ids = List.generate(200, (_) => generator.newId());
      expect(ids.toSet(), hasLength(200));
      for (final id in ids) {
        expect(id, matches(RegExp('^[0-9a-f]{8}-[0-9a-f]{4}-7')));
      }
    });

    test('los UUID de milisegundos distintos se ordenan por tiempo', () async {
      const generator = UuidV7IdGenerator();
      final first = generator.newId();
      await Future<void>.delayed(const Duration(milliseconds: 3));
      final second = generator.newId();
      expect(first.compareTo(second), lessThan(0));
    });
  });
}
