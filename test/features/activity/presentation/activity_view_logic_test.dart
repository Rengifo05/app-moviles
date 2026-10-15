import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/features/activity/domain/activity.dart';
import 'package:nexo_familia/features/activity/presentation/activity_view_logic.dart';

import 'activity_test_support.dart';

SosActivity at(String id, DateTime when) => SosActivity(
  id: id,
  familyId: familyId,
  actorUid: 'ana',
  occurredAt: when,
  alertId: id,
  resolved: false,
);

void main() {
  group('groupActivityByDay', () {
    test('separa hoy, ayer y días anteriores conservando el orden', () {
      final now = DateTime(2026, 3, 10, 9);
      final groups = groupActivityByDay([
        at('a', DateTime(2026, 3, 10, 8)),
        at('b', DateTime(2026, 3, 10, 0, 1)),
        at('c', DateTime(2026, 3, 9, 23, 59)),
        at('d', DateTime(2026, 3, 1, 12)),
        at('e', DateTime(2026, 2, 28, 12)),
      ], now);
      expect(groups.map((g) => g.kind), [
        ActivityDayKind.today,
        ActivityDayKind.yesterday,
        ActivityDayKind.earlier,
        ActivityDayKind.earlier,
      ]);
      expect(groups.map((g) => g.items.map((i) => i.id).join()), [
        'ab',
        'c',
        'd',
        'e',
      ]);
      expect(groups[2].day, DateTime(2026, 3));
    });

    test('ayer funciona al cambiar de mes', () {
      final groups = groupActivityByDay([
        at('a', DateTime(2026, 2, 28, 20)),
      ], DateTime(2026, 3, 1, 7));
      expect(groups.single.kind, ActivityDayKind.yesterday);
    });

    test('un evento con fecha futura cuenta como de hoy', () {
      final now = DateTime(2026, 3, 10, 23);
      final groups = groupActivityByDay([
        at('futuro', DateTime(2026, 3, 11, 1)),
        at('hoy', DateTime(2026, 3, 10, 22)),
      ], now);
      expect(groups.single.kind, ActivityDayKind.today);
      expect(groups.single.items, hasLength(2));
    });

    test('sin eventos no hay grupos', () {
      expect(groupActivityByDay(const [], DateTime(2026)), isEmpty);
    });
  });

  group('ActivityNames', () {
    test('integrante actual, ex integrante y sin nombre', () {
      final names = ActivityNames([
        member('ana', '  Ana  '),
        member('luis', ''),
      ]);
      expect(names.resolve('ana'), (
        kind: ActivityNameKind.member,
        name: 'Ana',
      ));
      expect(names.resolve('luis').kind, ActivityNameKind.unknown);
      expect(names.resolve('carlos').kind, ActivityNameKind.former);
    });

    test('sin lista de integrantes nunca afirma que alguien salió', () {
      expect(
        ActivityNames(null).resolve('carlos').kind,
        ActivityNameKind.unknown,
      );
    });
  });
}
