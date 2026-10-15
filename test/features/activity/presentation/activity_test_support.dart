import 'package:flutter/material.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/features/activity/domain/activity.dart';
import 'package:nexo_familia/features/activity/presentation/activity_providers.dart';
import 'package:nexo_familia/features/activity/presentation/activity_screen.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';
import 'package:riverpod/misc.dart';

import '../../../helpers/fakes.dart';
import '../../home/presentation/home_test_support.dart'
    show familyId, member, routedTestApp, testNow;

export '../../home/presentation/home_test_support.dart'
    show familyId, forbiddenClaims, member, myUid, settle, testNow, visibleText;

/// Integrantes actuales (Carlos ya no está: salió de la familia).
final List<FamilyMember> activityMembers = [
  member('ana', 'Ana'),
  member('luis', 'Luis'),
  member('sofia', 'Sofía'),
];

/// Historial de ejemplo (martes 10 de marzo de 2026, 14:30 UTC): hoy, ayer
/// y el domingo 8.
final List<ActivityItem> sampleActivity = [
  CheckInActivity(
    id: 'c1',
    familyId: familyId,
    actorUid: 'ana',
    occurredAt: testNow.subtract(const Duration(minutes: 3)),
    kind: CheckInKind.ok,
    message: 'Ya llegué a la casa',
  ),
  SosActivity(
    id: 's1',
    familyId: familyId,
    actorUid: 'luis',
    occurredAt: testNow.subtract(const Duration(minutes: 40)),
    alertId: 'a1',
    resolved: false,
  ),
  GeofenceActivity(
    id: 'g1',
    familyId: familyId,
    actorUid: 'sofia',
    occurredAt: testNow.subtract(const Duration(hours: 2)),
    geofenceName: 'Casa',
    transition: GeofenceTransition.enter,
  ),
  CheckInActivity(
    id: 'c2',
    familyId: familyId,
    actorUid: 'luis',
    occurredAt: testNow.subtract(const Duration(hours: 20)),
    kind: CheckInKind.needHelp,
  ),
  GeofenceActivity(
    id: 'g2',
    familyId: familyId,
    actorUid: 'sofia',
    occurredAt: testNow.subtract(const Duration(hours: 22)),
    geofenceName: 'Colegio',
    transition: GeofenceTransition.exit,
  ),
  MembershipActivity(
    id: 'm1',
    familyId: familyId,
    actorUid: 'carlos',
    occurredAt: testNow.subtract(const Duration(days: 2)),
    change: MembershipChange.left,
  ),
  MembershipActivity(
    id: 'm2',
    familyId: familyId,
    actorUid: 'sofia',
    occurredAt: testNow.subtract(const Duration(days: 2, hours: 1)),
    change: MembershipChange.joined,
  ),
];

/// Sobrescrituras de Actividad. Con [activity] `null` el historial no
/// emite (cargando); con [activityError], falla.
List<Override> activityOverrides({
  List<ActivityItem>? activity = const [],
  Object? activityError,
  List<FamilyMember>? members,
  Object? membersError,
  String? activeFamilyId = familyId,
  SyncStatus sync = SyncStatus.live,
}) => [
  clockProvider.overrideWithValue(FakeClock(testNow)),
  activeFamilyIdProvider.overrideWithValue(activeFamilyId),
  activityProvider.overrideWith(
    (ref, id) => activityError != null
        ? Stream.error(activityError)
        : activity == null
        ? const Stream.empty()
        : Stream.value(activity),
  ),
  familyMembersProvider.overrideWith(
    (ref, id) => membersError != null
        ? Stream.error(membersError)
        : Stream.value(members ?? activityMembers),
  ),
  syncStatusProvider.overrideWith((ref) => Stream.value(sync)),
];

Widget activityTestApp({
  required List<Override> overrides,
  ThemeData? theme,
  double textScale = 1,
}) => routedTestApp(
  overrides: overrides,
  start: const ActivityScreen(),
  startPath: '/activity',
  theme: theme,
  textScale: textScale,
);
