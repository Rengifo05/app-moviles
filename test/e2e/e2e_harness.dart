import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart' as fake_time;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/app/app.dart';
import 'package:nexo_familia/app/composition.dart';
import 'package:nexo_familia/app/session_providers.dart';
import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/core/config/app_config.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/infrastructure/database/app_database.dart';

import '../helpers/fakes.dart';

/// Reloj que sigue el tiempo simulado de `testWidgets` (FakeAsync lo expone
/// por `package:clock`): las cuentas atrás y los reintentos avanzan con cada
/// `pump`, igual que los temporizadores.
final class _TestTimeClock implements Clock {
  const new();

  @override
  DateTime now() => fake_time.clock.now().toUtc();
}

const e2eConfig = AppConfig(
  appName: 'Nexo Familia',
  environment: AppEnvironment.dev,
  backend: BackendMode.demo,
  useFirebaseEmulators: false,
  emergencyNumber: '123',
);

/// App completa con el backend de demostración y una base de datos en
/// memoria: el mismo cableado que `bootstrap`, sin red ni dispositivo.
final class E2EApp {
  new _(this.db, this.composition);

  final AppDatabase db;
  final AppComposition composition;

  static Future<E2EApp> start(WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = [const Locale('es', 'CO')];
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    final composition = AppComposition.demo(
      db: db,
      clock: const _TestTimeClock(),
      logSink: MemoryLogSink(),
      random: math.Random(42),
    );
    final app = E2EApp._(db, composition);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(e2eConfig),
          activeFamilyIdOverride,
          ...composition.overrides,
        ],
        child: const NexoApp(),
      ),
    );
    await app.settle(tester);
    return app;
  }

  /// Deja avanzar la base de datos (E/S real), los flujos y las animaciones
  /// durante [rounds] fotogramas de 100 ms. No usa `pumpAndSettle`: los
  /// indicadores de progreso indeterminados nunca se «asientan».
  Future<void> settle(WidgetTester tester, {int rounds = 10}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Espera hasta que [finder] encuentre algo, o falla con un mensaje claro.
  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    int maxRounds = 80,
  }) async {
    for (var i = 0; i < maxRounds; i++) {
      if (finder.evaluate().isNotEmpty) return;
      await settle(tester, rounds: 1);
    }
    throw TestFailure('No apareció a tiempo: $finder');
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder.first);
    await tester.tap(finder.first);
    await settle(tester);
  }

  Future<void> enterField(
    WidgetTester tester,
    String label,
    String value,
  ) async {
    await tester.enterText(find.widgetWithText(TextField, label), value);
    await tester.pump();
  }

  /// Libera la app. Las futuras de la composición viven en la zona de tiempo
  /// simulado de la prueba: hay que bombear fotogramas mientras terminan
  /// (esperarlas dentro de `runAsync` las bloquearía para siempre).
  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    var done = false;
    unawaited(
      composition.dispose().then((_) => db.close()).whenComplete(() {
        done = true;
      }),
    );
    for (var i = 0; i < 100 && !done; i++) {
      await settle(tester, rounds: 1);
    }
    if (!done) throw TestFailure('La app no terminó de liberarse');
  }
}
