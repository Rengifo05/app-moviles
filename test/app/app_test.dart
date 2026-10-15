import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/app/app.dart';
import 'package:nexo_familia/app/session_providers.dart';
import 'package:nexo_familia/core/config/app_config.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/settings/domain/preferences.dart';
import 'package:nexo_familia/features/settings/presentation/settings_providers.dart';

const config = AppConfig(
  appName: 'Nexo Prueba',
  environment: AppEnvironment.dev,
  backend: BackendMode.demo,
  useFirebaseEmulators: false,
  emergencyNumber: '123',
);

/// Arranca la app sin backend: sin onboarding completado, el enrutador
/// muestra la bienvenida.
Future<void> pumpApp(WidgetTester tester, Locale locale) async {
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        preferencesProvider.overrideWith(
          (ref) => Stream.value(const AppPreferences()),
        ),
        currentUserProvider.overrideWith((ref) => Stream.value(null)),
        myFamiliesProvider.overrideWith((ref) => Stream.value(const [])),
        activeFamilyIdOverride,
      ],
      child: const NexoApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('el nombre visible de la app proviene de la configuración', (
    tester,
  ) async {
    await pumpApp(tester, const Locale('es', 'CO'));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Nexo Prueba');
  });

  testWidgets('un idioma no soportado usa español como respaldo', (
    tester,
  ) async {
    await pumpApp(tester, const Locale('fr', 'FR'));
    expect(find.text('Tu familia, cerca y tranquila'), findsWidgets);
  });

  testWidgets('en inglés muestra los textos traducidos', (tester) async {
    await pumpApp(tester, const Locale('en', 'US'));
    expect(find.text('Your family, close and at ease'), findsOneWidget);
  });
}
