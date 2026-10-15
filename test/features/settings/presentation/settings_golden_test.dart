@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/settings/presentation/account_screen.dart';
import 'package:nexo_familia/features/settings/presentation/privacy_screen.dart';
import 'package:nexo_familia/features/settings/presentation/settings_screen.dart';
import 'package:nexo_familia/features/settings/presentation/settings_widgets.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

import '../../../helpers/fonts.dart';
import 'settings_test_harness.dart';

/// Ajustes, Privacidad y Cuenta en claro al 100 % y oscuro al 200 %.
/// Para regenerar: `flutter test --update-goldens <este archivo>`.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await spanish();
  });

  const variants = [('claro_x1', false, 1.0), ('oscuro_x2', true, 2.0)];

  void phoneView(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required Widget home,
    required String location,
    required bool dark,
    required double scale,
    SettingsFakes? fakes,
    int? pendingOutbox,
  }) async {
    phoneView(tester);
    await tester.pumpWidget(
      settingsTestApp(
        overrides: (fakes ?? SettingsFakes()).overrides(
          pendingOutbox: pendingOutbox,
        ),
        home: home,
        initialLocation: location,
        theme: dark ? NxTheme.dark() : NxTheme.light(),
        textScale: scale,
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
  }

  for (final (name, dark, scale) in variants) {
    testWidgets('ajustes $name', (tester) async {
      await pumpScreen(
        tester,
        home: const SettingsScreen(),
        location: AppRoutes.settings,
        dark: dark,
        scale: scale,
      );
      await expectLater(
        find.byType(SettingsScreen),
        matchesGoldenFile('goldens/settings_$name.png'),
      );
    });

    testWidgets('privacidad compartiendo $name', (tester) async {
      await pumpScreen(
        tester,
        home: const PrivacyScreen(),
        location: AppRoutes.privacy,
        dark: dark,
        scale: scale,
      );
      await expectLater(
        find.byType(PrivacyScreen),
        matchesGoldenFile('goldens/privacy_sharing_$name.png'),
      );
    });

    testWidgets('privacidad sin decidir, desplazada $name', (tester) async {
      await pumpScreen(
        tester,
        home: const PrivacyScreen(),
        location: AppRoutes.privacy,
        dark: dark,
        scale: scale,
        fakes: SettingsFakes(
          location: FakeLocationRepository(state: SharingState.notConfigured),
        ),
      );
      await tester.scrollUntilVisible(
        find.text(l10n.settingsPrivacyDataTitle),
        300,
      );
      await settle(tester);
      await expectLater(
        find.byType(PrivacyScreen),
        matchesGoldenFile('goldens/privacy_scrolled_$name.png'),
      );
    });

    testWidgets('explicación antes de compartir $name', (tester) async {
      await pumpScreen(
        tester,
        home: const PrivacyScreen(),
        location: AppRoutes.privacy,
        dark: dark,
        scale: scale,
        fakes: SettingsFakes(
          location: FakeLocationRepository(state: SharingState.paused),
        ),
      );
      await tester.ensureVisible(find.text(l10n.settingsPrivacyShare));
      await settle(tester);
      await tester.tap(find.text(l10n.settingsPrivacyShare));
      await settle(tester);
      expect(find.byType(ShareExplanationSheet), findsOne);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/privacy_share_sheet_$name.png'),
      );
    });

    testWidgets('cuenta $name', (tester) async {
      await pumpScreen(
        tester,
        home: const AccountScreen(),
        location: AppRoutes.account,
        dark: dark,
        scale: scale,
        pendingOutbox: 1,
      );
      await expectLater(
        find.byType(AccountScreen),
        matchesGoldenFile('goldens/account_$name.png'),
      );
    });
  }
}
