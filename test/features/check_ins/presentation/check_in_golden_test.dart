@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/check_ins/presentation/check_in_widgets.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';

import '../../../helpers/fonts.dart';
import 'check_in_test_support.dart';

/// Capturas de la pantalla de check-in para revisión visual, en claro al
/// 100 % y en oscuro al 200 %. Para regenerarlas:
/// `flutter test --update-goldens test/features/check_ins/presentation/check_in_golden_test.dart`.
typedef _Case = ({
  String name,
  CheckInTestEnv Function() env,
  Future<void> Function(WidgetTester tester, CheckInTestEnv env)? act,
});

Finder _option(CheckInKind kind) =>
    find.byWidgetPredicate((w) => w is CheckInOptionTile && w.kind == kind);

Future<void> _choose(WidgetTester tester, CheckInKind kind) =>
    scrollAndTap(tester, _option(kind));

/// Arrastra hasta que la lista deja de moverse (su largo se conoce a medida
/// que se construye, así que un solo arrastre puede quedarse corto).
Future<void> _scrollFully(WidgetTester tester, double dy) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 10; i++) {
    final position = tester.state<ScrollableState>(scrollable).position;
    final before = position.pixels;
    await tester.drag(scrollable, Offset(0, dy));
    await pumpFrames(tester);
    if (position.pixels == before) break;
  }
}

Future<void> _scrollToEnd(WidgetTester tester) => _scrollFully(tester, -2000);

Future<void> _scrollToTop(WidgetTester tester) => _scrollFully(tester, 2000);

/// Elige "Necesito ayuda", escribe un mensaje y envía (sin ubicación).
Future<void> _sendHelp(WidgetTester tester) async {
  await _choose(tester, CheckInKind.needHelp);
  await tester.enterText(
    find.byType(TextField),
    'Se me descargó el celular, ¿alguien me recoge?',
  );
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await scrollAndTap(tester, find.text(esL10n.checkInSend));
}

/// Pendientes de otros envíos: uno en espera y otro rechazado.
FakeCheckInRepository _withOlder() => FakeCheckInRepository([
  sampleCheckIn(id: 'old-1', message: 'Salí del trabajo'),
  sampleCheckIn(
    id: 'old-2',
    kind: CheckInKind.needHelp,
    delivery: DeliveryState.failed,
    age: const Duration(minutes: 3),
  ),
]);

final List<_Case> _cases = [
  (name: 'inicial', env: CheckInTestEnv.new, act: null),
  (
    name: 'formulario_ayuda',
    env: () => CheckInTestEnv(precision: LocationPrecision.approximate),
    act: (tester, env) async {
      await _choose(tester, CheckInKind.needHelp);
      await tester.enterText(find.byType(TextField), 'Estoy en la portería.');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await scrollAndTap(tester, find.byType(Switch));
      await _scrollToEnd(tester);
    },
  ),
  (
    name: 'sin_conexion',
    env: () => CheckInTestEnv(
      syncStatus: SyncStatus.offline,
      sharing: SharingState.paused,
      repository: _withOlder(),
    ),
    act: (tester, env) async {
      await _choose(tester, CheckInKind.ok);
      await _scrollToTop(tester);
    },
  ),
  (
    name: 'pendientes',
    env: () => CheckInTestEnv(
      syncStatus: SyncStatus.offline,
      sharing: SharingState.paused,
      repository: _withOlder(),
    ),
    act: (tester, env) => _scrollToEnd(tester),
  ),
  (
    name: 'enviando',
    env: CheckInTestEnv.new,
    act: (tester, env) => _sendHelp(tester),
  ),
  (
    name: 'guardado',
    env: () => CheckInTestEnv(
      syncStatus: SyncStatus.offline,
      repository: _withOlder(),
    ),
    act: (tester, env) async {
      await _sendHelp(tester);
      await _scrollToTop(tester);
    },
  ),
  (
    name: 'enviado',
    env: CheckInTestEnv.new,
    act: (tester, env) async {
      await _choose(tester, CheckInKind.ok);
      await scrollAndTap(tester, find.byType(Switch));
      await scrollAndTap(tester, find.text(esL10n.checkInSend));
      env.repository.deliver('id-1');
      await pumpFrames(tester);
      await _scrollToTop(tester);
    },
  ),
  (
    name: 'rechazado',
    env: CheckInTestEnv.new,
    act: (tester, env) async {
      await _sendHelp(tester);
      env.repository.fail('id-1');
      await pumpFrames(tester);
      await _scrollToTop(tester);
    },
  ),
  (
    name: 'sin_familia',
    env: () => CheckInTestEnv(activeFamilyId: null),
    act: null,
  ),
];

void main() {
  setUpAll(loadAppFonts);

  for (final c in _cases) {
    for (final (theme, scale) in [('claro', 1.0), ('oscuro', 2.0)]) {
      testWidgets('${c.name} $theme al ${(scale * 100).round()} %', (
        tester,
      ) async {
        final env = c.env();
        await pumpCheckInScreen(
          tester,
          env,
          theme: theme == 'claro' ? NxTheme.light() : NxTheme.dark(),
          textScale: scale,
        );
        if (c.act case final act?) await act(tester, env);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${c.name}_${theme}_x${scale.round()}.png'),
        );
      });
    }
  }
}
