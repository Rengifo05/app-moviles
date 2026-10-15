import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/components/nx_section.dart';
import 'package:nexo_familia/design_system/components/nx_state_views.dart';
import 'package:nexo_familia/design_system/components/nx_status_pill.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_actions.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/family/presentation/family_text.dart';
import 'package:nexo_familia/features/family/presentation/family_widgets.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Genera un código de invitación de un solo uso para la familia activa.
/// Solo para owner/admin (el servidor lo vuelve a validar).
class InviteScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final familyId = ref.watch(activeFamilyIdProvider);
    final family = ref.watch(activeFamilyProvider);
    final Widget body;
    if (familyId == null) {
      body = NxMessageView(
        icon: Icons.groups_outlined,
        title: l10n.familyNoActiveTitle,
      );
    } else if (family.isLoading && !family.hasValue) {
      body = NxLoadingView(label: l10n.commonLoading);
    } else if (family.value case final group? when group.myRole.canManage) {
      body = _InviteBody(family: group);
    } else {
      body = NxMessageView(
        icon: Icons.lock_outline,
        title: l10n.familyErrorNotAllowedInvite,
        actionLabel: l10n.familyBackToFamily,
        onAction: () => context.go(AppRoutes.family),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.familyInviteTitle)),
      body: SafeArea(top: false, child: body),
    );
  }
}

class _InviteBody extends ConsumerStatefulWidget {
  const new({required this.family});

  final FamilyGroup family;

  @override
  ConsumerState<_InviteBody> createState() => _InviteBodyState();
}

class _InviteBodyState extends ConsumerState<_InviteBody> {
  final GlobalKey _codeKey = GlobalKey();
  final GlobalKey _errorKey = GlobalKey();
  CreatedInvitation? _invitation;
  bool _busy = false;
  bool _copied = false;
  String? _error;

  Future<void> _generate() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(familyActionsProvider)
        .createInvitation(widget.family.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Ok(:final value):
          _invitation = value;
          _copied = false;
        case Err(:final failure):
          _error = familyFailureMessage(l10n, failure, FamilyOperation.invite);
      }
    });
    // Con texto grande, el código aparece por encima del botón pulsado.
    if (result.isOk) {
      revealAfterFrame(_codeKey);
    } else {
      revealAfterFrame(_errorKey, alignEnd: true);
    }
  }

  Future<void> _copy(CreatedInvitation invitation) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      ClipboardData(text: FamilyRules.formatCode(invitation.code)),
    );
    if (!mounted) return;
    setState(() => _copied = true);
    // El SnackBar es una región en vivo: los lectores de pantalla lo anuncian.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.familyInviteCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final memberCount =
        ref.watch(familyMembersProvider(widget.family.id)).value?.length ?? 0;
    final isFull = memberCount >= FamilyRules.maxMembers;
    final invitation = _invitation;

    return NxPageBody(
      children: [
        const SizedBox(height: NxSpace.sm),
        Text(
          l10n.familyInviteBody(widget.family.name),
          style: context.text.bodyLarge,
        ),
        if (isFull) ...[
          const SizedBox(height: NxSpace.md),
          NxBanner(
            icon: Icons.group_off_outlined,
            message: l10n.familyInviteFull(FamilyRules.maxMembers),
          ),
        ],
        if (invitation != null) ...[
          const SizedBox(height: NxSpace.lg),
          _CodePanel(
            key: _codeKey,
            invitation: invitation,
            copied: _copied,
            onCopy: () => _copy(invitation),
          ),
        ],
        const SizedBox(height: NxSpace.md),
        FamilyNote(
          icon: Icons.person_outline,
          text: l10n.familyInviteWarningShare,
        ),
        FamilyNote(
          icon: Icons.visibility_outlined,
          text: l10n.familyInviteWarningVisibility,
        ),
        if (invitation != null)
          FamilyNote(
            icon: Icons.lock_clock_outlined,
            text: l10n.familyInviteWarningOnce,
          ),
        if (_error case final error?) ...[
          const SizedBox(height: NxSpace.sm),
          NxBanner(key: _errorKey, icon: Icons.error_outline, message: error),
        ],
        const SizedBox(height: NxSpace.lg),
        NxButton(
          label: invitation == null
              ? l10n.familyInviteGenerate
              : l10n.familyInviteGenerateAnother,
          icon: invitation == null ? Icons.vpn_key_outlined : Icons.refresh,
          variant: invitation == null
              ? NxButtonVariant.primary
              : NxButtonVariant.tertiary,
          loading: _busy,
          onPressed: isFull ? null : _generate,
        ),
      ],
    );
  }
}

class _CodePanel extends ConsumerWidget {
  const new({
    required this.invitation,
    required this.copied,
    required this.onCopy,
    super.key,
  });

  final CreatedInvitation invitation;
  final bool copied;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.nx;
    final clock = ref.watch(clockProvider);
    return NxSurface(
      padding: const EdgeInsets.all(NxSpace.lg),
      child: PeriodicRebuild(
        builder: (context) {
          final expires = inviteExpiresText(
            l10n,
            invitation.expiresAt.difference(clock.now()),
          );
          return Column(
            children: [
              Text(
                l10n.familyInviteCodeLabel,
                style: context.text.labelLarge?.copyWith(color: c.inkMuted),
              ),
              const SizedBox(height: NxSpace.xs),
              // Región en vivo: el lector de pantalla anuncia el código en
              // cuanto aparece.
              Semantics(
                container: true,
                liveRegion: true,
                label: l10n.familyInviteCodeSemantics(
                  spellInvitationCode(invitation.code),
                ),
                excludeSemantics: true,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    FamilyRules.formatCode(invitation.code),
                    maxLines: 1,
                    style: context.text.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: expires == null ? c.inkMuted : c.ink,
                      decoration: expires == null
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: NxSpace.sm),
              if (expires == null)
                NxStatusPill(
                  label: l10n.familyInviteExpired,
                  icon: Icons.timer_off_outlined,
                  tone: NxTone.warning,
                )
              else
                NxStatusPill(
                  label: l10n.familyInviteValidity(
                    expires,
                    l10n.familyInviteUses(invitation.maxUses),
                  ),
                  icon: Icons.schedule,
                  tone: NxTone.info,
                ),
              const SizedBox(height: NxSpace.md),
              NxButton(
                label: copied ? l10n.familyInviteCopied : l10n.familyInviteCopy,
                icon: copied ? Icons.check : Icons.copy_outlined,
                variant: NxButtonVariant.secondary,
                onPressed: expires == null ? null : onCopy,
              ),
            ],
          );
        },
      ),
    );
  }
}
