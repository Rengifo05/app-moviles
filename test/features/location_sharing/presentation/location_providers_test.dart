import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';

import 'location_test_support.dart';

void main() {
  late FakeLocationRepository repository;
  late FakeDeviceLocation device;
  late ProviderContainer container;

  setUp(() {
    repository = FakeLocationRepository();
    device = FakeDeviceLocation();
    container = ProviderContainer(
      overrides: [
        locationRepositoryProvider.overrideWithValue(repository),
        deviceLocationServiceProvider.overrideWithValue(device),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
  });

  test('shareMyLocationNowProvider usa el repositorio y el dispositivo '
      'inyectados', () async {
    final result = await container.read(shareMyLocationNowProvider)(
      familyId: familyId,
      uid: myUid,
      consent: repository.consent.value,
    );
    expect(result.isOk, isTrue);
    expect(repository.published.single.uid, myUid);
  });

  test('resolveShareableLocationProvider respeta el consentimiento', () async {
    final resolve = container.read(resolveShareableLocationProvider);
    expect(await resolve(repository.consent.value), isNotNull);
    expect(
      await resolve(
        repository.consent.value.copyWith(state: SharingState.paused),
      ),
      isNull,
    );
    // Nunca pide permisos.
    device.current = DeviceLocationPermission.notDetermined;
    expect(await resolve(repository.consent.value), isNull);
    expect(device.requests, 0);
  });

  test('deviceLocationPermissionProvider se relee al invalidarlo', () async {
    final sub = container.listen(deviceLocationPermissionProvider, (_, _) {});
    addTearDown(sub.close);
    expect(
      await container.read(deviceLocationPermissionProvider.future),
      DeviceLocationPermission.whileInUse,
    );
    device.current = DeviceLocationPermission.deniedForever;
    container.invalidate(deviceLocationPermissionProvider);
    expect(
      await container.read(deviceLocationPermissionProvider.future),
      DeviceLocationPermission.deniedForever,
    );
  });
}
