import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/infrastructure/location/geolocator_location_service.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Sustituye a `GeolocatorPlatform.instance`.
final class _FakeGeolocator extends GeolocatorPlatform {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  Exception? checkError;
  Exception? positionError;
  bool hang = false;
  Position position = _position();
  int positionRequests = 0;
  int requests = 0;

  /// Resultado de la solicitud (el permiso pasa a este valor).
  LocationPermission requestResult = LocationPermission.whileInUse;
  Exception? requestError;
  int locationSettingsOpened = 0;
  LocationSettings? lastSettings;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async {
    if (checkError case final error?) throw error;
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    if (requestError case final error?) throw error;
    return permission = requestResult;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    positionRequests++;
    lastSettings = locationSettings;
    // Nunca responde (plataforma colgada).
    if (hang) await Completer<void>().future;
    if (positionError case final error?) throw error;
    return position;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsOpened++;
    return true;
  }
}

/// Coordenadas sintéticas.
Position _position({
  double latitude = 4.6012,
  double longitude = -74.0712,
  double accuracy = 9.5,
  bool isMocked = false,
}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime.utc(2026, 3, 1, 10, 30),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
  isMocked: isMocked,
);

/// Respuestas simuladas del canal de permission_handler (su implementación
/// por defecto en el host).
final class _FakePermissionChannel {
  static const channel = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );

  // Valor del protocolo del canal (PermissionStatus.granted).
  static const granted = 1;

  bool rationale = false;
  final List<MethodCall> calls = [];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'shouldShowRequestPermissionRationale':
              return rationale;
            case 'requestPermissions':
              final requested = (call.arguments as List<Object?>).cast<int>();
              return {for (final p in requested) p: granted};
            case 'openAppSettings':
              return true;
          }
          return null;
        });
  }

  void uninstall() => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);

  Iterable<MethodCall> callsTo(String method) =>
      calls.where((c) => c.method == method);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GeolocatorPlatform original;
  late _FakeGeolocator geolocator;
  late _FakePermissionChannel permissions;
  const service = GeolocatorLocationService(fixTimeout: Duration(seconds: 3));

  setUp(() {
    original = GeolocatorPlatform.instance;
    geolocator = _FakeGeolocator();
    GeolocatorPlatform.instance = geolocator;
    permissions = _FakePermissionChannel()..install();
  });

  tearDown(() {
    GeolocatorPlatform.instance = original;
    permissions.uninstall();
    debugDefaultTargetPlatformOverride = null;
  });

  group('permission', () {
    for (final (from, expected) in [
      (LocationPermission.whileInUse, DeviceLocationPermission.whileInUse),
      (LocationPermission.always, DeviceLocationPermission.always),
      (
        LocationPermission.deniedForever,
        DeviceLocationPermission.deniedForever,
      ),
      (
        LocationPermission.unableToDetermine,
        DeviceLocationPermission.notDetermined,
      ),
    ]) {
      test('${from.name} → ${expected.name}', () async {
        geolocator.permission = from;
        expect(await service.permission(), expected);
      });
    }

    test('el servicio apagado tiene prioridad', () async {
      geolocator
        ..serviceEnabled = false
        ..permission = LocationPermission.whileInUse;
      expect(
        await service.permission(),
        DeviceLocationPermission.serviceDisabled,
      );
    });

    test(
      'Android: "denegado" sin justificación pendiente es "sin decidir"',
      () async {
        geolocator.permission = LocationPermission.denied;
        permissions.rationale = false;
        expect(
          await service.permission(),
          DeviceLocationPermission.notDetermined,
        );
      },
    );

    test('Android: con justificación pendiente ya se negó una vez', () async {
      geolocator.permission = LocationPermission.denied;
      permissions.rationale = true;
      expect(await service.permission(), DeviceLocationPermission.denied);
      expect(
        permissions
            .callsTo('shouldShowRequestPermissionRationale')
            .single
            .arguments,
        ph.Permission.locationWhenInUse.value,
      );
    });

    test('iOS: "denegado" solo puede ser "sin decidir"', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      geolocator.permission = LocationPermission.denied;
      permissions.rationale = true;
      expect(
        await service.permission(),
        DeviceLocationPermission.notDetermined,
      );
    });

    test('si la plataforma falla, lo prudente es "denegado"', () async {
      geolocator.checkError = PlatformException(code: 'boom');
      expect(await service.permission(), DeviceLocationPermission.denied);
    });

    test('consultar nunca pide el permiso', () async {
      geolocator.permission = LocationPermission.denied;
      await service.permission();
      expect(permissions.callsTo('requestPermissions'), isEmpty);
      expect(geolocator.requests, 0);
    });
  });

  group('requestWhileInUse', () {
    test('pide el permiso una vez y devuelve el estado concedido', () async {
      geolocator.permission = LocationPermission.denied;
      expect(
        await service.requestWhileInUse(),
        DeviceLocationPermission.whileInUse,
      );
      expect(geolocator.requests, 1);
      // La solicitud no depende de la configuración nativa de
      // permission_handler (macros del Podfile en iOS).
      expect(permissions.callsTo('requestPermissions'), isEmpty);
    });

    for (final (result, expected) in [
      (LocationPermission.denied, DeviceLocationPermission.denied),
      (
        LocationPermission.deniedForever,
        DeviceLocationPermission.deniedForever,
      ),
      (
        LocationPermission.unableToDetermine,
        DeviceLocationPermission.notDetermined,
      ),
      (LocationPermission.always, DeviceLocationPermission.always),
    ]) {
      test('resultado ${result.name} → ${expected.name}', () async {
        geolocator
          ..permission = LocationPermission.denied
          ..requestResult = result;
        expect(await service.requestWhileInUse(), expected);
      });
    }

    test('con el servicio apagado no pregunta', () async {
      geolocator.serviceEnabled = false;
      expect(
        await service.requestWhileInUse(),
        DeviceLocationPermission.serviceDisabled,
      );
      expect(geolocator.requests, 0);
    });

    test('si la solicitud falla informa el estado real', () async {
      geolocator
        ..permission = LocationPermission.deniedForever
        ..requestError = const PermissionRequestInProgressException('en curso');
      expect(
        await service.requestWhileInUse(),
        DeviceLocationPermission.deniedForever,
      );
    });
  });

  group('currentFix', () {
    test('lectura con precisión alta y tiempo límite', () async {
      geolocator.position = _position(isMocked: true);
      final fix = (await service.currentFix()).valueOrNull!;
      expect(fix.point, GeoPoint(4.6012, -74.0712));
      expect(fix.accuracyMeters, 9.5);
      expect(fix.capturedAt, DateTime.utc(2026, 3, 1, 10, 30));
      expect(fix.capturedAt.isUtc, isTrue);
      expect(fix.isMocked, isTrue);
      expect(geolocator.lastSettings?.accuracy, LocationAccuracy.high);
      expect(geolocator.lastSettings?.timeLimit, const Duration(seconds: 3));
    });

    test('sin permiso falla sin provocar el diálogo del sistema', () async {
      geolocator.permission = LocationPermission.denied;
      final result = await service.currentFix();
      expect(
        result.failureOrNull,
        const Failure(
          FailureKind.devicePermissionDenied,
          'location-permission',
        ),
      );
      expect(geolocator.positionRequests, 0);
      expect(permissions.callsTo('requestPermissions'), isEmpty);
    });

    test('con el servicio apagado', () async {
      geolocator.serviceEnabled = false;
      expect(
        (await service.currentFix()).failureOrNull?.code,
        'location-service-disabled',
      );
      expect(geolocator.positionRequests, 0);
    });

    for (final (name, error, code, kind) in [
      (
        'servicio apagado al leer',
        const LocationServiceDisabledException(),
        'location-service-disabled',
        FailureKind.devicePermissionDenied,
      ),
      (
        'permiso retirado al leer',
        const PermissionDeniedException('denied'),
        'location-permission',
        FailureKind.devicePermissionDenied,
      ),
      (
        'tiempo agotado',
        TimeoutException('sin lectura'),
        'location-unavailable',
        FailureKind.unavailable,
      ),
      (
        'error de la plataforma',
        PlatformException(code: 'position-update'),
        'location-unavailable',
        FailureKind.unavailable,
      ),
    ]) {
      test('error: $name', () async {
        geolocator.positionError = error;
        final failure = (await service.currentFix()).failureOrNull;
        expect(failure?.code, code);
        expect(failure?.kind, kind);
      });
    }

    test('lecturas imposibles se descartan', () async {
      for (final position in [
        _position(latitude: double.nan),
        _position(longitude: 200),
        _position(accuracy: -1),
        _position(accuracy: double.infinity),
      ]) {
        geolocator.position = position;
        expect(
          (await service.currentFix()).failureOrNull?.code,
          'location-unavailable',
        );
      }
    });

    test('no espera indefinidamente si la plataforma no responde', () {
      fakeAsync((async) {
        geolocator.hang = true;
        String? code;
        unawaited(
          service.currentFix().then((r) => code = r.failureOrNull?.code),
        );
        async.elapse(const Duration(seconds: 4));
        expect(code, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(code, 'location-unavailable');
      });
    });
  });

  group('openSystemSettings', () {
    test('con el servicio apagado abre los ajustes de ubicación', () async {
      geolocator.serviceEnabled = false;
      expect(await service.openSystemSettings(), isTrue);
      expect(geolocator.locationSettingsOpened, 1);
      expect(permissions.callsTo('openAppSettings'), isEmpty);
    });

    test('si no, abre los ajustes de la app (permisos)', () async {
      expect(await service.openSystemSettings(), isTrue);
      expect(permissions.callsTo('openAppSettings'), hasLength(1));
      expect(geolocator.locationSettingsOpened, 0);
    });
  });
}
