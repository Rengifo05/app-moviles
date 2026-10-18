import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/design_system/components/nx_avatar.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/components/nx_section.dart';
import 'package:nexo_familia/design_system/components/nx_state_views.dart';
import 'package:nexo_familia/design_system/components/nx_status_pill.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/check_ins/presentation/check_in_providers.dart';
import 'package:nexo_familia/features/common/presentation/failure_text.dart';
import 'package:nexo_familia/features/common/presentation/relative_time.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/emergency/presentation/active_alerts_banner.dart';
import 'package:nexo_familia/features/emergency/presentation/emergency_providers.dart';
import 'package:nexo_familia/features/emergency/presentation/sos_view_logic.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/family/presentation/family_widgets.dart';
import 'package:nexo_familia/features/home/presentation/home_view_logic.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
import 'package:nexo_familia/features/location_sharing/presentation/sharing_status_card.dart';
import 'package:nexo_familia/features/notifications/presentation/push_prompt_card.dart';
import 'package:nexo_familia/features/service_status/presentation/service_notice_banner.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Pestaña Inicio: alertas SOS activas de otros integrantes (arriba), saludo,
/// estado de mi compartición, acciones rápidas (check-in y SOS) y la lista
/// de integrantes con el estado **honesto** de su ubicación: solo qué tan
/// reciente es el dato, nunca si alguien está bien.
class HomeScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final familyId = ref.watch(activeFamilyIdProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navHome)),
      body: SafeArea(
        top: false,
        child: familyId == null
            ? NxMessageView(
                icon: Icons.groups_outlined,
                title: l10n.homeNoFamilyTitle,
                body: l10n.homeNoFamilyBody,
                actionLabel: l10n.homeNoFamilyAction,
                onAction: () => context.go(AppRoutes.familySetup),
              )
            : _HomeBody(familyId: familyId),
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const new({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final offline = ref.watch(syncStatusProvider).value == SyncStatus.offline;
    final pending = summarizePending(
      ref.watch(pendingCheckInsProvider(familyId)).value ?? const [],
    );
    return NxPageBody(
      children: [
        if (offline) ...[
          NxBanner(
            icon: Icons.cloud_off_outlined,
            message: l10n.commonOfflineBanner,
          ),
          const SizedBox(height: NxSpace.sm),
        ],
        const _Alerts(),
        _Greeting(familyId: familyId),
        if (pending.failed > 0) ...[
          NxBanner(
            icon: Icons.error_outline,
            message: l10n.homeFailedCheckIns(pending.failed),
            actionLabel: l10n.homePendingCheckInsAction,
            onAction: () => unawaited(context.push(AppRoutes.checkIn)),
          ),
          const SizedBox(height: NxSpace.sm),
        ],
        if (pending.waiting > 0) ...[
          NxBanner(
            icon: Icons.schedule_send_outlined,
            tone: NxTone.info,
            message: l10n.homePendingCheckIns(pending.waiting),
            actionLabel: l10n.homePendingCheckInsAction,
            onAction: () => unawaited(context.push(AppRoutes.checkIn)),
          ),
          const SizedBox(height: NxSpace.sm),
        ],
        const ServiceNoticeBanner(),
        const PushPromptCard(),
        const SharingStatusCard(),
        NxSectionHeader(title: l10n.homeQuickActionsTitle),
        const _QuickActions(),
        NxSectionHeader(title: l10n.homeMembersTitle),
        _Members(familyId: familyId),
      ],
    );
  }
}

/// Aviso de alertas SOS activas de otros integrantes (componente de la
/// funcionalidad de emergencia, con "Lo vi"). Ocupa espacio solo si hay
/// alguna: usa el mismo criterio que el aviso.
class _Alerts extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familyId = ref.watch(activeFamilyIdProvider);
    final uid = ref.watch(currentUserProvider).value?.uid;
    final visible =
        familyId != null &&
        othersActiveAlerts(
          ref.watch(emergencyAlertsProvider(familyId)).value ?? const [],
          uid,
        ).isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: visible ? NxSpace.md : 0),
      child: const ActiveAlertsBanner(),
    );
  }
}

class _Greeting extends ConsumerWidget {
  const new({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider).value;
    final family = ref.watch(activeFamilyProvider).value;
    final memberName = ref
        .watch(familyMembersProvider(familyId))
        .value
        ?.where((m) => m.uid == user?.uid)
        .firstOrNull
        ?.displayName;
    final name = [
      user?.displayName,
      memberName,
    ].map((n) => n?.trim() ?? '').where((n) => n.isNotEmpty).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: NxSpace.xs, bottom: NxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              name == null ? l10n.homeGreetingNoName : l10n.homeGreeting(name),
              style: context.text.headlineSmall,
            ),
          ),
          if (family != null) ...[
            const SizedBox(height: NxSpace.xxs),
            Text(
              l10n.homeFamilyName(family.name),
              style: context.text.bodyMedium?.copyWith(
                color: context.nx.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Check-in y SOS. El botón SOS solo **abre** la pantalla de emergencia:
/// allí está la confirmación deliberada (mantener pulsado + cuenta atrás
/// cancelable). Así hay un único lugar donde se crea una alerta y un toque
/// accidental en Inicio nunca envía nada.
class _QuickActions extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final checkIn = NxButton(
      label: l10n.homeCheckInAction,
      icon: Icons.check_circle_outline,
      onPressed: () => unawaited(context.push(AppRoutes.checkIn)),
    );
    final sos = NxButton(
      label: l10n.homeSosAction,
      icon: Icons.emergency_outlined,
      variant: NxButtonVariant.destructive,
      onPressed: () => unawaited(context.push(AppRoutes.sos)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
                constraints.maxWidth < 340;
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  checkIn,
                  const SizedBox(height: NxSpace.sm),
                  sos,
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: checkIn),
                  const SizedBox(width: NxSpace.sm),
                  Expanded(child: sos),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: NxSpace.xs),
        Text(
          l10n.homeSosHint,
          style: context.text.bodySmall?.copyWith(color: context.nx.inkMuted),
        ),
      ],
    );
  }
}

