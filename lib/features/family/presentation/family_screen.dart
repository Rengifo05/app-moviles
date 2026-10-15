import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/nx_avatar.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/components/nx_section.dart';
import 'package:nexo_familia/design_system/components/nx_state_views.dart';
import 'package:nexo_familia/design_system/components/nx_status_pill.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/common/presentation/async_view.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_actions.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/family/presentation/family_text.dart';
import 'package:nexo_familia/features/family/presentation/family_widgets.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Pestaña Familia: integrantes de la familia activa, invitar, cambiar de
/// familia y salir del grupo.
class FamilyScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final familyId = ref.watch(activeFamilyIdProvider);
    final offline = ref.watch(syncStatusProvider).value == SyncStatus.offline;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navFamily)),
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
                      title: l10n.familyNoActiveTitle,
                    )
                  : AsyncView(
                      value: ref.watch(familyMembersProvider(familyId)),
                      onRetry: () =>
                          ref.invalidate(familyMembersProvider(familyId)),
                      builder: (members) =>
                          _FamilyBody(familyId: familyId, members: members),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FamilyBody extends ConsumerStatefulWidget {
  const new({required this.familyId, required this.members});

  final String familyId;
  final List<FamilyMember> members;

  @override
  ConsumerState<_FamilyBody> createState() => _FamilyBodyState();
}

class _FamilyBodyState extends ConsumerState<_FamilyBody> {
  bool _leaving = false;

  Future<void> _switchFamily(
    List<FamilyGroup> families,
    String activeId,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showModalBottomSheet<_FamilyChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _FamilySwitcherSheet(families: families, activeId: activeId),
    );
    if (choice == null || !mounted) return;
    final String selected;
    switch (choice) {
      case _OpenRoute(:final route):
        unawaited(context.push(route));
        return;
      case _SwitchTo(:final familyId):
        selected = familyId;
    }
    if (selected == activeId) return;
    final result = await ref.read(familyActionsProvider).switchTo(selected);
    final name = families.firstWhere((f) => f.id == selected).name;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(switch (result) {
            Ok() => l10n.familySwitched(name),
            Err(:final failure) => familyFailureMessage(
              l10n,
              failure,
              FamilyOperation.switchFamily,
            ),
          }),
        ),
      );
  }

  Future<void> _leave(FamilyGroup? family) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = family?.name ?? l10n.navFamily;
    final isLast = widget.members.length <= 1;
    final confirmed = await showFamilyConfirmDialog(
      context,
      title: l10n.familyLeaveTitle(name),
      consequences: [
        (Icons.visibility_off_outlined, l10n.familyLeaveSee),
        (Icons.location_off_outlined, l10n.familyLeaveShare),
        if (isLast)
          (Icons.delete_outline, l10n.familyLeaveLast)
        else if (family?.myRole == MemberRole.owner)
          (Icons.manage_accounts_outlined, l10n.familyLeaveOwner),
        (Icons.vpn_key_outlined, l10n.familyLeaveReturn),
      ],
      confirmLabel: l10n.familyLeave,
    );
    if (!confirmed || !mounted) return;
    setState(() => _leaving = true);
    final result = await ref.read(familyActionsProvider).leave(widget.familyId);
    // Tras salir, la sesión cambia de familia (o lleva a crear una) y esta
    // vista puede desaparecer: el aviso va al ScaffoldMessenger raíz.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(switch (result) {
            Ok() => l10n.familyLeft(name),
            Err(:final failure) => familyFailureMessage(
              l10n,
              failure,
              FamilyOperation.leave,
            ),
          }),
        ),
      );
    if (mounted) setState(() => _leaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final family = ref.watch(activeFamilyProvider).value;
    final families = ref.watch(myFamiliesProvider).value ?? const [];
    final myUid = ref.watch(currentUserProvider).value?.uid;
    final canManage = family?.myRole.canManage ?? false;
    final members = widget.members;

    void invite() => context.push(AppRoutes.invite);

    if (members.isEmpty) {
      return NxMessageView(
        icon: Icons.groups_outlined,
        title: l10n.familyEmptyTitle,
        body: l10n.familyEmptyBody,
        actionLabel: canManage ? l10n.familyInviteAction : null,
        onAction: canManage ? invite : null,
      );
    }

    return NxPageBody(
      children: [
        const SizedBox(height: NxSpace.sm),
        Semantics(
          header: true,
          child: Text(
            family?.name ?? l10n.navFamily,
            style: context.text.headlineSmall,
          ),
        ),
        const SizedBox(height: NxSpace.xxs),
        Text(
          l10n.familyMemberCount(members.length),
          style: context.text.bodyMedium?.copyWith(color: context.nx.inkMuted),
        ),
        // Siempre visible: además de cambiar, permite crear otra familia o
        // unirse a otra (hasta 5 por persona).
        if (families.isNotEmpty) ...[
          const SizedBox(height: NxSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: NxButton(
              label: l10n.familySwitch,
              icon: Icons.swap_horiz,
              variant: NxButtonVariant.secondary,
              expand: false,
              onPressed: () => _switchFamily(families, widget.familyId),
            ),
          ),
        ],
        if (canManage) ...[
          const SizedBox(height: NxSpace.md),
          NxButton(
            label: l10n.familyInviteAction,
            icon: Icons.person_add_alt_1_outlined,
            onPressed: invite,
          ),
        ],
        NxSectionHeader(title: l10n.familyMembersTitle),
        NxSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (index, member) in members.indexed) ...[
                if (index > 0) const Divider(indent: NxSpace.md),
                _MemberTile(member: member, isMe: member.uid == myUid),
              ],
            ],
          ),
        ),
        const SizedBox(height: NxSpace.sm),
        FamilyNote(icon: Icons.lock_outline, text: l10n.familyPrivacyNote),
        const SizedBox(height: NxSpace.xl),
        NxButton(
          label: l10n.familyLeave,
          icon: Icons.logout,
          variant: NxButtonVariant.destructive,
          loading: _leaving,
          onPressed: () => _leave(family),
        ),
      ],
    );
  }
}

