import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/design_system/tokens/nx_colors.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/check_ins/domain/submit_check_in.dart';
import 'package:nexo_familia/features/check_ins/presentation/check_in_controller.dart';
import 'package:nexo_familia/features/check_ins/presentation/check_in_widgets.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';

import 'check_in_test_support.dart';

void main() {
  final l10n = esL10n;

  Finder option(CheckInKind kind) =>
      find.byWidgetPredicate((w) => w is CheckInOptionTile && w.kind == kind);

  Finder sendButton() => find.widgetWithText(TextButton, l10n.checkInSend);

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<TextButton>(button).onPressed != null;

  Future<void> choose(WidgetTester tester, CheckInKind kind) =>
      scrollAndTap(tester, option(kind));

  Future<void> send(WidgetTester tester) => scrollAndTap(tester, sendButton());

  group('formulario', () {
    testWidgets('dos opciones, explicación del SOS y Enviar desactivado', (
      tester,
    ) async {
      await pumpCheckInScreen(tester, CheckInTestEnv());

      expect(find.text(l10n.checkInHeading), findsOneWidget);
      expect(find.text(l10n.checkInOptionOk), findsOneWidget);
      expect(find.text(l10n.checkInOptionHelp), findsOneWidget);
      expect(find.text(l10n.checkInSosExplainer), findsOneWidget);
      expect(find.text(l10n.checkInGoToSos), findsOneWidget);
      expect(enabled(tester, sendButton()), isFalse);
      expect(find.text(l10n.checkInChooseFirst), findsOneWidget);

      await choose(tester, CheckInKind.needHelp);
      expect(enabled(tester, sendButton()), isTrue);
      expect(find.text(l10n.checkInChooseFirst), findsNothing);
    });

    testWidgets('las opciones son un grupo de selección única', (tester) async {
      await pumpCheckInScreen(tester, CheckInTestEnv());
      await choose(tester, CheckInKind.ok);

      expect(
        tester.getSemantics(option(CheckInKind.ok)),
        isSemantics(
          label: '${l10n.checkInOptionOk}\n${l10n.checkInOptionOkHint}',
          isInMutuallyExclusiveGroup: true,
          hasCheckedState: true,
          isChecked: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(option(CheckInKind.needHelp)),
        isSemantics(
          isInMutuallyExclusiveGroup: true,
          hasCheckedState: true,
          isChecked: false,
        ),
      );
    });

    testWidgets('"Necesito ayuda" usa el tono ámbar, no el rojo del SOS', (
      tester,
    ) async {
      await pumpCheckInScreen(tester, CheckInTestEnv());
      await choose(tester, CheckInKind.needHelp);

      final material = tester.widget<Material>(
        find.descendant(
          of: option(CheckInKind.needHelp),
          matching: find.byType(Material),
        ),
      );
      expect(material.color, NxColors.light.warningContainer);
      expect(material.color, isNot(NxColors.light.emergencyFill));
      expect(material.color, isNot(NxColors.light.emergencyContainer));
    });

    testWidgets('Ir al SOS abre el SOS', (tester) async {
      await pumpCheckInScreen(tester, CheckInTestEnv());
      await scrollAndTap(tester, find.text(l10n.checkInGoToSos));
      expect(find.text('stub:${AppRoutes.sos}'), findsOneWidget);
    });

    testWidgets('el contador mide el mensaje recortado y avisa si se pasa', (
      tester,
    ) async {
      await pumpCheckInScreen(tester, CheckInTestEnv());
      await choose(tester, CheckInKind.ok);

      await tester.enterText(find.byType(TextField), '  Hola  ');
      await reveal(tester, find.text('4/140'));
      expect(find.text('4/140'), findsOneWidget);
      // El lector de pantalla anuncia lo que queda junto con la etiqueta.
      expect(
        tester.getSemantics(find.byType(TextField)).label,
        allOf(
          contains(l10n.checkInMessageLabel),
          contains(l10n.checkInMessageRemaining(136)),
        ),
      );

      await tester.enterText(find.byType(TextField), 'a' * 141);
      await tester.pump();
      expect(find.text('141/140'), findsOneWidget);
      expect(find.text(l10n.checkInMessageTooLong(140)), findsOneWidget);
      expect(enabled(tester, sendButton()), isFalse);
    });

    testWidgets('interruptor de ubicación solo si la comparte', (tester) async {
      await pumpCheckInScreen(
        tester,
        CheckInTestEnv(sharing: SharingState.paused),
      );
      await reveal(tester, find.text(l10n.checkInLocationNotShared));
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text(l10n.checkInLocationNotShared), findsOneWidget);
    });

    testWidgets('con precisión aproximada lo dice', (tester) async {
      await pumpCheckInScreen(
        tester,
        CheckInTestEnv(precision: LocationPrecision.approximate),
      );
      await reveal(tester, find.byType(SwitchListTile));
      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.text(l10n.checkInIncludeLocationOffApprox), findsOneWidget);

      await scrollAndTap(tester, find.byType(Switch));
      expect(find.text(l10n.checkInIncludeLocationApprox), findsOneWidget);
    });

    testWidgets('un error al guardar se muestra y se puede reintentar', (
      tester,
    ) async {
      final env = CheckInTestEnv();
      env.repository.submitFailure = const Failure.unexpected(
        CheckInFailureCodes.notSaved,
      );
      await pumpCheckInScreen(tester, env);
      await choose(tester, CheckInKind.ok);
      await send(tester);

      expect(find.text(l10n.checkInErrorNotSaved), findsOneWidget);
      // Sigue en el formulario, con la opción elegida.
      expect(find.text(l10n.checkInSendingTitle), findsNothing);
      expect(
        tester.widget<CheckInOptionTile>(option(CheckInKind.ok)).selected,
        isTrue,
      );

      env.repository.submitFailure = null;
      await send(tester);
      expect(find.text(l10n.checkInSendingTitle), findsOneWidget);
      expect(env.repository.submitted, hasLength(2));
      // Cada intento es una operación distinta.
      expect(env.repository.submitted.map((c) => c.id).toSet(), hasLength(2));
    });
  });

  group('envío', () {
    testWidgets('envía la opción y el mensaje recortado, sin ubicación', (
      tester,
    ) async {
      final env = CheckInTestEnv();
      await pumpCheckInScreen(tester, env);
      await choose(tester, CheckInKind.ok);
      await tester.enterText(find.byType(TextField), '  Ya llegué  ');
      await send(tester);

      final sent = env.repository.submitted.single;
      expect(sent.kind, CheckInKind.ok);
      expect(sent.message, 'Ya llegué');
      expect(sent.familyId, familyId);
      expect(sent.uid, me.uid);
      expect(sent.location, isNull);
      expect(env.device.fixCalls, 0);
    });

    testWidgets('"Enviando…" hasta que el servidor confirma', (tester) async {
      final env = CheckInTestEnv();
      await pumpCheckInScreen(tester, env);
      await choose(tester, CheckInKind.ok);
      await send(tester);

      expect(find.text(l10n.checkInSendingTitle), findsOneWidget);
      expect(find.text(l10n.checkInDeliveredTitle), findsNothing);

      env.repository.deliver('id-1');
      await pumpFrames(tester);
      expect(find.text(l10n.checkInDeliveredTitle), findsOneWidget);
      expect(find.text(l10n.checkInDeliveredBody), findsOneWidget);

      await scrollAndTap(tester, find.text(l10n.checkInDone));
      expect(find.text('stub:${AppRoutes.home}'), findsOneWidget);
    });

    testWidgets('si no se confirma pronto: guardado, se enviará después', (
      tester,
    ) async {
      final env = CheckInTestEnv();
      await pumpCheckInScreen(tester, env);
      await choose(tester, CheckInKind.needHelp);
      await send(tester);

      await tester.pump(CheckInController.settleDelay);
      await pumpFrames(tester);
      expect(find.text(l10n.checkInQueuedTitle), findsOneWidget);
      expect(find.text(l10n.checkInDeliveredTitle), findsNothing);

      // Más tarde se recupera la conexión y sale de la bandeja.
      env.repository.deliver('id-1');
      await pumpFrames(tester);
      expect(find.text(l10n.checkInDeliveredTitle), findsOneWidget);
    });

    testWidgets('sin conexión: guardado de inmediato, no "Enviando…"', (
      tester,
    ) async {
      final env = CheckInTestEnv(syncStatus: SyncStatus.offline);
      await pumpCheckInScreen(tester, env);
      expect(find.text(l10n.checkInOfflineBanner), findsOneWidget);
      await choose(tester, CheckInKind.ok);
      await send(tester);

      expect(find.text(l10n.checkInQueuedTitle), findsOneWidget);
      expect(find.text(l10n.checkInSendingTitle), findsNothing);
      await tester.pump(CheckInController.settleDelay);
      await pumpFrames(tester);
      expect(find.text(l10n.checkInQueuedTitle), findsOneWidget);
    });

    testWidgets(
      'si la lista aún no lo refleja, no lo da por entregado antes de tiempo',
      (tester) async {
        final env = CheckInTestEnv();
        // Se entrega tan rápido que la lista nunca lo muestra.
        env.repository.enqueueOnSubmit = false;
        await pumpCheckInScreen(tester, env);
        await choose(tester, CheckInKind.ok);
        await send(tester);

        expect(find.text(l10n.checkInSendingTitle), findsOneWidget);
        expect(find.text(l10n.checkInDeliveredTitle), findsNothing);

        await tester.pump(CheckInController.settleDelay);
        await pumpFrames(tester);
        expect(find.text(l10n.checkInDeliveredTitle), findsOneWidget);
      },
    );

    testWidgets('rechazado: reintentar lo vuelve a enviar', (tester) async {
      final env = CheckInTestEnv();
      await pumpCheckInScreen(tester, env);
      await choose(tester, CheckInKind.needHelp);
      await send(tester);

      env.repository.fail('id-1');
      await pumpFrames(tester);
      expect(find.text(l10n.checkInFailedTitle), findsOneWidget);
      expect(find.text(l10n.checkInDeliveredTitle), findsNothing);

      await scrollAndTap(tester, find.text(l10n.commonRetry));
      expect(env.repository.retried, ['id-1']);
      expect(find.text(l10n.checkInSendingTitle), findsOneWidget);

      env.repository.deliver('id-1');
      await pumpFrames(tester);
      expect(find.text(l10n.checkInDeliveredTitle), findsOneWidget);
    });

    testWidgets('rechazado: descartar vuelve al formulario con la opción', (
      tester,
    ) async {
      final env = CheckInTestEnv();
      await pumpCheckInScreen(tester, env);
      await choose(tester, CheckInKind.needHelp);
      await send(tester);
      env.repository.fail('id-1');
      await pumpFrames(tester);

      await scrollAndTap(tester, find.text(l10n.checkInDiscard));
      await tester.pump(CheckInController.settleDelay);
      await pumpFrames(tester);

      expect(env.repository.discarded, ['id-1']);
      expect(find.text(l10n.checkInDeliveredTitle), findsNothing);
      expect(find.text(l10n.checkInHeading), findsOneWidget);
      expect(
        tester.widget<CheckInOptionTile>(option(CheckInKind.needHelp)).selected,
        isTrue,
      );
    });

    testWidgets('un error al reintentar se muestra', (tester) async {
      final env = CheckInTestEnv();
      env.repository.retryFailure = const Failure.notFound(
        CheckInFailureCodes.notFound,
      );
      await pumpCheckInScreen(tester, env);
      await choose(tester, CheckInKind.ok);
      await send(tester);
      env.repository.fail('id-1');
      await pumpFrames(tester);

      await scrollAndTap(tester, find.text(l10n.commonRetry));
      expect(find.text(l10n.checkInErrorNotFound), findsOneWidget);
      expect(find.text(l10n.checkInFailedTitle), findsOneWidget);
    });
  });

  group('ubicación', () {
    testWidgets('se adjunta solo si la persona activa el interruptor', (
      tester,
    ) async {
      final env = CheckInTestEnv();
      await pumpCheckInScreen(tester, env);
      await choose(tester, CheckInKind.needHelp);
      await scrollAndTap(tester, find.byType(Switch));
      await send(tester);

      expect(env.repository.submitted.single.location, syntheticPoint);
      expect(find.text(l10n.checkInWithLocation), findsOneWidget);
    });

    testWidgets('con precisión aproximada se envía redondeada', (tester) async {
      final env = CheckInTestEnv(precision: LocationPrecision.approximate);
      await pumpCheckInScreen(tester, env);
      await choose(tester, CheckInKind.ok);
      await scrollAndTap(tester, find.byType(Switch));
      await send(tester);

      expect(
        env.repository.submitted.single.location,
        syntheticPoint.approximate(),
      );
      expect(find.text(l10n.checkInWithApproxLocation), findsOneWidget);
    });

    testWidgets('si no se obtiene, se envía sin ella y lo dice', (
      tester,
    ) async {
      final env = CheckInTestEnv(device: FakeDeviceLocation());
      await pumpCheckInScreen(tester, env);
      await choose(tester, CheckInKind.ok);
      await scrollAndTap(tester, find.byType(Switch));
      await send(tester);

      expect(env.repository.submitted.single.location, isNull);
      expect(find.text(l10n.checkInLocationOmitted), findsOneWidget);
    });

    testWidgets('sin compartir no se busca la ubicación', (tester) async {
      final env = CheckInTestEnv(sharing: SharingState.notConfigured);
      await pumpCheckInScreen(tester, env);
      await choose(tester, CheckInKind.ok);
      await send(tester);

      expect(env.repository.submitted.single.location, isNull);
      expect(env.device.fixCalls, 0);
    });
  });

  group('pendientes', () {
    testWidgets('lista los pendientes y fallidos; reintenta los fallidos', (
      tester,
    ) async {
      final env = CheckInTestEnv(
        repository: FakeCheckInRepository([
          sampleCheckIn(id: 'old-1', message: 'Salí del trabajo'),
          sampleCheckIn(
            id: 'old-2',
            kind: CheckInKind.needHelp,
            delivery: DeliveryState.failed,
            age: const Duration(minutes: 3),
          ),
        ]),
      );
      await pumpCheckInScreen(tester, env);

      await tester.scrollUntilVisible(
        find.text(l10n.checkInPendingTitle),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(l10n.checkInStatusPending), findsOneWidget);
      expect(find.text(l10n.checkInStatusFailed), findsOneWidget);
      expect(find.text('Salí del trabajo'), findsOneWidget);
      expect(
        find.text(l10n.checkInSavedAt(l10n.relativeMinutes(12))),
        findsOneWidget,
      );
      // Solo el fallido ofrece reintentar.
      expect(find.text(l10n.commonRetry), findsOneWidget);

      await scrollAndTap(tester, find.text(l10n.commonRetry));
      expect(env.repository.retried, ['old-2']);
      expect(find.text(l10n.checkInStatusFailed), findsNothing);
    });

    testWidgets('descartar un fallido de la lista', (tester) async {
      final env = CheckInTestEnv(
        repository: FakeCheckInRepository([
          sampleCheckIn(id: 'old-2', delivery: DeliveryState.failed),
        ]),
      );
      await pumpCheckInScreen(tester, env);
      await scrollAndTap(tester, find.text(l10n.checkInDiscard));
      expect(env.repository.discarded, ['old-2']);
      expect(find.text(l10n.checkInPendingTitle), findsNothing);
    });

    testWidgets('el recién enviado no se repite en la lista', (tester) async {
      final env = CheckInTestEnv(
        repository: FakeCheckInRepository([sampleCheckIn(id: 'old-1')]),
      );
      await pumpCheckInScreen(tester, env);
      await choose(tester, CheckInKind.ok);
      await send(tester);
      await tester.pump(CheckInController.settleDelay);
      await pumpFrames(tester);

      expect(find.text(l10n.checkInQueuedTitle), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(l10n.checkInPendingTitle),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // Solo el anterior figura en la lista.
      expect(find.text(l10n.checkInStatusPending), findsOneWidget);
    });
  });

  testWidgets('sin familia activa lo explica', (tester) async {
    await pumpCheckInScreen(tester, CheckInTestEnv(activeFamilyId: null));
    expect(find.text(l10n.checkInNoFamily), findsOneWidget);
    await tester.tap(find.text(l10n.checkInSetUpFamily));
    await pumpFrames(tester);
    expect(find.text('stub:${AppRoutes.familySetup}'), findsOneWidget);
  });

  testWidgets('en inglés', (tester) async {
    await pumpCheckInScreen(
      tester,
      CheckInTestEnv(),
      locale: const Locale('en'),
    );
    expect(find.text('How are you?'), findsOneWidget);
    expect(find.text("I'm OK"), findsOneWidget);
    expect(find.text('I need help'), findsOneWidget);
  });

  testWidgets('texto al 200 %: sin desbordes', (tester) async {
    final env = CheckInTestEnv(
      precision: LocationPrecision.approximate,
      repository: FakeCheckInRepository([
        sampleCheckIn(
          id: 'old-2',
          kind: CheckInKind.needHelp,
          delivery: DeliveryState.failed,
          message: 'Se me descargó el carro, ¿alguien puede pasar por mí?',
        ),
      ]),
    );
    await pumpCheckInScreen(tester, env, textScale: 2);
    await choose(tester, CheckInKind.needHelp);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
    await send(tester);
    env.repository.fail('id-1');
    await pumpFrames(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
  });
}
