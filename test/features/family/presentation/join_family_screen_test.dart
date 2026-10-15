import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';

import 'family_test_harness.dart';

void main() {
  Future<FamilyTestEnv> open(WidgetTester tester, [FamilyTestEnv? env]) async {
    final e = env ?? FamilyTestEnv(activeFamilyId: null);
    await pumpFamilyApp(tester, e, initialLocation: AppRoutes.joinFamily);
    return e;
  }

  Future<void> submit(WidgetTester tester, String code) async {
    await tester.enterText(find.byType(TextField), code);
    await tester.tap(find.text('Unirme'));
    await pumpFrames(tester);
  }

  testWidgets('muestra la ayuda del formato y pasa el código a mayúsculas', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Formato: ABCDE-FGHJK'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'abcde-fghjk');
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'ABCDE-FGHJK');
  });

  testWidgets('un código mal formado se explica sin llamar al servidor', (
    tester,
  ) async {
    final env = await open(tester);
    await submit(tester, 'ABC');
    expect(
      find.text('Revisa el código: son 10 letras y números, como ABCDE-FGHJK.'),
      findsOneWidget,
    );
    expect(env.families.acceptCalls, isEmpty);
  });

  testWidgets('con un código válido se une y activa la familia', (
    tester,
  ) async {
    final env = await open(tester);
    await submit(tester, 'abcde fghjk');
    expect(env.families.acceptCalls, ['ABCDE FGHJK']);
    expect(env.preferences.prefs.value.activeFamilyId, 'fam-joined');
  });

  final cases = <String, (Failure, String)>{
    'invitation-invalid': (
      const Failure.notFound('invitation-invalid'),
      'El código no es válido o ya venció. Pide uno nuevo a quien te invitó.',
    ),
    'already-member': (
      const Failure.conflict('already-member'),
      'Ya perteneces a esta familia.',
    ),
    'family-full': (
      const Failure(FailureKind.rateLimited, 'family-full'),
      'Esta familia ya tiene 12 integrantes, el máximo permitido.',
    ),
    'rate-limited': (
      const Failure(FailureKind.rateLimited, 'rate-limited'),
      'Hiciste demasiados intentos. Por seguridad, espera un rato antes de '
          'volver a intentarlo.',
    ),
    'invitation-format (servidor)': (
      const Failure.validation('invitation-format'),
      'Revisa el código: son 10 letras y números, como ABCDE-FGHJK.',
    ),
    'sin conexión': (
      const Failure.network(),
      'No hay conexión. Revisa tu red e inténtalo de nuevo.',
    ),
  };
  for (final MapEntry(key: name, value: (failure, message)) in cases.entries) {
    testWidgets('error: $name', (tester) async {
      final env = FamilyTestEnv(activeFamilyId: null);
      env.families.accept.result = Err(failure);
      await open(tester, env);
      await submit(tester, 'ABCDE-FGHJK');
      expect(find.text(message), findsOneWidget);
      expect(env.preferences.prefs.value.activeFamilyId, isNull);
    });
  }

  testWidgets('al 200 % el error del servidor queda a la vista', (
    tester,
  ) async {
    final env = FamilyTestEnv(activeFamilyId: null);
    env.families.accept.result = const Err(
      Failure.notFound('invitation-invalid'),
    );
    await pumpFamilyApp(
      tester,
      env,
      initialLocation: AppRoutes.joinFamily,
      textScale: 2,
    );
    await tester.enterText(find.byType(TextField), 'ABCDE-FGHJK');
    await scrollAndTap(tester, find.text('Unirme'));
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('El código no es válido').hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('al 200 % un código mal formado lleva al campo', (tester) async {
    await pumpFamilyApp(
      tester,
      FamilyTestEnv(activeFamilyId: null),
      initialLocation: AppRoutes.joinFamily,
      textScale: 2,
    );
    await tester.enterText(find.byType(TextField), 'ABC');
    await scrollAndTap(tester, find.text('Unirme'));
    await pumpFrames(tester);
    expect(
      find.textContaining('Revisa el código').hitTestable(),
      findsOneWidget,
    );
  });
}
