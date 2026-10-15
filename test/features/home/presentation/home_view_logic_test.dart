import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/home/presentation/home_view_logic.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';

import 'home_test_support.dart';

void main() {
  const staleAfter = Duration(minutes: 30);

  group('homeMemberStatuses', () {
    test('excluye a la persona actual y ordena por nombre', () {
      final statuses = homeMemberStatuses(
        members: sampleMembers,
        locations: sampleLocations,
        myUid: myUid,
        now: testNow,
        staleAfter: staleAfter,
      );
      expect(statuses.map((s) => s.member.uid), ['luis', 'marta', 'sofia']);
      expect(statuses.map((s) => s.state), [
        HomeLocationState.recent,
        HomeLocationState.stale,
        HomeLocationState.notSharing,
      ]);
      expect(
        statuses.first.reportedAt,
        testNow.subtract(const Duration(minutes: 3)),
      );
    });

    test('el límite de frescura es inclusivo', () {
      final statuses = homeMemberStatuses(
        members: sampleMembers,
        locations: [locationOf('luis', age: staleAfter)],
        myUid: myUid,
        now: testNow,
        staleAfter: staleAfter,
      );
      expect(statuses.first.state, HomeLocationState.recent);
    });

    test(
      'una hora muy en el futuro no es fiable: sin actualización y sin hora',
      () {
        final statuses = homeMemberStatuses(
          members: sampleMembers,
          locations: [
            MemberLocation(
              uid: 'luis',
              point: locationOf('luis', age: Duration.zero).point,
              accuracyMeters: 10,
              capturedAt: testNow.add(const Duration(hours: 5)),
              isApproximate: false,
            ),
          ],
          myUid: myUid,
          now: testNow,
          staleAfter: staleAfter,
        );
        expect(statuses.first.state, HomeLocationState.stale);
        expect(statuses.first.reportedAt, isNull);
      },
    );

    test('cargando o con error no inventa un estado', () {
      final loading = homeMemberStatuses(
        members: sampleMembers,
        locations: null,
        myUid: myUid,
        now: testNow,
        staleAfter: staleAfter,
      );
      expect(loading.map((s) => s.state).toSet(), {HomeLocationState.loading});
      final failed = homeMemberStatuses(
        members: sampleMembers,
        locations: null,
        locationsFailed: true,
        myUid: myUid,
        now: testNow,
        staleAfter: staleAfter,
      );
      expect(failed.map((s) => s.state).toSet(), {
        HomeLocationState.unavailable,
      });
    });

    test('una ubicación aproximada se marca', () {
      final statuses = homeMemberStatuses(
        members: sampleMembers,
        locations: [
          locationOf(
            'luis',
            age: const Duration(minutes: 1),
            approximate: true,
          ),
        ],
        myUid: myUid,
        now: testNow,
        staleAfter: staleAfter,
      );
      expect(statuses.first.isApproximate, isTrue);
    });
  });

  test('summarizePending separa pendientes y fallidos', () {
    final summary = summarizePending([
      pendingCheckIn('a'),
      pendingCheckIn('b', delivery: DeliveryState.failed),
      pendingCheckIn('c'),
      pendingCheckIn('d', delivery: DeliveryState.delivered),
    ]);
    expect(summary.waiting, 2);
    expect(summary.failed, 1);
    expect(summary.isEmpty, isFalse);
    expect(summarizePending(const []).isEmpty, isTrue);
  });
}
