import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/features/settings/presentation/settings_screen.dart';
import 'package:nexo_familia/features/settings/presentation/settings_widgets.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

import 'settings_test_harness.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async => l10n = await spanish());

  Future<SettingsFakes> pumpSettings(
    WidgetTester tester, {
    SettingsFakes? fakes,
    bool pushAvailable = false,
    String? appVersion = '0.1.0',
  }) async {
    tester.view
      ..physicalSize = const Size(600, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = fakes ?? SettingsFakes();
    await tester.pumpWidget(
      settingsTestApp(
        overrides: f.overrides(
          pushAvailable: pushAvailable,
          appVersion: appVersion,
        ),
        home: const SettingsScreen(),
      ),
    );
    await settle(tester);
    return f;
  }

  testWidgets('muestra las secciones y el aviso legal', (tester) async {
    await pumpSettings(tester);
    expect(find.text(l10n.settingsSectionPrivacy), findsOne);
    expect(find.text(l10n.settingsSectionAccount), findsOne);
    expect(find.text(l10n.settingsSectionNotifications), findsOne);
    expect(find.text(l10n.settingsSectionAbout), findsOne);
    expect(find.text(breakableAtSeparators('ana@example.com')), findsOne);
    expect(find.text('Nexo Familia'), findsOne);
    expect(find.text(l10n.settingsAboutVersion('0.1.0')), findsOne);
    expect(
      find.text(l10n.settingsAboutDisclaimer('Nexo Familia', '123')),
      findsOne,
    );
  });

  testWidgets('sin versión de la compilación no inventa ninguna', (
    tester,
  ) async {
    await pumpSettings(tester, appVersion: null);
    expect(find.text('Nexo Familia'), findsOne);
    expect(find.textContaining('0.1.0'), findsNothing);
  });

  testWidgets('abre Privacidad y Cuenta', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text(l10n.settingsPrivacyTile));
    await settle(tester);
    expect(find.text('ruta: privacidad'), findsOne);

    await pumpSettings(tester);
    await tester.tap(find.text(l10n.settingsAccountTile));
    await settle(tester);
    expect(find.text('ruta: cuenta'), findsOne);
  });

  testWidgets('ocultar detalles guarda la preferencia', (tester) async {
    final fakes = await pumpSettings(tester);
    expect(fakes.preferences.prefs.value.hideNotificationDetails, isFalse);
    await tester.tap(find.text(l10n.settingsHideDetails));
    await settle(tester);
    expect(fakes.preferences.prefs.value.hideNotificationDetails, isTrue);
    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.value, isTrue);
  });

  testWidgets('si no se guarda, el interruptor no cambia y lo dice', (
    tester,
  ) async {
    final fakes = SettingsFakes()..preferences.failWrites = true;
    await pumpSettings(tester, fakes: fakes);
    await tester.tap(find.text(l10n.settingsHideDetails));
    await settle(tester);
    expect(find.text(l10n.settingsHideDetailsError), findsOne);
    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.value, isFalse);
  });

  testWidgets('sin servicio de avisos lo dice; con él, no', (tester) async {
    await pumpSettings(tester);
    expect(find.text(l10n.settingsPushUnavailable), findsOne);

    await pumpSettings(tester, pushAvailable: true);
    expect(find.text(l10n.settingsPushUnavailable), findsNothing);
  });

  testWidgets('abre el resumen de privacidad en una hoja', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text(l10n.settingsAboutPrivacySummary));
    await settle(tester);
    expect(find.text(l10n.privacySummaryTitle), findsOne);
    expect(find.text(l10n.privacySummaryBody), findsOne);
    await tester.tap(find.text(l10n.commonClose));
    await settle(tester);
    expect(find.text(l10n.privacySummaryBody), findsNothing);
  });
}
