import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/settings/presentation/privacy_actions.dart';

import '../../../helpers/fakes.dart';
import 'settings_test_harness.dart';

void main() {
  late FakeLocationRepository repository;
  late FakeDeviceLocation device;
  late MemoryLogSink logs;

  PrivacyActions actions() => PrivacyActions(
    locations: repository,
    device: device,
    logger: SafeLogger(sink: logs, clock: FakeClock(testNow)),
  );

  const paused = SharingConsent(
    familyId: familyId,
    uid: myUid,
    state: SharingState.paused,
    precision: LocationPrecision.approximate,
  );

  setUp(() {
    repository = FakeLocationRepository(state: SharingState.paused);
    device = FakeDeviceLocation();
    logs = MemoryLogSink();
  });

  group('share', () {
    for (final (initial, asks) in [
      (DeviceLocationPermission.notDetermined, true),
      (DeviceLocationPermission.denied, true),
      (DeviceLocationPermission.whileInUse, false),
      (DeviceLocationPermission.always, false),
      (DeviceLocationPermission.deniedForever, false),
      (DeviceLocationPermission.serviceDisabled, false),
    ]) {
      test('con permiso ${initial.name} ${asks ? '' : 'no '}lo pide', () async {
        device = FakeDeviceLocation(current: initial);
        await actions().share(paused);
        expect(device.requests, asks ? 1 : 0);
      });
    }

    test('guarda compartir conservando la precisión elegida', () async {
      final outcome = await actions().share(paused);
      expect(outcome.applied, isTrue);
      expect(outcome.needsPermission, isFalse);
      final saved = repository.updates.single;
      expect(saved.state, SharingState.sharing);
      expect(saved.precision, LocationPrecision.approximate);
    });

    test('permiso denegado: guarda igualmente y avisa que falta', () async {
      device = FakeDeviceLocation(
        current: DeviceLocationPermission.notDetermined,
        afterRequest: DeviceLocationPermission.denied,
      );
      final outcome = await actions().share(paused);
      expect(repository.updates.single.state, SharingState.sharing);
      expect(outcome.applied, isTrue);
      expect(outcome.needsPermission, isTrue);
      expect(outcome.permission, DeviceLocationPermission.denied);
    });

    test('sin conexión no se aplica y se registra solo el código', () async {
      repository.updateResult = const Err(networkFailure);
      final outcome = await actions().share(paused);
      expect(outcome.applied, isFalse);
      expect(outcome.needsPermission, isFalse);
      final entry = logs.entries.single;
      expect(entry.event, 'settings.consent_failed');
      expect(entry.fields, {
        'feature': 'settings',
        'operation': 'share',
        'kind': 'network',
        'code': 'network',
      });
    });
  });

  test('pause y keepPaused guardan la pausa', () async {
    const sharing = SharingConsent(
      familyId: familyId,
      uid: myUid,
      state: SharingState.sharing,
      precision: LocationPrecision.exact,
    );
    final paused = await actions().pause(sharing);
    final kept = await actions().keepPaused(sharing);
    expect(paused.change, ConsentChange.pause);
    expect(kept.change, ConsentChange.keepPaused);
    expect(repository.updates.map((c) => c.state), [
      SharingState.paused,
      SharingState.paused,
    ]);
    expect(device.requests, 0);
  });

  test('pausa que falla devuelve el fallo sin aplicarse', () async {
    repository.updateResult = const Err(networkFailure);
    final outcome = await actions().pause(paused);
    expect(outcome.applied, isFalse);
    expect(outcome.result, const Err<void>(networkFailure));
  });

  test('setPrecision conserva el estado', () async {
    final outcome = await actions().setPrecision(
      paused,
      LocationPrecision.exact,
    );
    expect(outcome.change, ConsentChange.precision);
    final saved = repository.updates.single;
    expect(saved.state, SharingState.paused);
    expect(saved.precision, LocationPrecision.exact);
  });
}
