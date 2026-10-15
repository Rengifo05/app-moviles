import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/geofences/data/geofence_repository_impl.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';
import 'package:nexo_familia/features/geofences/presentation/geofence_editor_logic.dart';
import 'package:nexo_familia/features/geofences/presentation/geofence_text.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';

import '../../../helpers/fakes.dart';
import 'geofence_test_support.dart';

void main() {
  group('ZoneCenterLocator', () {
    test('con permiso, usa la lectura actual y su precisión', () async {
      final device = FakeDeviceLocationService();
      final outcome = await ZoneCenterLocator(device).locate();
      expect(outcome, isA<Located>());
      final center = (outcome as Located).center;
      expect(center.point, syntheticCenter);
      expect(center.accuracyMeters, 12);
      expect(center.isLowAccuracy, isFalse);
      expect(device.requests, 0);
    });

    test('sin permiso decidido no lo pide: primero se explica', () async {
      for (final state in [
        DeviceLocationPermission.notDetermined,
        DeviceLocationPermission.denied,
      ]) {
        final device = FakeDeviceLocationService(permissionState: state);
        expect(
          await ZoneCenterLocator(device).locate(),
          isA<LocateNeedsPermission>(),
        );
        expect(device.requests, 0);
        expect(device.fixes, 0);
      }
    });

    test('tras aceptar la explicación, pide el permiso y lee', () async {
      final device = FakeDeviceLocationService(
        permissionState: DeviceLocationPermission.notDetermined,
      );
      final outcome = await ZoneCenterLocator(device).requestAndLocate();
      expect(outcome, isA<Located>());
      expect(device.requests, 1);
    });

    test('si al pedirlo no lo concede, no vuelve a pedirlo solo', () async {
      final device = FakeDeviceLocationService(
        permissionState: DeviceLocationPermission.notDetermined,
        onRequest: DeviceLocationPermission.denied,
      );
      expect(
        await ZoneCenterLocator(device).requestAndLocate(),
        isA<LocateDeclined>(),
      );
      expect(device.requests, 1);
      expect(device.fixes, 0);
    });

    test(
      'denegado para siempre o servicio apagado: solo los ajustes',
      () async {
        expect(
          await ZoneCenterLocator(
            FakeDeviceLocationService(
              permissionState: DeviceLocationPermission.deniedForever,
            ),
          ).locate(),
          isA<LocateBlocked>(),
        );
        expect(
          await ZoneCenterLocator(
            FakeDeviceLocationService(
              permissionState: DeviceLocationPermission.serviceDisabled,
            ),
          ).locate(),
          isA<LocateServiceOff>(),
        );
      },
    );

    test('traduce los fallos de la lectura', () async {
      Future<LocateOutcome> withFix(Result<DeviceFix> fix) =>
          ZoneCenterLocator(FakeDeviceLocationService(fix: fix)).locate();

      expect(
        await withFix(
          const Err(
            Failure(
              FailureKind.devicePermissionDenied,
              'location-service-disabled',
            ),
          ),
        ),
        isA<LocateServiceOff>(),
      );
      expect(
        await withFix(
          const Err(
            Failure(FailureKind.devicePermissionDenied, 'location-permission'),
          ),
        ),
        isA<LocateBlocked>(),
      );
      expect(
        await withFix(const Err(Failure.unavailable('location-unavailable'))),
        isA<LocateUnavailable>(),
      );
    });

    test('si la lectura no llega a tiempo, no se queda esperando', () async {
      final outcome = await ZoneCenterLocator(
        // La lectura nunca llega (GPS sin señal).
        FakeDeviceLocationService()..fixGate = Completer<void>(),
        timeout: const Duration(milliseconds: 20),
      ).locate();
      expect(outcome, isA<LocateUnavailable>());
    });

    test('marca la precisión baja por encima de 100 m', () {
      expect(
        CurrentLocationCenter(
          syntheticCenter,
          accuracyMeters: 100,
        ).isLowAccuracy,
        isFalse,
      );
      expect(
        CurrentLocationCenter(
          syntheticCenter,
          accuracyMeters: 101,
        ).isLowAccuracy,
        isTrue,
      );
    });
  });

  group('GeofenceActions', () {
    late FakeGeofenceRepository repository;
    late MemoryLogSink sink;
    late GeofenceActions actions;

    setUp(() {
      repository = FakeGeofenceRepository();
      sink = MemoryLogSink();
      actions = GeofenceActions(
        repository: repository,
        logger: SafeLogger(sink: sink, clock: FakeClock(testNow)),
      );
    });

    test('sin zona original, crea con el nombre recortado', () async {
      final result = await actions.save(
        familyId: familyId,
        original: null,
        name: '  Colegio  ',
        center: syntheticCenter,
        radiusMeters: 450,
      );
      expect(result.isOk, isTrue);
      final call = repository.createCalls.single;
      expect(call.familyId, familyId);
      expect(call.name, 'Colegio');
      expect(call.center, syntheticCenter);
      expect(call.radiusMeters, 450);
      expect(repository.updateCalls, isEmpty);
    });

    test(
      'con zona original, actualiza desde su versión y conserva el autor',
      () async {
        final original = sampleZone(version: 4);
        await actions.save(
          familyId: familyId,
          original: original,
          name: ' Casa nueva ',
          center: syntheticPicked,
          radiusMeters: 600,
        );
        final sent = repository.updateCalls.single;
        expect(sent.id, original.id);
        expect(sent.version, 4);
        expect(sent.createdBy, original.createdBy);
        expect(sent.name, 'Casa nueva');
        expect(sent.center, syntheticPicked);
        expect(sent.radiusMeters, 600);
        expect(repository.createCalls, isEmpty);
      },
    );

    test('registra los fallos sin nombres ni coordenadas', () async {
      repository
        ..updateResult = const Err(Failure.conflict('geofence-conflict'))
        ..deleteResult = const Err(Failure.permissionDenied());
      await actions.save(
        familyId: familyId,
        original: sampleZone(),
        name: 'Casa de la abuela',
        center: syntheticCenter,
        radiusMeters: 200,
      );
      await actions.delete(sampleZone());

      expect(sink.entries.map((e) => e.fields), [
        {
          'feature': 'geofences',
          'operation': 'update',
          'kind': 'conflict',
          'code': 'geofence-conflict',
        },
        {
          'feature': 'geofences',
          'operation': 'delete',
          'kind': 'permissionDenied',
          'code': 'permission-denied',
        },
      ]);
      final logged = sink.entries.join('\n');
      expect(logged, isNot(contains('abuela')));
      expect(logged, isNot(contains('-40')));
    });
  });

  group('formulario', () {
    test('exige centro además de las reglas del dominio', () {
      expect(validateGeofenceDraft(name: ' ', radiusMeters: 50, center: null), [
        'geofence-name-required',
        'geofence-radius-out-of-range',
        GeofenceEditorCodes.centerRequired,
      ]);
      expect(
        validateGeofenceDraft(
          name: 'Casa',
          radiusMeters: 200,
          center: MapPickedCenter(syntheticCenter),
        ),
        isEmpty,
      );
    });

    test('radio de 100 a 2000 m en pasos de 50 m', () {
      expect(geofenceRadiusDivisions, 38);
      expect(clampGeofenceRadius(20), 100);
      expect(clampGeofenceRadius(130), 130);
      expect(clampGeofenceRadius(5000), 2000);
      expect(clampGeofenceRadius(double.nan), 200);
    });
  });

  group('textos', () {
    final l10n = esL10n;

    test('los códigos coinciden con los del repositorio', () {
      expect(GeofenceCodes.limit, GeofenceFailureCodes.limit);
      expect(GeofenceCodes.conflict, GeofenceFailureCodes.conflict);
      expect(GeofenceCodes.notFound, GeofenceFailureCodes.notFound);
      // Y con los de las reglas del dominio.
      expect(GeofenceRules.validate(name: '', radiusMeters: 1), [
        GeofenceCodes.nameRequired,
        GeofenceCodes.radiusOutOfRange,
      ]);
      expect(GeofenceRules.validate(name: 'x' * 41, radiusMeters: 200), [
        GeofenceCodes.nameTooLong,
      ]);
    });

    test('traduce los fallos al guardar', () {
      String message(Failure f) => geofenceFailureMessage(l10n, f);
      expect(
        message(const Failure.validation(GeofenceFailureCodes.limit)),
        'Esta familia ya tiene 10 zonas, el máximo por ahora. '
        'Elimina una para crear otra.',
      );
      expect(
        message(const Failure.conflict(GeofenceFailureCodes.conflict)),
        'Otro integrante cambió esta zona. Revisa la versión actual.',
      );
      expect(
        message(const Failure.notFound(GeofenceFailureCodes.notFound)),
        l10n.geofenceErrorNotFound,
      );
      // Sin confirmación del servidor: no se afirma ni que se guardó ni
      // que no.
      for (final transient in const [
        Failure.network(),
        Failure.unavailable('timeout'),
        Failure.conflict(),
      ]) {
        expect(message(transient), l10n.geofenceErrorUnconfirmed);
      }
      expect(
        message(const Failure.permissionDenied()),
        l10n.geofenceErrorNotAllowed,
      );
      expect(
        message(const Failure.validation('geofence-name-too-long')),
        'El nombre puede tener hasta 40 caracteres.',
      );
      expect(message(const Failure.unexpected()), l10n.errorUnexpected);
    });

    test('describe el centro sin coordenadas', () {
      expect(geofenceCenterText(l10n, null), 'Aún no has elegido el centro.');
      expect(
        geofenceCenterText(
          l10n,
          CurrentLocationCenter(syntheticCenter, accuracyMeters: 11.2),
        ),
        'Centro elegido · precisión ±12 m',
      );
      expect(
        geofenceCenterText(l10n, MapPickedCenter(GeoPoint(-40.5, -30.5))),
        'Centro elegido en el mapa',
      );
      expect(
        geofenceCenterText(l10n, SavedCenter(syntheticCenter)),
        'Se mantiene el centro guardado',
      );
    });
  });
}
