import 'package:meta/meta.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_view_logic.dart';

/// Lo único que Inicio afirma de la ubicación de un integrante: qué tan
/// reciente es el dato. Nunca si la persona está bien.
enum HomeLocationState {
  /// Hay una ubicación dentro del umbral de frescura.
  recent,

  /// Hay una ubicación, pero más antigua que el umbral (o con hora no
  /// fiable).
  stale,

  /// No hay ninguna ubicación publicada (no la comparte, la pausó o aún no
  /// la envió).
  notSharing,

  /// Las ubicaciones aún no se conocen.
  loading,

  /// No se pudieron leer las ubicaciones.
  unavailable,
}

@immutable
final class HomeMemberStatus {
  const new({
    required this.member,
    required this.state,
    this.reportedAt,
    this.isApproximate = false,
  });

  final FamilyMember member;
  final HomeLocationState state;

  /// Hora de la última ubicación, si es fiable.
  final DateTime? reportedAt;
  final bool isApproximate;
}

/// Integrantes **distintos de la persona actual** (su propio estado va en la
/// tarjeta de compartición), por nombre, con el estado honesto de su
/// ubicación. [locations] `null` mientras cargan; con [locationsFailed] y
/// sin datos, el estado es "no disponible".
List<HomeMemberStatus> homeMemberStatuses({
  required List<FamilyMember> members,
  required List<MemberLocation>? locations,
  required String? myUid,
  required DateTime now,
  required Duration staleAfter,
  bool locationsFailed = false,
}) {
  final byUid = locations == null
      ? null
      : {for (final l in locations) l.uid: l};
  final others =
      [
        for (final m in members)
          if (m.uid != myUid) m,
      ]..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
  return [
    for (final member in others)
      if (byUid == null)
        HomeMemberStatus(
          member: member,
          state: locationsFailed
              ? HomeLocationState.unavailable
              : HomeLocationState.loading,
        )
      else if (byUid[member.uid] case final location?)
        _statusOf(member, location, now, staleAfter)
      else
        HomeMemberStatus(member: member, state: HomeLocationState.notSharing),
  ];
}

HomeMemberStatus _statusOf(
  FamilyMember member,
  MemberLocation location,
  DateTime now,
  Duration staleAfter,
) {
  final status = locationStatusOf(location, now: now, staleAfter: staleAfter);
  return HomeMemberStatus(
    member: member,
    state: status.freshness == LocationFreshness.recent
        ? HomeLocationState.recent
        : HomeLocationState.stale,
    reportedAt: status.reportedAt,
    isApproximate: status.isApproximate,
  );
}

/// Check-ins propios aún no confirmados por el servidor.
@immutable
final class PendingCheckInSummary {
  const new({required this.waiting, required this.failed});

  /// Guardados en el teléfono, pendientes de enviar.
  final int waiting;

  /// Fallaron de forma permanente: requieren que la persona actúe.
  final int failed;

  bool get isEmpty => waiting == 0 && failed == 0;
}

PendingCheckInSummary summarizePending(List<CheckIn> pending) {
  var failed = 0;
  var waiting = 0;
  for (final checkIn in pending) {
    switch (checkIn.delivery) {
      case DeliveryState.failed:
        failed++;
      case DeliveryState.pending:
        waiting++;
      case DeliveryState.delivered:
        break;
    }
  }
  return PendingCheckInSummary(waiting: waiting, failed: failed);
}