/// Semilla estable para el tono del avatar (no depende de `hashCode`).
int _avatarSeed(String uid) => uid.codeUnits.fold(0, (sum, u) => sum + u);

class _MemberTile extends StatelessWidget {
  const new({required this.member, required this.isMe});

  final FamilyMember member;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      leading: NxAvatar(
        name: member.displayName,
        colorSeed: _avatarSeed(member.uid),
      ),
      title: Wrap(
        spacing: NxSpace.xs,
        runSpacing: NxSpace.xxs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(member.displayName),
          if (isMe)
            NxStatusPill(
              label: l10n.familyYou,
              icon: Icons.person_outline,
              tone: NxTone.info,
            ),
        ],
      ),
      subtitle: Text(familyRoleLabel(l10n, member.role)),
      trailing: ExcludeSemantics(
        child: Icon(Icons.chevron_right, color: context.nx.inkMuted),
      ),
      onTap: () => context.push(AppRoutes.member(member.uid)),
    );
  }
}

/// Lo que se elige en la hoja de familias.
sealed class _FamilyChoice {
  const new();
}

final class _SwitchTo extends _FamilyChoice {
  const new(this.familyId);
  final String familyId;
}

final class _OpenRoute extends _FamilyChoice {
  const new(this.route);
  final String route;
}

class _FamilySwitcherSheet extends StatelessWidget {
  const new({required this.families, required this.activeId});

  final List<FamilyGroup> families;
  final String activeId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.nx;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: NxSpace.md),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NxSpace.gutter,
              0,
              NxSpace.gutter,
              NxSpace.xs,
            ),
            child: Semantics(
              header: true,
              child: Text(
                l10n.familySwitchTitle,
                style: context.text.titleLarge,
              ),
            ),
          ),
          for (final family in families)
            ListTile(
              selected: family.id == activeId,
              selectedColor: c.ink,
              title: Text(family.name),
              subtitle: Text(familyRoleLabel(l10n, family.myRole)),
              trailing: family.id == activeId
                  ? Icon(
                      Icons.check_circle,
                      color: c.positive,
                      semanticLabel: l10n.familySwitchActive,
                    )
                  : null,
              onTap: () => Navigator.of(context).pop(_SwitchTo(family.id)),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(l10n.familySwitchCreate),
            onTap: () =>
                Navigator.of(context)
                    .pop(const _OpenRoute(AppRoutes.createFamily)),
          ),
          ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: Text(l10n.familySwitchJoin),
            onTap: () =>
                Navigator.of(context)
                    .pop(const _OpenRoute(AppRoutes.joinFamily)),
          ),
        ],
      ),
    );
  }
}
