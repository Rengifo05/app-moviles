import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';

import '../../../helpers/fakes.dart';

const _staleAfter = Duration(minutes: 15);
const _us = Duration(microseconds: 1);

// Punto sintético en el océano Pacífico.
final _point = GeoPoint(-12.5, -98.25);

MemberLocation _location(DateTime capturedAt, {DateTime? receivedAt}) =>
    MemberLocation(
      uid: 'u1',
      point: _point,
      accuracyMeters: 20,
      capturedAt: capturedAt,
      receivedAt: receivedAt,
      isApproximate: false,
    );

void main() {
  group('SharingConsent', () {
    test('initial no comparte hasta que la persona decida', () {
      const consent = SharingConsent.initial(familyId: 'f1', uid: 'u1');
      expect(consent.familyId, 'f1');
      expect(consent.uid, 'u1');
      expect(consent.state, SharingState.notConfigured);
      expect(consent.precision, LocationPrecision.exact);
      expect(consent.updatedAt, isNull);
      expect(consent.isSharing, isFalse);
    });

    test('solo el estado sharing comparte', () {
      for (final state in SharingState.values) {
        final consent = const SharingConsent.initial(
          familyId: 'f1',
          uid: 'u1',
        ).copyWith(state: state);
        expect(
          consent.isSharing,
          state == SharingState.sharing,
          reason: '$state',
        );
      }
    });

    test(
      'copyWith cambia estado, precisión y fecha, nunca familia ni persona',
      () {
        final at = DateTime.utc(2026, 1, 1, 12);
        final consent = const SharingConsent.initial(familyId: 'f1', uid: 'u1')
            .copyWith(
              state: SharingState.sharing,
              precision: LocationPrecision.approximate,
              updatedAt: at,
            );
        expect(consent.familyId, 'f1');
        expect(consent.uid, 'u1');
        expect(consent.state, SharingState.sharing);
        expect(consent.precision, LocationPrecision.approximate);
        expect(consent.updatedAt, at);
      },
    );

    test('copyWith sin argumentos conserva todos los campos', () {
      final at = DateTime.utc(2026, 1, 1, 12);
      final original = SharingConsent(
        familyId: 'f1',
        uid: 'u1',
        state: SharingState.paused,
        precision: LocationPrecision.approximate,
        updatedAt: at,
      );
      final copy = original.copyWith();
      expect(copy.familyId, original.familyId);
      expect(copy.uid, original.uid);
      expect(copy.state, original.state);
      expect(copy.precision, original.precision);
      expect(copy.updatedAt, original.updatedAt);
    });

    test('copyWith cambia solo el campo indicado', () {
      final at = DateTime.utc(2026, 1, 1, 12);
      final original = SharingConsent(
        familyId: 'f1',
        uid: 'u1',
        state: SharingState.sharing,
        precision: LocationPrecision.exact,
        updatedAt: at,
      );
      final paused = original.copyWith(state: SharingState.paused);
      expect(paused.state, SharingState.paused);
      expect(paused.precision, LocationPrecision.exact);
      expect(paused.updatedAt, at);

      final approximate = original.copyWith(
        precision: LocationPrecision.approximate,
      );
      expect(approximate.state, SharingState.sharing);
      expect(approximate.precision, LocationPrecision.approximate);
    });

    test(
      'los nombres de los estados coinciden con el contrato del backend',
      () {
        expect(SharingState.values.map((s) => s.name), [
          'notConfigured',
          'sharing',
          'paused',
        ]);
        expect(LocationPrecision.values.map((p) => p.name), [
          'exact',
          'approximate',
        ]);
      },
    );
  });

  group('MemberLocation.freshnessAt', () {
    late FakeClock clock;

    setUp(() => clock = FakeClock(DateTime.utc(2026, 3, 10, 9)));

    test('recién capturada es reciente', () {
      final location = _location(clock.now());
      expect(
        location.freshnessAt(clock.now(), _staleAfter),
        LocationFreshness.recent,
      );
    });

    test(
      'el límite es inclusivo: exactamente staleAfter sigue siendo reciente',
      () {
        final now = clock.now();
        expect(
          _location(now.subtract(_staleAfter)).freshnessAt(now, _staleAfter),
          LocationFreshness.recent,
        );
        expect(
          _location(now.subtract(_staleAfter - _us))
              .freshnessAt(now, _staleAfter),
          LocationFreshness.recent,
        );
        expect(
          _location(now.subtract(_staleAfter + _us))
              .freshnessAt(now, _staleAfter),
          LocationFreshness.stale,
        );
      },
    );

    test('envejece al avanzar el reloj', () {
      final location = _location(clock.now());
      clock.advance(_staleAfter);
      expect(
        location.freshnessAt(clock.now(), _staleAfter),
        LocationFreshness.recent,
      );
      clock.advance(_us);
      expect(
        location.freshnessAt(clock.now(), _staleAfter),
        LocationFreshness.stale,
      );
      clock.advance(const Duration(days: 3));
      expect(
        location.freshnessAt(clock.now(), _staleAfter),
        LocationFreshness.stale,
      );
    });

    test('recibirla tarde no la rejuvenece: cuenta la hora de captura', () {
      final now = clock.now();
      final location = _location(
        now.subtract(const Duration(minutes: 20)),
        receivedAt: now.subtract(const Duration(minutes: 1)),
      );
      expect(location.freshnessAt(now, _staleAfter), LocationFreshness.stale);
    });

    group('con el reloj del dispositivo adelantado', () {
      test('un desfase pequeño sin sincronizar se trata como reciente', () {
        final now = clock.now();
        final location = _location(now.add(const Duration(seconds: 30)));
        expect(
          location.freshnessAt(now, _staleAfter),
          LocationFreshness.recent,
        );
      });

      test('el desfase futuro tiene el mismo límite inclusivo', () {
        final now = clock.now();
        expect(
          _location(now.add(_staleAfter)).freshnessAt(now, _staleAfter),
          LocationFreshness.recent,
        );
        expect(
          _location(now.add(_staleAfter + _us)).freshnessAt(now, _staleAfter),
          LocationFreshness.stale,
        );
      });

      test('una fecha muy futura no se muestra como reciente', () {
        // Con una hora imposible no se puede afirmar que sea reciente.
        final now = clock.now();
        final location = _location(now.add(const Duration(days: 1)));
        expect(location.freshnessAt(now, _staleAfter), LocationFreshness.stale);
        // Ni siquiera con el tiempo: sigue sin ser fiable hasta acercarse.
        clock.advance(const Duration(hours: 12));
        expect(
          location.freshnessAt(clock.now(), _staleAfter),
          LocationFreshness.stale,
        );
      });

      test('manda la hora del servidor si la captura es posterior', () {
        final now = clock.now();
        // El emisor adelantado dice "hace 1 min", pero el servidor la
        // recibió hace 40 min: no puede ser más nueva que eso.
        final location = _location(
          now.subtract(const Duration(minutes: 1)),
          receivedAt: now.subtract(const Duration(minutes: 40)),
        );
        expect(location.freshnessAt(now, _staleAfter), LocationFreshness.stale);

        final future = _location(
          now.add(const Duration(hours: 5)),
          receivedAt: now.subtract(const Duration(minutes: 2)),
        );
        expect(future.freshnessAt(now, _staleAfter), LocationFreshness.recent);
        clock.advance(const Duration(minutes: 13));
        expect(
          future.freshnessAt(clock.now(), _staleAfter),
          LocationFreshness.recent,
        );
        clock.advance(_us);
        expect(
          future.freshnessAt(clock.now(), _staleAfter),
          LocationFreshness.stale,
        );
      });
    });

    test(
      'con el reloj local atrasado más que staleAfter no afirma frescura',
      () {
        // Este dispositivo va 1 h por detrás del servidor y del emisor.
        final realNow = clock.now();
        final localNow = realNow.subtract(const Duration(hours: 1));
        final location = _location(realNow, receivedAt: realNow);
        expect(
          location.freshnessAt(localNow, _staleAfter),
          LocationFreshness.stale,
        );
      },
    );

    test('compara instantes aunque las fechas no estén en UTC', () {
      final now = clock.now();
      final capturedLocal = now.subtract(const Duration(minutes: 5)).toLocal();
      expect(
        _location(capturedLocal).freshnessAt(now, _staleAfter),
        LocationFreshness.recent,
      );
      final oldLocal = now.subtract(const Duration(minutes: 16)).toLocal();
      expect(
        _location(oldLocal).freshnessAt(now.toLocal(), _staleAfter),
        LocationFreshness.stale,
      );
    });
  });

  group('DeviceLocationPermission.isGranted', () {
    test('solo "mientras se usa" y "siempre" conceden acceso', () {
      final granted = DeviceLocationPermission.values
          .where((p) => p.isGranted)
          .toSet();
      expect(granted, {
        DeviceLocationPermission.whileInUse,
        DeviceLocationPermission.always,
      });
    });

    test('denegado, sin pedir o con el servicio apagado no conceden', () {
      for (final permission in [
        DeviceLocationPermission.notDetermined,
        DeviceLocationPermission.denied,
        DeviceLocationPermission.deniedForever,
        DeviceLocationPermission.serviceDisabled,
      ]) {
        expect(permission.isGranted, isFalse, reason: '$permission');
      }
    });
  });

  group('DeviceFix', () {
    test('no se considera simulada salvo que el sistema lo indique', () {
      final at = DateTime.utc(2026);
      expect(
        DeviceFix(point: _point, accuracyMeters: 10, capturedAt: at).isMocked,
        isFalse,
      );
      expect(
        DeviceFix(
          point: _point,
          accuracyMeters: 10,
          capturedAt: at,
          isMocked: true,
        ).isMocked,
        isTrue,
      );
    });
  });
}
