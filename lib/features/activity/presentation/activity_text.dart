import 'package:nexo_familia/features/activity/domain/activity.dart';
import 'package:nexo_familia/features/activity/presentation/activity_view_logic.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Nombre al inicio de la frase ("Ana", "Un ex integrante").
String activitySubject(
  AppLocalizations l10n,
  ActivityNames names,
  String uid,
) => switch (names.resolve(uid)) {
  (kind: ActivityNameKind.member, :final name?) => name,
  (kind: ActivityNameKind.former, name: _) => l10n.activityFormerMember,
  _ => l10n.activityUnknownMember,
};

/// Nombre como complemento ("quitó a un ex integrante").
String activityObject(AppLocalizations l10n, ActivityNames names, String uid) =>
    switch (names.resolve(uid)) {
      (kind: ActivityNameKind.member, :final name?) => name,
      (kind: ActivityNameKind.former, name: _) =>
        l10n.activityFormerMemberObject,
      _ => l10n.activityUnknownMemberObject,
    };

/// Frase principal de un evento del historial. Solo describe lo que el
/// evento registra: nunca dice que alguien esté bien o a salvo, ni que un
/// aviso se haya recibido.
String activityTitle(
  AppLocalizations l10n,
  ActivityItem item,
  ActivityNames names,
) {
  final actor = activitySubject(l10n, names, item.actorUid);
  return switch (item) {
    CheckInActivity(kind: CheckInKind.ok) => l10n.activityCheckInOk(actor),
    CheckInActivity(kind: CheckInKind.needHelp) => l10n.activityCheckInNeedHelp(
      actor,
    ),
    SosActivity() => l10n.activitySos(actor),
    GeofenceActivity(
      transition: GeofenceTransition.enter,
      :final geofenceName,
    ) =>
      l10n.activityGeofenceEnter(actor, geofenceName),
    GeofenceActivity(
      transition: GeofenceTransition.exit,
      :final geofenceName,
    ) =>
      l10n.activityGeofenceExit(actor, geofenceName),
    MembershipActivity(change: MembershipChange.joined) => l10n.activityJoined(
      actor,
    ),
    MembershipActivity(change: MembershipChange.left) => l10n.activityLeft(
      actor,
    ),
    MembershipActivity(change: MembershipChange.removed, :final targetUid) =>
      targetUid == null
          ? l10n.activityRemovedNoTarget(actor)
          : l10n.activityRemoved(actor, activityObject(l10n, names, targetUid)),
  };
}

/// Texto secundario (el mensaje de un check-in), si lo hay.
String? activityDetail(AppLocalizations l10n, ActivityItem item) =>
    switch (item) {
      CheckInActivity(:final message?) => l10n.activityCheckInMessage(message),
      _ => null,
    };

/// "Hoy", "Ayer" o la fecha ("Martes, 10 de marzo").
String activityDayLabel(AppLocalizations l10n, ActivityDayGroup group) =>
    switch (group.kind) {
      ActivityDayKind.today => l10n.activityToday,
      ActivityDayKind.yesterday => l10n.activityYesterday,
      ActivityDayKind.earlier => _capitalized(l10n.activityDay(group.day)),
    };

String _capitalized(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
