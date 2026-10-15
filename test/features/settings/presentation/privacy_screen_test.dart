import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/settings/presentation/privacy_screen.dart';
import 'package:nexo_familia/features/settings/presentation/settings_widgets.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

import 'settings_test_harness.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async => l10n = await spanish());

  /// Vista alta para que toda la página quede construida.
  void tallView(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(600, 2600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<SettingsFakes> pumpPrivacy(
    WidgetTester tester, {
    SettingsFakes? fakes,
    SyncStatus sync = SyncStatus.live,
    String? activeFamilyId = familyId,
  }) async {
    tallView(tester);
    final f = fakes ?? SettingsFakes();
    await tester.pumpWidget(
      settingsTestApp(
        overrides: f.overrides(sync: sync, activeFamilyId: activeFamilyId),
        home: const PrivacyScreen(),
        initialLocation: AppRoutes.privacy,
      ),
    );
    await settle(tester);
    return f;
  }

  Finder inSheet(String text) => find.descendant(
    of: find.byType(ShareExplanationSheet),
    matching: find.text(text),
  );

  testWidgets('muestra mi estado, quién puede verme y la retención', (
    tester,
  ) async {
    await pumpPrivacy(tester);
    expect(find.text(l10n.settingsPrivacyHeading('Familia Rojas')), findsOne);
    expect(find.text(l10n.settingsPrivacyStateSharingExact), findsOne);
    expect(find.text(l10n.settingsPrivacyPause), findsOne);
    expect(find.text(l10n.settingsPrivacyAudienceSharing), findsOne);
    // Los demás integrantes, no la persona actual.
    expect(find.text('Luis Rojas'), findsOne);
    expect(find.text('Marta'), findsOne);
    expect(find.text('Ana Rojas'), findsNothing);
    expect(find.text(l10n.settingsPrivacyDataLocation), findsOne);
    expect(find.text(l10n.settingsPrivacyDataEvents), findsOne);
    expect(find.text(l10n.settingsPrivacyDataSos), findsOne);
    expect(find.text(l10n.settingsPrivacyDataAudit), findsOne);
    expect(find.text(l10n.settingsPrivacyLeave), findsOne);
    // Nunca afirma que alguien esté a salvo.
    expect(find.textContaining('seguro'), findsNothing);
    expect(find.textContaining('a salvo'), findsNothing);
  });

  testWidgets('sin decidir: "Aún no decides" y dos opciones', (tester) async {
    await pumpPrivacy(
      tester,
      fakes: SettingsFakes(
        location: FakeLocationRepository(state: SharingState.notConfigured),
      ),
    );
    expect(find.text(l10n.settingsPrivacyStateNotConfigured), findsOne);
    expect(find.text(l10n.settingsPrivacyShare), findsOne);
    expect(find.text(l10n.settingsPrivacyKeepPaused), findsOne);
    expect(find.text(l10n.settingsPrivacyAudienceNotSharing), findsOne);
  });

  testWidgets('"No compartir por ahora" guarda la pausa tras Ok', (
    tester,
  ) async {
    final fakes = await pumpPrivacy(
      tester,
      fakes: SettingsFakes(
        location: FakeLocationRepository(state: SharingState.notConfigured),
      ),
    );
    await tester.tap(find.text(l10n.settingsPrivacyKeepPaused));
    await settle(tester);
    expect(fakes.location.updates.single.state, SharingState.paused);
    expect(find.text(l10n.settingsPrivacyKeptPausedOk), findsOne);
    expect(find.text(l10n.settingsPrivacyStatePaused), findsOne);
  });

  testWidgets('activar explica primero; "Ahora no" no pide ni guarda nada', (
    tester,
  ) async {
    final fakes = await pumpPrivacy(
      tester,
      fakes: SettingsFakes(
        location: FakeLocationRepository(state: SharingState.paused),
        device: FakeDeviceLocation(
          current: DeviceLocationPermission.notDetermined,
        ),
      ),
    );
    await tester.tap(find.text(l10n.settingsPrivacyShare));
    await settle(tester);
    expect(find.byType(ShareExplanationSheet), findsOne);
    expect(inSheet(l10n.settingsShareSheetWho('Familia Rojas')), findsOne);
    expect(inSheet('Luis Rojas'), findsOne);
    expect(inSheet('Marta'), findsOne);
    expect(inSheet(l10n.settingsShareSheetPause), findsOne);

    await tester.tap(inSheet(l10n.settingsShareSheetCancel));
    await settle(tester);
    expect(fakes.device.requests, 0);
    expect(fakes.location.updates, isEmpty);
    expect(find.text(l10n.settingsPrivacyStatePaused), findsOne);
  });

  testWidgets(
    'activar: pide el permiso tras la explicación y confirma tras Ok',
    (tester) async {
      final fakes = await pumpPrivacy(
        tester,
        fakes: SettingsFakes(
          location: FakeLocationRepository(state: SharingState.paused),
          device: FakeDeviceLocation(
            current: DeviceLocationPermission.notDetermined,
          ),
        ),
      );
      await tester.tap(find.text(l10n.settingsPrivacyShare));
      await settle(tester);
      await tester.tap(inSheet(l10n.settingsPrivacyShare));
      await settle(tester);

      expect(fakes.device.requests, 1);
      expect(fakes.location.updates.single.state, SharingState.sharing);
      expect(find.text(l10n.settingsPrivacySharedOk), findsOne);
      expect(find.text(l10n.settingsPrivacyStateSharingExact), findsOne);
      expect(find.text(l10n.settingsPrivacyPermissionMissing), findsNothing);

      await tester.tap(find.text(l10n.settingsPrivacyGoToMap));
      await settle(tester);
      expect(find.text('ruta: mapa'), findsOne);
    },
  );

  testWidgets('permiso denegado: guarda la decisión y avisa sin fingir', (
    tester,
  ) async {
    final fakes = await pumpPrivacy(
      tester,
      fakes: SettingsFakes(
        location: FakeLocationRepository(state: SharingState.paused),
        device: FakeDeviceLocation(
          current: DeviceLocationPermission.notDetermined,
          afterRequest: DeviceLocationPermission.denied,
        ),
      ),
    );
    await tester.tap(find.text(l10n.settingsPrivacyShare));
    await settle(tester);
    await tester.tap(inSheet(l10n.settingsPrivacyShare));
    await settle(tester);

    expect(fakes.device.requests, 1);
    expect(fakes.location.updates.single.state, SharingState.sharing);
    expect(find.text(l10n.settingsPrivacyPermissionMissing), findsOne);
    // No dice "Listo" si no se puede enviar nada.
    expect(find.text(l10n.settingsPrivacySharedOk), findsNothing);

    await tester.tap(find.text(l10n.commonOpenSettings));
    await settle(tester);
    expect(fakes.device.settingsOpened, 1);
  });

  testWidgets('denegado para siempre: no vuelve a pedir el permiso', (
    tester,
  ) async {
    final fakes = await pumpPrivacy(
      tester,
      fakes: SettingsFakes(
        location: FakeLocationRepository(state: SharingState.paused),
        device: FakeDeviceLocation(
          current: DeviceLocationPermission.deniedForever,
        ),
      ),
    );
    await tester.tap(find.text(l10n.settingsPrivacyShare));
    await settle(tester);
    await tester.tap(inSheet(l10n.settingsPrivacyShare));
    await settle(tester);
    expect(fakes.device.requests, 0);
    expect(fakes.location.updates.single.state, SharingState.sharing);
    expect(find.text(l10n.settingsPrivacyPermissionMissing), findsOne);
  });

  testWidgets('pausar confirma solo tras Ok', (tester) async {
    final fakes = SettingsFakes()..location.gate = Completer<void>();
    await pumpPrivacy(tester, fakes: fakes);
    await tester.tap(find.text(l10n.settingsPrivacyPause));
    await tester.pump();
    // En curso: aún no se muestra como pausado.
    expect(find.text(l10n.settingsPrivacyStatePaused), findsNothing);
    expect(find.text(l10n.settingsPrivacyPausedOk), findsNothing);

    fakes.location.gate!.complete();
    await settle(tester);
    expect(fakes.location.updates.single.state, SharingState.paused);
    expect(find.text(l10n.settingsPrivacyPausedOk), findsOne);
    expect(find.text(l10n.settingsPrivacyStatePaused), findsOne);
  });

  testWidgets('pausa que falla por red: no se muestra como pausado', (
    tester,
  ) async {
    final fakes = SettingsFakes()
      ..location.updateResult = const Err(networkFailure);
    await pumpPrivacy(tester, fakes: fakes, sync: SyncStatus.offline);
    expect(find.text(l10n.commonOfflineBanner), findsOne);

    await tester.tap(find.text(l10n.settingsPrivacyPause));
    await settle(tester);
    expect(
      find.text(l10n.settingsPrivacyPauseFailed(l10n.errorNetwork)),
      findsOne,
    );
    expect(find.text(l10n.settingsPrivacyPausedOk), findsNothing);
    expect(find.text(l10n.settingsPrivacyStatePaused), findsNothing);
    expect(find.text(l10n.settingsPrivacyStateSharingExact), findsOne);

    // Reintentar con la conexión de vuelta sí la pausa.
    fakes.location.updateResult = const Ok(null);
    await tester.tap(find.text(l10n.commonRetry));
    await settle(tester);
    expect(fakes.location.updates, hasLength(2));
    expect(find.text(l10n.settingsPrivacyPausedOk), findsOne);
    expect(find.text(l10n.settingsPrivacyStatePaused), findsOne);
  });

  testWidgets('un rechazo del servidor no ofrece reintentar', (tester) async {
    final fakes = SettingsFakes()
      ..location.updateResult = const Err(Failure.permissionDenied());
    await pumpPrivacy(tester, fakes: fakes);
    await tester.tap(find.text(l10n.settingsPrivacyPause));
    await settle(tester);
    expect(
      find.text(l10n.settingsPrivacyPauseFailed(l10n.settingsPrivacyRejected)),
      findsOne,
    );
    expect(find.text(l10n.commonRetry), findsNothing);
  });

  testWidgets('cambiar a aproximada avisa de la última ubicación exacta', (
    tester,
  ) async {
    final fakes = await pumpPrivacy(tester);
    await tester.tap(find.text(l10n.settingsPrivacyPrecisionApprox));
    await settle(tester);
    final update = fakes.location.updates.single;
    expect(update.precision, LocationPrecision.approximate);
    expect(update.state, SharingState.sharing);
    expect(find.text(l10n.settingsPrivacyPrecisionOkApproxSharing), findsOne);
    expect(find.text(l10n.settingsPrivacyStateSharingApprox), findsOne);
  });

  testWidgets('cambiar la precisión sin conexión no la cambia', (tester) async {
    final fakes = SettingsFakes()
      ..location.updateResult = const Err(networkFailure);
    await pumpPrivacy(tester, fakes: fakes);
    await tester.tap(find.text(l10n.settingsPrivacyPrecisionApprox));
    await settle(tester);
    expect(
      find.text(l10n.settingsPrivacyPrecisionFailed(l10n.errorNetwork)),
      findsOne,
    );
    expect(find.text(l10n.settingsPrivacyStateSharingExact), findsOne);
  });

  testWidgets('salir de la familia pide confirmación', (tester) async {
    final fakes = await pumpPrivacy(tester);
    await tester.tap(find.text(l10n.settingsPrivacyLeave));
    await settle(tester);
    expect(find.text(l10n.familyLeaveTitle('Familia Rojas')), findsOne);
    expect(find.text(l10n.familyLeaveOwner), findsOne);

    await tester.tap(find.text(l10n.commonCancel));
    await settle(tester);
    expect(fakes.families.left, isEmpty);

    await tester.tap(find.text(l10n.settingsPrivacyLeave));
    await settle(tester);
    await tester.tap(find.text(l10n.familyLeave));
    await settle(tester);
    expect(fakes.families.left, [familyId]);
    expect(fakes.preferences.prefs.value.activeFamilyId, isNull);
    expect(find.text(l10n.familyLeft('Familia Rojas')), findsOne);
  });

  testWidgets('sin familia activa lo explica', (tester) async {
    await pumpPrivacy(tester, activeFamilyId: null);
    expect(find.text(l10n.settingsPrivacyNoFamily), findsOne);
  });
}
