import 'package:meta/meta.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';

/// Si quien tiene el rol [myRole] puede quitar a [target] del grupo.
///
/// Refleja la regla de `removeMember` para no ofrecer una acción que el
/// servidor rechazaría: el owner puede quitar a cualquiera menos a sí
/// mismo; un admin, solo a quienes son `member`. Nadie se quita a sí mismo
/// (para eso está "Salir del grupo"). El servidor lo vuelve a validar.
bool canRemoveMember({
  required String myUid,
  required MemberRole myRole,
  required FamilyMember target,
}) {
  if (target.uid == myUid) return false;
  return switch (myRole) {
    MemberRole.owner => target.role != MemberRole.owner,
    MemberRole.admin => target.role == MemberRole.member,
    MemberRole.member => false,
  };
}

enum MemberLocationState {
  /// Hay una ubicación con antigüedad acotada por `staleLocationAfter`.
  recent,

  /// Hay una ubicación, pero es antigua o su hora no es fiable.
  stale,

  /// No hay ubicación publicada: no comparte, la pausó o nunca la activó.
  notSharing,
}

/// Lo que la interfaz puede afirmar sobre la ubicación de un integrante.
/// Nunca dice si la persona está bien: solo qué tan reciente es el dato.
@immutable
final class MemberLocationSummary {
  const new({required this.state, this.reportedAt, this.isApproximate = false});

  final MemberLocationState state;

  /// Hora que se muestra ("hace 5 min"). Es la misma que usa
  /// `MemberLocation.freshnessAt`: la captura, salvo que el servidor la
  /// recibiera antes (reloj del emisor adelantado).
  final DateTime? reportedAt;
  final bool isApproximate;
}

MemberLocationSummary summarizeMemberLocation(
  MemberLocation? location, {
  required DateTime now,
  required Duration staleAfter,
}) {
  if (location == null) {
    return const MemberLocationSummary(state: MemberLocationState.notSharing);
  }
  final received = location.receivedAt;
  final reportedAt = received != null && received.isBefore(location.capturedAt)
      ? received
      : location.capturedAt;
  return MemberLocationSummary(
    state: switch (location.freshnessAt(now, staleAfter)) {
      LocationFreshness.recent => MemberLocationState.recent,
      LocationFreshness.stale => MemberLocationState.stale,
    },
    reportedAt: reportedAt,
    isApproximate: location.isApproximate,
  );
}
