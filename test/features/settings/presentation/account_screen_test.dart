import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/settings/presentation/account_screen.dart';
import 'package:nexo_familia/features/settings/presentation/settings_widgets.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

import 'settings_test_harness.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async => l10n = await spanish());

  Future<SettingsFakes> pumpAccount(
    WidgetTester tester, {
    SettingsFakes? fakes,
    int? pendingOutbox,
  }) async {
    tester.view
      ..physicalSize = const Size(600, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = fakes ?? SettingsFakes();
    await tester.pumpWidget(
      settingsTestApp(
        overrides: f.overrides(pendingOutbox: pendingOutbox),
        home: const AccountScreen(),
        initialLocation: AppRoutes.account,
      ),
    );
    await settle(tester);
    return f;
  }

  Future<void> openFinalConfirmation(WidgetTester tester) async {
    await tester.tap(find.text(l10n.settingsAccountDelete));
    await settle(tester);
    await tester.tap(find.text(l10n.settingsAccountDeleteContinue));
    await settle(tester);
  }

  testWidgets('muestra el correo y el nombre de la cuenta', (tester) async {
    await pumpAccount(tester);
    expect(find.text(l10n.settingsAccountEmailLabel), findsOne);
    expect(find.text(breakableAtSeparators('ana@example.com')), findsOne);
    expect(find.text('Ana Rojas'), findsOne);
  });

  testWidgets('cerrar sesión olvida la familia activa del teléfono', (
    tester,
  ) async {
    final fakes = await pumpAccount(tester);
    await tester.tap(find.text(l10n.settingsAccountSignOut));
    await settle(tester);
    expect(fakes.auth.signOutCalls, 1);
    expect(fakes.preferences.prefs.value.activeFamilyId, isNull);
    // Las preferencias del dispositivo se conservan.
    expect(fakes.preferences.prefs.value.onboardingCompleted, isTrue);
  });

  testWidgets('descargar mis datos entrega el archivo sin registrar su '
      'contenido', (tester) async {
    final fakes = await pumpAccount(tester);
    expect(find.text(l10n.settingsAccountDataWarning), findsOne);
    await tester.scrollUntilVisible(
      find.text(l10n.settingsAccountDataExport),
      200,
    );
    await tester.tap(find.text(l10n.settingsAccountDataExport));
    await settle(tester);
    expect(fakes.exports.calls, 1);
    expect(fakes.sharer.shared.single.fileName, endsWith('.json'));
    expect(fakes.logs.entries, isEmpty);
  });

  testWidgets('si no se puede preparar el archivo lo dice y no comparte '
      'nada', (tester) async {
    final fakes = SettingsFakes();
    fakes.exports.result = const Err(networkFailure);
    await pumpAccount(tester, fakes: fakes);
    await tester.scrollUntilVisible(
      find.text(l10n.settingsAccountDataExport),
      200,
    );
    await tester.tap(find.text(l10n.settingsAccountDataExport));
    await settle(tester);
    expect(fakes.sharer.shared, isEmpty);
    expect(
      find.textContaining(l10n.settingsAccountDataFailed('').trim()),
      findsOne,
    );
    // Se registra el fallo, nunca el contenido.
    expect(fakes.logs.entries.single.fields['operation'], 'exportMyData');
  });

  testWidgets('si cerrar sesión falla lo dice', (tester) async {
    final fakes = SettingsFakes()
      ..auth.signOutResult = const Err(networkFailure);
    await pumpAccount(tester, fakes: fakes);
    await tester.tap(find.text(l10n.settingsAccountSignOut));
    await settle(tester);
    expect(
      find.text(l10n.settingsAccountSignOutFailed(l10n.errorNetwork)),
      findsOne,
    );
    expect(fakes.preferences.prefs.value.activeFamilyId, familyId);
  });

  testWidgets('con envíos pendientes avisa y confirma antes de cerrar sesión', (
    tester,
  ) async {
    final fakes = await pumpAccount(tester, pendingOutbox: 2);
    expect(find.text(l10n.settingsAccountPending(2)), findsOne);

    await tester.tap(find.text(l10n.settingsAccountSignOut));
    await settle(tester);
    expect(find.text(l10n.settingsAccountSignOutPendingTitle), findsOne);
    await tester.tap(find.text(l10n.commonCancel));
    await settle(tester);
    expect(fakes.auth.signOutCalls, 0);

    await tester.tap(find.text(l10n.settingsAccountSignOut));
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.settingsAccountSignOutAnyway),
      ),
    );
    await settle(tester);
    expect(fakes.auth.signOutCalls, 1);
  });

  testWidgets('cerrar sesión en todos los dispositivos explica qué pasa y '
      'solo actúa al confirmar', (tester) async {
    final fakes = await pumpAccount(tester);
    await tester.tap(find.text(l10n.settingsAccountEverywhere));
    await settle(tester);
    expect(find.text(l10n.settingsAccountEverywhereDevices), findsOne);
    expect(find.text(l10n.settingsAccountEverywhereAlerts), findsOne);
    expect(find.text(l10n.settingsAccountEverywhereInvites), findsOne);
    expect(fakes.auth.signOutEverywhereCalls, 0);

    await tester.tap(find.text(l10n.settingsAccountEverywhereConfirm));
    await settle(tester);
    expect(fakes.auth.signOutEverywhereCalls, 1);
    expect(fakes.preferences.prefs.value.activeFamilyId, isNull);
  });

  testWidgets('si cerrar sesión en todos falla lo dice', (tester) async {
    final fakes = SettingsFakes();
    fakes.auth.signOutEverywhereResult = const Err(Failure.network());
    await pumpAccount(tester, fakes: fakes);
    await tester.tap(find.text(l10n.settingsAccountEverywhere));
    await settle(tester);
    await tester.tap(find.text(l10n.settingsAccountEverywhereConfirm));
    await settle(tester);
    expect(
      find.textContaining('No pudimos cerrar la sesión en tus otros'),
      findsOne,
    );
  });

  testWidgets('eliminar explica las consecuencias y pide doble confirmación', (
    tester,
  ) async {
    final fakes = await pumpAccount(tester);
    await tester.tap(find.text(l10n.settingsAccountDelete));
    await settle(tester);
    expect(find.text(l10n.settingsAccountDeleteConfirmTitle), findsOne);
    expect(find.text(l10n.settingsAccountDeleteFamilies), findsOne);
    expect(find.text(l10n.settingsAccountDeleteProfile), findsOne);
    expect(find.text(l10n.settingsAccountDeleteEvents), findsOne);
    expect(find.text(l10n.settingsAccountDeleteAudit), findsOne);

    await tester.tap(find.text(l10n.settingsAccountDeleteContinue));
    await settle(tester);
    expect(find.text(l10n.settingsAccountDeleteFinalTitle), findsOne);

    // Sin escribir la palabra, no se puede confirmar.
    await tester.tap(find.text(l10n.settingsAccountDeleteFinalConfirm));
    await settle(tester);
    expect(fakes.auth.deleteCalls, 0);
    expect(find.text(l10n.settingsAccountDeleteFinalTitle), findsOne);

    await tester.enterText(find.byType(TextField), 'eliminar');
    await tester.pump();
    await tester.tap(find.text(l10n.settingsAccountDeleteFinalConfirm));
    await settle(tester);
    expect(fakes.auth.deleteCalls, 1);
    expect(fakes.preferences.prefs.value.activeFamilyId, isNull);
    expect(find.text(l10n.settingsAccountDeleted), findsOne);
  });

  testWidgets('cancelar en cualquiera de las confirmaciones no elimina', (
    tester,
  ) async {
    final fakes = await pumpAccount(tester);
    await tester.tap(find.text(l10n.settingsAccountDelete));
    await settle(tester);
    await tester.tap(find.text(l10n.commonCancel));
    await settle(tester);
    expect(find.text(l10n.settingsAccountDeleteFinalTitle), findsNothing);

    await openFinalConfirmation(tester);
    await tester.tap(find.text(l10n.commonCancel));
    await settle(tester);
    expect(fakes.auth.deleteCalls, 0);
  });

  testWidgets('si la eliminación falla lo dice con honestidad', (tester) async {
    final fakes = SettingsFakes()
      ..auth.deleteResult = const Err(networkFailure);
    await pumpAccount(tester, fakes: fakes);
    await openFinalConfirmation(tester);
    await tester.enterText(
      find.byType(TextField),
      l10n.settingsAccountDeleteWord,
    );
    await tester.pump();
    await tester.tap(find.text(l10n.settingsAccountDeleteFinalConfirm));
    await settle(tester);
    expect(fakes.auth.deleteCalls, 1);
    expect(
      find.text(l10n.settingsAccountDeleteFailed(l10n.errorNetwork)),
      findsOne,
    );
    expect(find.text(l10n.settingsAccountDeleted), findsNothing);
    expect(fakes.preferences.prefs.value.activeFamilyId, familyId);
  });
}
