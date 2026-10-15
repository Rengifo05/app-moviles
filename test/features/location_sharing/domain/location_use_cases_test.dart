import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/domain/location_use_cases.dart';

final _fix = DeviceFix(
  point: GeoPoint(4.65432, -74.05678),
  accuracyMeters: 12,
  capturedAt: DateTime.utc(2026, 1, 1, 12),
);

final class FakeDevice implements DeviceLocationService {
  DeviceLocationPermission current = DeviceLocationPermission.whileInUse;
  Result<DeviceFix> fix = Ok(_fix);
  bool hang = false;
  int requests = 0;

  @override
  Future<DeviceLocationPermission> permission() async => current;

  @override
  Future<DeviceLocationPermission> requestWhileInUse() async {
    requests++;
    return current;
  }

  @override
  Future<Result<DeviceFix>> currentFix() =>
      hang ? Completer<Result<DeviceFix>>().future : Future.value(fix);

  @override
  Future<bool> openSystemSettings() async => true;
}

final class FakeRepository implements LocationRepository {
  final published = <MemberLocation>[];
  VoidResult result = const Ok(null);

  @override
  Future<VoidResult> publishMyLocation(
    String familyId,
    MemberLocation location,
  ) async {
    published.add(location);
    return result;
  }

  @override
  Stream<SharingConsent> watchMyConsent(String familyId) =>
      const Stream.empty();

  @override
  Stream<List<MemberLocation>> watchFamilyLocations(String familyId) =>
      const Stream.empty();

  @override
  Future<VoidResult> updateConsent(SharingConsent consent) async =>
      const Ok(null);
}

SharingConsent consent(
  SharingState state, [
  LocationPrecision precision = LocationPrecision.exact,
]) => SharingConsent(
  familyId: 'f1',
  uid: 'u1',
  state: state,
  precision: precision,
);

void main() {
  late FakeDevice device;
  late FakeRepository repo;

  setUp(() {
    device = FakeDevice();
    repo = FakeRepository();
  });

  group('ResolveShareableLocation', () {
    test('sin consentimiento activo no obtiene ubicación', () async {
      final resolve = ResolveShareableLocation(device);
      expect(await resolve(consent(SharingState.paused)), isNull);
      expect(await resolve(consent(SharingState.notConfigured)), isNull);
    });

    test('sin permiso no la obtiene y nunca pide permiso', () async {
      device.current = DeviceLocationPermission.denied;
      expect(
        await ResolveShareableLocation(device)(consent(SharingState.sharing)),
        isNull,
      );
      expect(device.requests, 0);
    });

    test('con precisión aproximada redondea y declara ≥ 1 km', () async {
      final fix = await ResolveShareableLocation(device)(
        consent(SharingState.sharing, LocationPrecision.approximate),
      );
      expect(fix!.point, _fix.point.approximate());
      expect(fix.accuracyMeters, 1000);
    });

    test('no bloquea más allá del tiempo límite', () async {
      device.hang = true;
      final fix = await ResolveShareableLocation(device)(
        consent(SharingState.sharing),
        timeout: const Duration(milliseconds: 20),
      );
      expect(fix, isNull);
    });
  });

  group('ShareMyLocationNow', () {
    Future<Result<MemberLocation>> share(SharingConsent c) =>
        ShareMyLocationNow(repo, device)(familyId: 'f1', uid: 'u1', consent: c);

    test('publica la ubicación exacta si se comparte', () async {
      final result = await share(consent(SharingState.sharing));
      expect(result.valueOrNull?.point, _fix.point);
      expect(repo.published.single.isApproximate, isFalse);
    });

    test('publica la aproximada si así se eligió', () async {
      final result = await share(
        consent(SharingState.sharing, LocationPrecision.approximate),
      );
      expect(result.valueOrNull?.isApproximate, isTrue);
      expect(repo.published.single.point, _fix.point.approximate());
    });

    test('sin compartir no publica nada', () async {
      final result = await share(consent(SharingState.paused));
      expect(result.failureOrNull?.code, 'not-sharing');
      expect(repo.published, isEmpty);
    });

    test('distingue permiso denegado y servicio apagado', () async {
      device.current = DeviceLocationPermission.deniedForever;
      expect(
        (await share(consent(SharingState.sharing))).failureOrNull,
        const Failure(
          FailureKind.devicePermissionDenied,
          'location-permission',
        ),
      );
      device.current = DeviceLocationPermission.serviceDisabled;
      expect(
        (await share(consent(SharingState.sharing))).failureOrNull?.code,
        'location-service-disabled',
      );
    });

    test('propaga el fallo del repositorio', () async {
      repo.result = const Err(Failure.network());
      expect(
        (await share(consent(SharingState.sharing))).failureOrNull?.kind,
        FailureKind.network,
      );
    });
  });
}
