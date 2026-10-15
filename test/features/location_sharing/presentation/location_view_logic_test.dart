import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_text.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_view_logic.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

import 'location_test_support.dart';

const _staleAfter = Duration(minutes: 30);

MemberLocation _at(
  DateTime captured, {
  DateTime? received,
  bool approximate = false,
}) => MemberLocation(
  uid: 'luis',
  point: GeoPoint(4.6, -74.1),
  accuracyMeters: 10,
  capturedAt: captured,
  receivedAt: received,
  isApproximate: approximate,
);

void main() {
  group('locationStatusOf', () {
    test('usa la recepción si el reloj del emisor iba adelantado', () {
      final status = locationStatusOf(
        _at(
          testNow.add(const Duration(hours: 2)),
          received: testNow.subtract(const Duration(hours: 1)),
        ),
        now: testNow,
        staleAfter: _staleAfter,
      );
      expect(status.freshness, LocationFreshness.stale);
      expect(status.reportedAt, testNow.subtract(const Duration(hours: 1)));
    });

    test('una hora muy en el futuro no se muestra como reciente', () {
      final status = locationStatusOf(
        _at(testNow.add(const Duration(days: 2))),
        now: testNow,
        staleAfter: _staleAfter,
      );
      expect(status.freshness, LocationFreshness.stale);
      expect(status.reportedAt, isNull);
    });

    test('un pequeño desfase hacia el futuro cuenta como reciente', () {
      final status = locationStatusOf(
        _at(testNow.add(const Duration(minutes: 2))),
        now: testNow,
        staleAfter: _staleAfter,
      );
      expect(status.freshness, LocationFreshness.recent);
      expect(status.reportedAt, isNotNull);
    });
  });

  group('matchFamilyLocations', () {
    test('yo primero, el resto por nombre; sin ubicación aparte', () {
      final entries = matchFamilyLocations(
        locations: [
          locationOf('sofia', const Duration(minutes: 1)),
          locationOf(myUid, const Duration(minutes: 1)),
          locationOf('luis', const Duration(minutes: 1)),
          locationOf('ex-integrante', const Duration(minutes: 1)),
        ],
        members: [
          ...sampleMembers,
          member('pedro', 'Pedro'),
          member('beto', 'beto'),
        ],
        myUid: myUid,
      );
      expect(entries.located.map((e) => e.member.uid), [
        myUid,
        'luis',
        'sofia',
      ]);
      expect(entries.located.first.isSelf, isTrue);
      // Sin la persona actual, ordenados sin importar mayúsculas.
      expect(entries.withoutLocation.map((m) => m.uid), [
        'beto',
        'marta',
        'pedro',
      ]);
    });
  });

  group('textos', () {
    late AppLocalizations l10n;

    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('es'));
    });

    String text(MemberLocation location) => locationStatusText(
      l10n,
      locationStatusOf(location, now: testNow, staleAfter: _staleAfter),
      now: testNow,
    );

    test('estados de una ubicación', () {
      expect(
        text(_at(testNow.subtract(const Duration(minutes: 3)))),
        'Ubicación actualizada hace 3\u00A0min',
      );
      expect(
        text(
          _at(testNow.subtract(const Duration(minutes: 3)), approximate: true),
        ),
        'Ubicación aproximada (±1\u00A0km) actualizada hace 3\u00A0min',
      );
      expect(
        text(_at(testNow.subtract(const Duration(hours: 3)))),
        'Sin actualización reciente. Última ubicación hace 3\u00A0h',
      );
      expect(
        text(_at(testNow.subtract(const Duration(days: 2)), approximate: true)),
        'Sin actualización reciente. Última ubicación aproximada '
        '(±1\u00A0km) hace 2\u00A0días',
      );
      expect(
        text(_at(testNow.add(const Duration(days: 2)))),
        'Sin actualización reciente',
      );
    });

    test('descripción completa del marcador', () {
      expect(
        locationMarkerDescription(
          l10n,
          name: 'Ana',
          status: locationStatusOf(
            _at(testNow.subtract(const Duration(minutes: 3))),
            now: testNow,
            staleAfter: _staleAfter,
          ),
          now: testNow,
        ),
        'Ana. Ubicación actualizada hace 3\u00A0min',
      );
    });

    test('nombre de respaldo y "Tú"', () {
      expect(
        locationMemberName(l10n, member('x', '   '), isSelf: false),
        'Integrante',
      );
      expect(
        locationMemberName(l10n, member(myUid, 'Ana'), isSelf: true),
        'Tú',
      );
    });

    test('motivos de fallo específicos y genéricos', () {
      expect(
        locationFailureReason(
          l10n,
          const Failure(
            FailureKind.devicePermissionDenied,
            'location-permission',
          ),
        ),
        'La app no tiene permiso para usar tu ubicación.',
      );
      expect(
        locationFailureReason(l10n, const Failure.validation('not-sharing')),
        'Activa la compartición de ubicación en Privacidad para enviarla.',
      );
      expect(
        locationFailureReason(l10n, const Failure.network()),
        'No hay conexión. Revisa tu red e inténtalo de nuevo.',
      );
      expect(
        locationFailureNeedsSettings(
          const Failure(
            FailureKind.devicePermissionDenied,
            'location-service-disabled',
          ),
        ),
        isTrue,
      );
      expect(locationFailureNeedsSettings(const Failure.network()), isFalse);
    });
  });
}
