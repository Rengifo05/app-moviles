import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/nx_avatar.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/components/nx_section.dart';
import 'package:nexo_familia/design_system/components/nx_state_views.dart';
import 'package:nexo_familia/design_system/components/nx_status_pill.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/common/presentation/async_view.dart';
import 'package:nexo_familia/features/common/presentation/relative_time.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_actions.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/family/presentation/family_text.dart';
import 'package:nexo_familia/features/family/presentation/family_view_logic.dart';
import 'package:nexo_familia/features/family/presentation/family_widgets.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Detalle de un integrante de la familia activa: rol, antigüedad y estado
/// de su ubicación (sin afirmar nunca que la persona está bien).
class MemberDetailScreen extends ConsumerWidget {
  const new({required this.uid, super.key});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final familyId = ref.watch(activeFamilyIdProvider);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: familyId == null
            ? NxMessageView(
                icon: Icons.groups_outlined,
                title: l10n.familyNoActiveTitle,
              )
            : AsyncView(
                value: ref.watch(familyMembersProvider(familyId)),
                onRetry: () => ref.invalidate(familyMembersProvider(familyId)),
                builder: (members) {
                  final member = members.where((m) => m.uid == uid).firstOrNull;
                  if (member == null) {
                    return NxMessageView(
                      icon: Icons.person_off_outlined,
                      title: l10n.familyErrorNotMember,
                      actionLabel: l10n.familyBackToFamily,
                      onAction: () => context.go(AppRoutes.family),
                    );
                  }
                  return _MemberBody(familyId: familyId, member: member);
                },
              ),
      ),
    );
  }
}

class _MemberBody extends ConsumerStatefulWidget {
  const new({required this.familyId, required this.member});

  final String familyId;
  final FamilyMember member;

  @override
  ConsumerState<_MemberBody> createState() => _MemberBodyState();
}

class _MemberBodyState extends ConsumerState<_MemberBody> {
  bool _removing = false;

  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final name = widget.member.displayName;
    final confirmed = await showFamilyConfirmDialog(
      context,
      title: l10n.familyRemoveTitle(name),
      consequences: [
        (Icons.person_remove_outlined, l10n.familyRemoveBody(name)),
      ],
      confirmLabel: l10n.familyRemove,
    );
    if (!confirmed || !mounted) return;
    setState(() => _removing = true);
    final result = await ref
        .read(familyActionsProvider)
        .removeMember(widget.familyId, widget.member.uid);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(switch (result) {
            Ok() => l10n.familyRemoved(name),
            Err(:final failure) => familyFailureMessage(
              l10n,
              failure,
              FamilyOperation.remove,
            ),
          }),
        ),
      );
    if (result.isOk) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go(AppRoutes.family);
      }
      return;
    }
    if (mounted) setState(() => _removing = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.nx;
    final member = widget.member;
    final myUid = ref.watch(currentUserProvider).value?.uid;
    final myRole = ref.watch(activeFamilyProvider).value?.myRole;
    final isMe = member.uid == myUid;
    final canRemove =
        myUid != null &&
        myRole != null &&
        canRemoveMember(myUid: myUid, myRole: myRole, target: member);

    return NxPageBody(
      children: [
        const SizedBox(height: NxSpace.xs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: NxAvatar(
            name: member.displayName,
            size: NxSize.avatarLg,
            colorSeed: member.uid.codeUnits.fold(0, (sum, u) => sum + u),
          ),
        ),
        const SizedBox(height: NxSpace.md),
        Wrap(
          spacing: NxSpace.xs,
          runSpacing: NxSpace.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(
                member.displayName,
                style: context.text.headlineSmall,
              ),
            ),
            if (isMe)
              NxStatusPill(
                label: l10n.familyYou,
                icon: Icons.person_outline,
                tone: NxTone.info,
              ),
          ],
        ),
        const SizedBox(height: NxSpace.xxs),
        Text(
          familyRoleLabel(l10n, member.role),
          style: context.text.bodyLarge?.copyWith(color: c.inkMuted),
        ),
        const SizedBox(height: NxSpace.xxs),
        Text(
          l10n.familyMemberSince(member.joinedAt.toLocal()),
          style: context.text.bodyMedium?.copyWith(color: c.inkMuted),
        ),
        NxSectionHeader(title: l10n.familyLocationTitle),
        _LocationStatus(familyId: widget.familyId, uid: member.uid, isMe: isMe),
        if (isMe) ...[
          const SizedBox(height: NxSpace.lg),
          NxButton(
            label: l10n.familyPrivacyLink,
            variant: NxButtonVariant.secondary,
            onPressed: () => context.go(AppRoutes.privacy),
          ),
        ],
        if (canRemove) ...[
          const SizedBox(height: NxSpace.xl),
          NxButton(
            label: l10n.familyRemove,
            icon: Icons.person_remove_outlined,
            variant: NxButtonVariant.destructive,
            loading: _removing,
            onPressed: _remove,
          ),
        ],
      ],
    );
  }
}

/// Estado de la ubicación de una persona: "Ubicación actualizada hace X",
/// "Sin actualización reciente" o "No comparte su ubicación".
class _LocationStatus extends ConsumerWidget {
  const new({required this.familyId, required this.uid, required this.isMe});

  final String familyId;
  final String uid;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locations = ref.watch(familyLocationsProvider(familyId));
    if (!locations.hasValue) {
      return FamilyNote(
        icon: locations.hasError ? Icons.error_outline : Icons.schedule,
        text: locations.hasError
            ? l10n.familyLocationUnavailable
            : l10n.commonLoading,
      );
    }
    final location = locations.requireValue
        .where((l) => l.uid == uid)
        .firstOrNull;
    final staleAfter = ref.watch(appConfigProvider).staleLocationAfter;
    final clock = ref.watch(clockProvider);

    return PeriodicRebuild(
      builder: (context) {
        final now = clock.now();
        final summary = summarizeMemberLocation(
          location,
          now: now,
          staleAfter: staleAfter,
        );
        final ago = summary.reportedAt == null
            ? null
            : relativeTime(l10n, summary.reportedAt!, now);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: switch (summary.state) {
                MemberLocationState.recent => NxStatusPill(
                  label: l10n.familyLocationUpdated(ago!),
                  icon: Icons.schedule,
                  tone: NxTone.positive,
                ),
                MemberLocationState.stale => NxStatusPill(
                  label: l10n.familyLocationStale,
                  icon: Icons.history_toggle_off,
                  tone: NxTone.warning,
                ),
                MemberLocationState.notSharing => NxStatusPill(
                  label: isMe
                      ? l10n.familyLocationSelfNotSharing
                      : l10n.familyLocationNotSharing,
                  icon: Icons.location_off_outlined,
                ),
              },
            ),
            if (summary.state == MemberLocationState.stale && ago != null)
              FamilyNote(
                icon: Icons.history,
                text: l10n.familyLocationLastUpdate(ago),
              ),
            if (summary.isApproximate)
              FamilyNote(
                icon: Icons.blur_circular,
                text: l10n.familyLocationApproximate,
              ),
            if (summary.state != MemberLocationState.notSharing)
              FamilyNote(
                icon: Icons.info_outline,
                text: l10n.familyLocationDeviceNote,
              ),
          ],
        );
      },
    );
  }
}
