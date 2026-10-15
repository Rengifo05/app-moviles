import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/app/app.dart';
import 'package:nexo_familia/core/config/app_config.dart';
import 'package:nexo_familia/core/di/core_providers.dart';

const config = AppConfig(
  appName: 'Nexo Prueba',
  environment: AppEnvironment.dev,
  backend: BackendMode.demo,
  useFirebaseEmulators: false,
  emergencyNumber: '123',
);

Future<void> pumpApp(WidgetTester tester, Locale locale) async {
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(config)],
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

    expect(find.text('Nexo Prueba'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'Nexo Prueba',
    );
    expect(
      find.text('La seguridad de tu familia, en un solo lugar.'),
      findsOneWidget,
    );
  });

  testWidgets('un idioma no soportado usa español como respaldo', (
    tester,
  ) async {
    await pumpApp(tester, const Locale('fr', 'FR'));
    expect(
      find.text('La seguridad de tu familia, en un solo lugar.'),
      findsOneWidget,
    );
  });

  testWidgets('en inglés muestra los textos traducidos', (tester) async {
    await pumpApp(tester, const Locale('en', 'US'));
    expect(
      find.text("Your family's safety, all in one place."),
      findsOneWidget,
    );
  });
}