class _Members extends ConsumerWidget {
  const new({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final members = ref.watch(familyMembersProvider(familyId));
    // Va dentro de una lista desplazable: estados compactos en lugar de
    // vistas a pantalla completa.
    if (!members.hasValue) {
      if (members.error case final error?) {
        return NxBanner(
          icon: Icons.error_outline,
          tone: NxTone.neutral,
          message: failureMessage(
            l10n,
            error is Failure
                ? error
                : Failure.unexpected('home-members', error),
          ),
          actionLabel: l10n.commonRetry,
          onAction: () => ref.invalidate(familyMembersProvider(familyId)),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: NxSpace.md),
        child: NxLoadingView(label: l10n.commonLoading),
      );
    }
    final list = members.requireValue;
    // Se reconstruye periódicamente: "hace 3 min" y la frescura dependen
    // de la hora actual.
    return PeriodicRebuild(
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final locations = ref.watch(familyLocationsProvider(familyId));
          final staleAfter = ref.watch(appConfigProvider).staleLocationAfter;
          final statuses = homeMemberStatuses(
            members: list,
            locations: locations.value,
            locationsFailed: locations.hasError,
            myUid: ref.watch(currentUserProvider).value?.uid,
            now: ref.watch(clockProvider).now(),
            staleAfter: staleAfter,
          );
          if (statuses.isEmpty) return const _NoOtherMembers();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final status in statuses)
                _MemberRow(key: ValueKey(status.member.uid), status: status),
              const SizedBox(height: NxSpace.sm),
              Text(
                l10n.homeStaleExplanation(staleAfter.inMinutes),
                style: context.text.bodySmall?.copyWith(
                  color: context.nx.inkMuted,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NoOtherMembers extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.homeMembersEmpty,
          style: context.text.bodyMedium?.copyWith(color: context.nx.inkMuted),
        ),
        const SizedBox(height: NxSpace.sm),
        NxButton(
          label: l10n.homeMembersInvite,
          icon: Icons.person_add_alt_1_outlined,
          variant: NxButtonVariant.secondary,
          expand: false,
          onPressed: () => unawaited(context.push(AppRoutes.invite)),
        ),
      ],
    );
  }
}

class _MemberRow extends ConsumerWidget {
  const new({required this.status, super.key});

  final HomeMemberStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.nx;
    final now = ref.watch(clockProvider).now();
    final member = status.member;
    final name = member.displayName.trim();
    String ago(DateTime at) => relativeTime(l10n, at, now);
    final at = status.reportedAt;
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final (
      IconData icon,
      Color iconColor,
      String text,
    ) = switch (status.state) {
      HomeLocationState.recent when at != null => (
        Icons.location_on_outlined,
        c.secondary,
        status.isApproximate
            ? l10n.homeMemberRecentApprox(ago(at))
            : l10n.homeMemberRecent(ago(at)),
      ),
      // Sin hora fiable nunca se presenta como reciente.
      HomeLocationState.recent || HomeLocationState.stale => (
        Icons.schedule,
        c.warning,
        at == null ? l10n.homeMemberStale : l10n.homeMemberStaleSince(ago(at)),
      ),
      HomeLocationState.notSharing => (
        Icons.location_off_outlined,
        c.inkMuted,
        l10n.homeMemberNotSharing,
      ),
      HomeLocationState.loading => (
        Icons.location_searching,
        c.inkMuted,
        l10n.homeMemberLocationLoading,
      ),
      HomeLocationState.unavailable => (
        Icons.error_outline,
        c.inkMuted,
        l10n.homeMemberLocationUnavailable,
      ),
    };
    // Un solo nodo para el lector de pantalla: nombre, estado y acción.
    return MergeSemantics(
      child: Semantics(
        button: true,
        hint: l10n.homeMemberOpenHint,
        child: InkWell(
          borderRadius: NxRadius.mdAll,
          onTap: () => unawaited(context.push(AppRoutes.member(member.uid))),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: NxSize.minTouchTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: NxSpace.xs),
              child: Row(
                children: [
                  // Con texto muy grande, el avatar (decorativo) cede su
                  // espacio al nombre y al estado.
                  if (!largeText) ...[
                    NxAvatar(
                      name: name,
                      colorSeed: member.uid.codeUnits.fold(0, (s, u) => s + u),
                    ),
                    const SizedBox(width: NxSpace.sm),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? l10n.activityUnknownMember : name,
                          style: context.text.titleSmall,
                        ),
                        const SizedBox(height: NxSpace.xxs),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(
                                icon,
                                size: nxScaledIcon(context, NxSize.iconSm - 2),
                                color: iconColor,
                              ),
                            ),
                            const SizedBox(width: NxSpace.xxs),
                            Expanded(
                              child: Text(
                                text,
                                style: context.text.bodyMedium?.copyWith(
                                  color: c.inkMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ExcludeSemantics(
                    child: Icon(
                      Icons.chevron_right,
                      color: c.inkMuted,
                      size: nxScaledIcon(context, NxSize.iconMd),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
