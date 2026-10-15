import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_section.dart';
import 'package:nexo_familia/design_system/components/nx_state_views.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/activity/domain/activity.dart';
import 'package:nexo_familia/features/activity/presentation/activity_providers.dart';
import 'package:nexo_familia/features/activity/presentation/activity_text.dart';
import 'package:nexo_familia/features/activity/presentation/activity_view_logic.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/common/presentation/async_view.dart';
import 'package:nexo_familia/features/common/presentation/relative_time.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/family/presentation/family_widgets.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Pestaña Actividad: historial de la familia activa de los últimos 30 días
/// (check-ins, zonas, SOS y cambios de integrantes), agrupado por día.
///
/// Lee de la copia local: sin conexión muestra lo último recibido con un
/// aviso.
class ActivityScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final familyId = ref.watch(activeFamilyIdProvider);
    final offline = ref.watch(syncStatusProvider).value == SyncStatus.offline;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navActivity)),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (offline)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NxSpace.gutter,
                  NxSpace.xs,
                  NxSpace.gutter,
                  0,
                ),
                child: NxBanner(
                  icon: Icons.cloud_off_outlined,
                  message: l10n.commonOfflineBanner,
                ),
              ),
            Expanded(
              child: familyId == null
                  ? NxMessageView(
                      icon: Icons.groups_outlined,
                      title: l10n.activityNoFamilyTitle,
                      body: l10n.activityNoFamilyBody,
                      actionLabel: l10n.activityNoFamilyAction,
                      onAction: () => context.go(AppRoutes.familySetup),
                    )
                  : _ActivityBody(familyId: familyId),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityBody extends ConsumerWidget {
  const new({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final activity = ref.watch(activityProvider(familyId));
    final members = ref.watch(familyMembersProvider(familyId));
    // Sin la lista de integrantes no se puede saber quién ya salió: se
    // espera a que cargue para no llamar "ex integrante" a nadie por error.
    // Si falla, se usan nombres genéricos.
    final value = members.hasValue || members.hasError
        ? activity
        : const AsyncLoading<List<ActivityItem>>();
    return AsyncView(
      value: value,
      onRetry: () => ref.invalidate(activityProvider(familyId)),
      builder: (items) => items.isEmpty
          ? NxMessageView(
              icon: Icons.history,
              title: l10n.activityEmptyTitle,
              body: l10n.activityEmptyBody,
            )
          // Se reconstruye periódicamente: "hace 3 min" y "Hoy" dependen
          // de la hora actual.
          : PeriodicRebuild(
              builder: (_) => _ActivityList(
                items: items,
                names: ActivityNames(members.value),
              ),
            ),
    );
  }
}

class _ActivityList extends ConsumerWidget {
  const new({required this.items, required this.names});

  final List<ActivityItem> items;
  final ActivityNames names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final now = ref.watch(clockProvider).now();
    final groups = groupActivityByDay(items, now);
    return NxPageBody(
      children: [
        for (final group in groups) ...[
          NxSectionHeader(title: activityDayLabel(l10n, group)),
          for (final item in group.items)
            _ActivityRow(
              key: ValueKey(item.id),
              item: item,
              names: names,
              now: now,
            ),
        ],
        const SizedBox(height: NxSpace.lg),
        Text(
          l10n.activityRetentionNote,
          style: context.text.bodySmall?.copyWith(color: context.nx.inkMuted),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const new({
    required this.item,
    required this.names,
    required this.now,
    super.key,
  });

  final ActivityItem item;
  final ActivityNames names;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.nx;
    final (icon, background, foreground) = switch (item) {
      SosActivity() => (
        Icons.sos,
        c.emergencyContainer,
        c.onEmergencyContainer,
      ),
      CheckInActivity(kind: CheckInKind.needHelp) => (
        Icons.support_outlined,
        c.warningContainer,
        c.onWarningContainer,
      ),
      CheckInActivity() => (
        Icons.check_circle_outline,
        c.secondaryContainer,
        c.onSecondaryContainer,
      ),
      GeofenceActivity(transition: GeofenceTransition.enter) => (
        Icons.login,
        c.surfaceAlt,
        c.ink,
      ),
      GeofenceActivity() => (Icons.logout, c.surfaceAlt, c.ink),
      MembershipActivity() => (Icons.group_outlined, c.surfaceAlt, c.ink),
    };
    final detail = activityDetail(l10n, item);
    final iconSize = nxScaledIcon(context, NxSize.iconSm);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NxSpace.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: iconSize + NxSpace.md,
                height: iconSize + NxSpace.md,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: iconSize, color: foreground),
              ),
            ),
            const SizedBox(width: NxSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activityTitle(l10n, item, names),
                    style: context.text.bodyLarge?.copyWith(
                      fontWeight: item is SosActivity ? FontWeight.w600 : null,
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: NxSpace.xxs),
                    Text(detail, style: context.text.bodyMedium),
                  ],
                  const SizedBox(height: NxSpace.xxs),
                  Text(
                    relativeTime(l10n, item.occurredAt, now),
                    style: context.text.bodySmall?.copyWith(color: c.inkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
