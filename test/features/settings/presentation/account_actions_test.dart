import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/features/settings/presentation/account_actions.dart';

import '../../../helpers/fakes.dart';
import 'settings_test_harness.dart';

void main() {
  late FakeAuthRepository auth;
  late FakePreferencesRepository preferences;

  setUp(() {
    auth = FakeAuthRepository();
    preferences = FakePreferencesRepository();
  });

  AccountActions actions(Future<void> Function() beforeSignOut) =>
      AccountActions(
        auth: auth,
        preferences: preferences,
        logger: SafeLogger(sink: MemoryLogSink(), clock: FakeClock()),
        beforeSignOut: beforeSignOut,
      );

  test('borra el registro de avisos antes de cerrar la sesión', () async {
    int? signOutsBefore;
    final result = await actions(() async {
      signOutsBefore = auth.signOutCalls;
    }).signOut();
    expect(result.isOk, isTrue);
    // Con la sesión aún abierta: las reglas exigen ser el dueño.
    expect(signOutsBefore, 0);
    expect(auth.signOutCalls, 1);
  });

  test('si no se puede borrar el registro, igual cierra la sesión', () async {
    final result = await actions(() async => throw StateError('sin red'))
        .signOut();
    expect(result.isOk, isTrue);
    expect(auth.signOutCalls, 1);
  });

  test('nunca espera indefinidamente a la red para cerrar sesión', () {
    fakeAsync((async) {
      var done = false;
      unawaited(
        actions(() => Completer<void>().future)
            .signOut()
            .then((_) => done = true),
      );
      async.elapse(const Duration(seconds: 4));
      expect(done, isFalse);
      async.elapse(const Duration(seconds: 2));
      expect(done, isTrue);
      expect(auth.signOutCalls, 1);
    });
  });
}
