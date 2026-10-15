import 'package:meta/meta.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';

/// Hora que se muestra para una ubicación ("hace 5 min"): la misma que usa
/// [MemberLocation.freshnessAt], es decir, la captura, salvo que el servidor
/// la recibiera antes (reloj del emisor adelantado).
DateTime reportedAtOf(MemberLocation location) {
  final received = location.receivedAt;
  return received != null && received.isBefore(location.capturedAt)
      ? received
      : location.capturedAt;
}

/// Lo que la pantalla puede afirmar de una ubicación. Nunca dice si la
/// persona está bien: solo qué tan reciente es el dato y su precisión.
@immutable
final class LocationStatus {
  const new({
    required this.freshness,
    required this.isApproximate,
    this.reportedAt,
  });

  final LocationFreshness freshness;
  final bool isApproximate;

  /// `null` si la hora no es fiable (muy en el futuro respecto a ahora): no
  /// se muestra un "hace un momento" engañoso.
  final DateTime? reportedAt;
}

LocationStatus locationStatusOf(
  MemberLocation location, {
  required DateTime now,
  required Duration staleAfter,
}) {
  final reported = reportedAtOf(location);
  final freshness = location.freshnessAt(now, staleAfter);
  final unreliable = reported.difference(now) > staleAfter;
  return LocationStatus(
    freshness: freshness,
    isApproximate: location.isApproximate,
    reportedAt: unreliable ? null : reported,
  );
}

/// Integrante con su última ubicación publicada.
@immutable
final class LocatedMember {
  const new({
    required this.member,
    required this.location,
    this.isSelf = false,
  });

  final FamilyMember member;
  final MemberLocation location;
  final bool isSelf;
}

/// Une ubicaciones e integrantes para el mapa.
@immutable
final class FamilyMapEntries {
  const new({required this.located, required this.withoutLocation});

  /// La persona actual primero; el resto, por nombre.
  final List<LocatedMember> located;

  /// Integrantes (sin contar a la persona actual) de los que no hay una
  /// ubicación publicada: no la comparten, la pausaron o aún no la enviaron.
  final List<FamilyMember> withoutLocation;
}

/// Solo se muestran ubicaciones de integrantes actuales: un documento de
/// alguien que ya no está en la familia (aún no purgado) se ignora.
FamilyMapEntries matchFamilyLocations({
  required List<MemberLocation> locations,
  required List<FamilyMember> members,
  required String? myUid,
}) {
  final byUid = {for (final l in locations) l.uid: l};
  final located = <LocatedMember>[];
  final without = <FamilyMember>[];
  for (final member in members) {
    final location = byUid[member.uid];
    final isSelf = member.uid == myUid;
    if (location != null) {
      located.add(
        LocatedMember(member: member, location: location, isSelf: isSelf),
      );
    } else if (!isSelf) {
      without.add(member);
    }
  }
  int byName(FamilyMember a, FamilyMember b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  located.sort((a, b) {
    if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
    return byName(a.member, b.member);
  });
  without.sort(byName);
  return FamilyMapEntries(located: located, withoutLocation: without);
}
