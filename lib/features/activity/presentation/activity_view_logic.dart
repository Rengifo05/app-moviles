import 'package:meta/meta.dart';
import 'package:nexo_familia/features/activity/domain/activity.dart';
import 'package:nexo_familia/features/family/domain/family.dart';

enum ActivityDayKind { today, yesterday, earlier }

/// Eventos de un mismo día (hora local del teléfono).
@immutable
final class ActivityDayGroup {
  const new({required this.day, required this.kind, required this.items});

  /// Medianoche local del día.
  final DateTime day;
  final ActivityDayKind kind;

  /// En el orden recibido (más recientes primero).
  final List<ActivityItem> items;
}

/// Agrupa el historial por día local, conservando el orden. Un evento con
/// fecha futura (reloj del emisor adelantado) cuenta como de hoy.
List<ActivityDayGroup> groupActivityByDay(
  List<ActivityItem> items,
  DateTime now,
) {
  final today = _dayOf(now);
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  final groups = <ActivityDayGroup>[];
  for (final item in items) {
    var day = _dayOf(item.occurredAt);
    if (day.isAfter(today)) day = today;
    final last = groups.lastOrNull;
    if (last != null && last.day == day) {
      last.items.add(item);
      continue;
    }
    groups.add(
      ActivityDayGroup(
        day: day,
        kind: day == today
            ? ActivityDayKind.today
            : day == yesterday
            ? ActivityDayKind.yesterday
            : ActivityDayKind.earlier,
        items: [item],
      ),
    );
  }
  return groups;
}

DateTime _dayOf(DateTime moment) {
  final local = moment.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Cómo se nombra a una persona en el historial.
enum ActivityNameKind {
  /// Integrante actual con nombre.
  member,

  /// Ya no está en la familia (la lista de integrantes se pudo leer).
  former,

  /// No se sabe: la lista de integrantes no está disponible o la persona no
  /// tiene nombre. Nunca se afirma que salió de la familia.
  unknown,
}

/// Resuelve nombres a partir de los integrantes **actuales**: el historial
/// no guarda nombres (privacidad por diseño), así que quien ya salió de la
/// familia aparece como "Un ex integrante".
@immutable
final class ActivityNames {
  /// [members] `null` si aún no se conocen (o no se pudieron leer).
  new(List<FamilyMember>? members)
    : _byUid = members == null
          ? null
          : {for (final m in members) m.uid: m.displayName.trim()};

  final Map<String, String>? _byUid;

  ({ActivityNameKind kind, String? name}) resolve(String uid) {
    final byUid = _byUid;
    if (byUid == null) return (kind: ActivityNameKind.unknown, name: null);
    final name = byUid[uid];
    if (name == null) return (kind: ActivityNameKind.former, name: null);
    if (name.isEmpty) return (kind: ActivityNameKind.unknown, name: null);
    return (kind: ActivityNameKind.member, name: name);
  }
}
