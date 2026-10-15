import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/infrastructure/location/demo_location_service.dart';

import '../../helpers/fakes.dart';

void main() {
  test(
    'por defecto el permiso está sin decidir y se concede al pedirlo',
    () async {
      final demo = DemoLocationService(clock: FakeClock());
      expect(await demo.permission(), DeviceLocationPermission.notDetermined);
      expect(
        (await demo.currentFix()).failureOrNull?.code,
        'location-permission',
      );

      expect(
        await demo.requestWhileInUse(),
        DeviceLocationPermission.whileInUse,
      );
      expect(await demo.permission(), DeviceLocationPermission.whileInUse);
      expect(demo.requests, 1);
    },
  );

  test('el resultado de la solicitud es configurable', () async {
    final demo = DemoLocationService(
      onRequest: DeviceLocationPermission.deniedForever,
    );
    expect(
      await demo.requestWhileInUse(),
      DeviceLocationPermission.deniedForever,
    );
    // Como el sistema: tras una negación permanente ya no pregunta.
    demo.simulatedPermission = DeviceLocationPermission.deniedForever;
    expect(
      await demo.requestWhileInUse(),
      DeviceLocationPermission.deniedForever,
    );
  });

  test('con el servicio apagado lo informa con su código', () async {
    final demo = DemoLocationService(
      simulatedPermission: DeviceLocationPermission.serviceDisabled,
    );
    expect(
      (await demo.currentFix()).failureOrNull,
      const Failure(
        FailureKind.devicePermissionDenied,
        'location-service-disabled',
      ),
    );
  });

  test(
    'las lecturas son sintéticas, cercanas al origen y deterministas',
    () async {
      final clock = FakeClock();
      final origin = GeoPoint(-40, -30);
      DemoLocationService demo() => DemoLocationService(
        clock: clock,
        origin: origin,
        simulatedPermission: DeviceLocationPermission.whileInUse,
      );
      final first = demo();
      final second = demo();

      final points = <GeoPoint>[];
      for (var i = 0; i < 8; i++) {
        final fix = (await first.currentFix()).valueOrNull!;
        expect(fix.point.distanceTo(origin), lessThan(50));
        expect(fix.capturedAt, clock.now());
        expect(fix.isMocked, isTrue);
        expect(fix.accuracyMeters, inInclusiveRange(15, 25));
        expect((await second.currentFix()).valueOrNull!.point, fix.point);
        points.add(fix.point);
      }
      // Hay variación entre lecturas consecutivas y el recorrido se repite.
      expect(points.toSet().length, greaterThan(1));
      expect((await first.currentFix()).valueOrNull!.point, points.first);
    },
  );

  test('no abre ajustes reales: lo informa con honestidad', () async {
    final demo = DemoLocationService();
    expect(await demo.openSystemSettings(), isFalse);
    expect(demo.settingsOpened, 1);
  });
}
