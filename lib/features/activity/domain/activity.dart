import 'package:meta/meta.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';

/// Evento del historial familiar.
@immutable
sealed class ActivityItem {
  const new({
    required this.id,
    required this.familyId,
    required this.actorUid,
    required this.occurredAt,
  });

  final String id;
  final String familyId;
  final String actorUid;
  final DateTime occurredAt;
}

final class CheckInActivity extends ActivityItem {
  const new({
    required super.id,
    required super.familyId,
    required super.actorUid,
    required super.occurredAt,
    required this.kind,
    this.message,
  });

  final CheckInKind kind;
  final String? message;
}

final class GeofenceActivity extends ActivityItem {
  const new({
    required super.id,
    required super.familyId,
    required super.actorUid,
    required super.occurredAt,
    required this.geofenceName,
    required this.transition,
  });

  final String geofenceName;
  final GeofenceTransition transition;
}

final class SosActivity extends ActivityItem {
  const new({
    required super.id,
    required super.familyId,
    required super.actorUid,
    required super.occurredAt,
    required this.alertId,
    required this.resolved,
  });

  final String alertId;
  final bool resolved;
}

enum MembershipChange { joined, left, removed }

final class MembershipActivity extends ActivityItem {
  const new({
    required super.id,
    required super.familyId,
    required super.actorUid,
    required super.occurredAt,
    required this.change,
    this.targetUid,
  });

  final MembershipChange change;
  final String? targetUid;
}

abstract interface class ActivityRepository {
  /// Más recientes primero.
  Stream<List<ActivityItem>> watchActivity(String familyId, {int limit = 50});
}
