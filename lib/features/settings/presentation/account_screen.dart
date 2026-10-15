import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/components/nx_section.dart';
import 'package:nexo_familia/design_system/components/nx_state_views.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/common/presentation/failure_text.dart';
import 'package:nexo_familia/features/family/presentation/family_widgets.dart';
import 'package:nexo_familia/features/settings/presentation/account_actions.dart';
import 'package:nexo_familia/features/settings/presentation/settings_providers.dart';
import 'package:nexo_familia/features/settings/presentation/settings_widgets.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Cuenta: correo, cerrar sesión y eliminar la cuenta (con doble
/// confirmación que explica las consecuencias).
class AccountScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAccountTitle)),
      body: SafeArea(
        top: false,
        child: switch (user) {
          AsyncValue(value: final user?) => _AccountBody(user: user),
          AsyncValue(hasValue: true) => NxMessageView(
            icon: Icons.person_off_outlined,
            title: l10n.settingsAccountNoUser,
          ),
          AsyncError(:final error) => NxMessageView(
            icon: Icons.error_outline,
            title: failureMessage(
              l10n,
              error is Failure ? error : const Failure.unexpected(),
            ),
          ),
          _ => NxLoadingView(label: l10n.commonLoading),
        },
      ),
    );
  }
}

enum _AccountOperation { signOut, signOutEverywhere, delete }

class _AccountBody extends ConsumerStatefulWidget {
  const new({required this.user});

  final AuthUser user;

  @override
  ConsumerState<_AccountBody> createState() => _AccountBodyState();
}

class _AccountBodyState extends ConsumerState<_AccountBody> {
  _AccountOperation? _busy;
  ({_AccountOperation operation, Failure failure})? _error;

  Future<void> _signOut() async {
    if (_busy != null) return;
    final l10n = AppLocalizations.of(context);
    final pending = ref.read(pendingOutboxCountProvider).value ?? 0;
    if (pending > 0) {
      final confirmed = await showFamilyConfirmDialog(
        context,
        title: l10n.settingsAccountSignOutPendingTitle,
        consequences: [
          (Icons.cloud_upload_outlined, l10n.settingsAccountPending(pending)),
        ],
        confirmLabel: l10n.settingsAccountSignOutAnyway,
      );
      if (!confirmed || !mounted) return;
    }
    await _run(
      _AccountOperation.signOut,
      ref.read(accountActionsProvider).signOut,
    );
  }

  Future<void> _signOutEverywhere() async {
    if (_busy != null) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFamilyConfirmDialog(
      context,
      title: l10n.settingsAccountEverywhereTitle,
      consequences: [
        (Icons.devices_other_outlined, l10n.settingsAccountEverywhereDevices),
        (
          Icons.notifications_off_outlined,
          l10n.settingsAccountEverywhereAlerts,
        ),
        (Icons.vpn_key_off_outlined, l10n.settingsAccountEverywhereInvites),
        (Icons.logout, l10n.settingsAccountEverywhereHere),
      ],
      confirmLabel: l10n.settingsAccountEverywhereConfirm,
    );
    if (!confirmed || !mounted) return;
    await _run(
      _AccountOperation.signOutEverywhere,
      ref.read(accountActionsProvider).signOutEverywhere,
    );
  }

  Future<void> _delete() async {
    if (_busy != null) return;
    final l10n = AppLocalizations.of(context);
    final understood = await showFamilyConfirmDialog(
      context,
      title: l10n.settingsAccountDeleteConfirmTitle,
      consequences: [
        (Icons.groups_outlined, l10n.settingsAccountDeleteFamilies),
        (Icons.manage_accounts_outlined, l10n.settingsAccountDeleteOwner),
        (Icons.person_remove_outlined, l10n.settingsAccountDeleteProfile),
        (Icons.event_busy_outlined, l10n.settingsAccountDeleteEvents),
        (Icons.history_outlined, l10n.settingsAccountDeleteAudit),
        (Icons.backup_outlined, l10n.settingsAccountDeleteBackups),
      ],
      confirmLabel: l10n.settingsAccountDeleteContinue,
    );
    if (!understood || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _FinalDeleteDialog(),
    );
    if (!(confirmed ?? false) || !mounted) return;
    await _run(
      _AccountOperation.delete,
      ref.read(accountActionsProvider).deleteAccount,
    );
  }

  Future<void> _run(
    _AccountOperation operation,
    Future<VoidResult> Function() action,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = operation;
      _error = null;
    });
    final result = await action();
    // Con éxito la sesión termina y el enrutador lleva a iniciar sesión:
    // esta vista desaparece, así que el aviso va al ScaffoldMessenger raíz.
    if (result.isOk && operation == _AccountOperation.delete) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.settingsAccountDeleted)));
    }
    if (!mounted) return;
    setState(() {
      _busy = null;
      if (result case Err(:final failure)) {
        _error = (operation: operation, failure: failure);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.nx;
    final muted = context.text.bodyMedium?.copyWith(color: c.inkMuted);
    final name = widget.user.displayName?.trim();
    final pending = ref.watch(pendingOutboxCountProvider).value ?? 0;
    final error = _error;
    final idle = _busy == null;

    Widget errorBanner(_AccountOperation operation) => Padding(
      padding: const EdgeInsets.only(top: NxSpace.sm),
      child: NxBanner(
        icon: Icons.error_outline,
        message: switch (operation) {
          _AccountOperation.signOut => l10n.settingsAccountSignOutFailed(
            failureMessage(l10n, error!.failure),
          ),
          _AccountOperation.signOutEverywhere =>
            l10n.settingsAccountEverywhereFailed(
              failureMessage(l10n, error!.failure),
            ),
          _AccountOperation.delete => l10n.settingsAccountDeleteFailed(
            failureMessage(l10n, error!.failure),
          ),
        },
      ),
    );

    return NxPageBody(
      children: [
        const SizedBox(height: NxSpace.md),
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.settingsAccountEmailLabel, style: muted),
              const SizedBox(height: NxSpace.xxs),
              Text(
                breakableAtSeparators(widget.user.email),
                semanticsLabel: widget.user.email,
                style: context.text.titleMedium,
              ),
            ],
          ),
        ),
        if (name != null && name.isNotEmpty) ...[
          const SizedBox(height: NxSpace.md),
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.settingsAccountNameLabel, style: muted),
                const SizedBox(height: NxSpace.xxs),
                Text(name, style: context.text.titleMedium),
              ],
            ),
          ),
        ],
        const SizedBox(height: NxSpace.lg),
        if (pending > 0) ...[
          NxBanner(
            icon: Icons.cloud_upload_outlined,
            message: l10n.settingsAccountPending(pending),
          ),
          const SizedBox(height: NxSpace.sm),
        ],
        NxButton(
          label: l10n.settingsAccountSignOut,
          icon: Icons.logout,
          variant: NxButtonVariant.secondary,
          loading: _busy == _AccountOperation.signOut,
          onPressed: idle ? _signOut : null,
        ),
        FamilyNote(
          icon: Icons.phone_android_outlined,
          text: l10n.settingsAccountSignOutNote,
          style: muted,
        ),
        if (error?.operation == _AccountOperation.signOut)
          errorBanner(_AccountOperation.signOut),
        const SizedBox(height: NxSpace.sm),
        NxButton(
          label: l10n.settingsAccountEverywhere,
          icon: Icons.devices_other_outlined,
          variant: NxButtonVariant.tertiary,
          loading: _busy == _AccountOperation.signOutEverywhere,
          onPressed: idle ? _signOutEverywhere : null,
        ),
        if (error?.operation == _AccountOperation.signOutEverywhere)
          errorBanner(_AccountOperation.signOutEverywhere),
        NxSectionHeader(title: l10n.settingsAccountDeleteTitle),
        Text(l10n.settingsAccountDeleteIntro, style: context.text.bodyMedium),
        const SizedBox(height: NxSpace.md),
        NxButton(
          label: l10n.settingsAccountDelete,
          icon: Icons.delete_outline,
          variant: NxButtonVariant.destructive,
          loading: _busy == _AccountOperation.delete,
          onPressed: idle ? _delete : null,
        ),
        if (error?.operation == _AccountOperation.delete)
          errorBanner(_AccountOperation.delete),
      ],
    );
  }
}

/// Segunda confirmación: hay que escribir la palabra indicada. Devuelve
/// `true` solo si coincide y se pulsa "Eliminar definitivamente".
class _FinalDeleteDialog extends StatefulWidget {
  const new();

  @override
  State<_FinalDeleteDialog> createState() => _FinalDeleteDialogState();
}

class _FinalDeleteDialogState extends State<_FinalDeleteDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final word = l10n.settingsAccountDeleteWord;
    return AlertDialog(
      title: Text(l10n.settingsAccountDeleteFinalTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.settingsAccountDeleteFinalBody(word),
              style: context.text.bodyLarge,
            ),
            const SizedBox(height: NxSpace.md),
            TextField(
              controller: _controller,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: l10n.settingsAccountDeleteField,
              ),
            ),
          ],
        ),
      ),
      actions: [
        NxButton(
          label: l10n.commonCancel,
          variant: NxButtonVariant.tertiary,
          expand: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => NxButton(
            label: l10n.settingsAccountDeleteFinalConfirm,
            variant: NxButtonVariant.destructive,
            expand: false,
            onPressed:
                _controller.text.trim().toUpperCase() == word.toUpperCase()
                ? () => Navigator.of(context).pop(true)
                : null,
          ),
        ),
      ],
    );
  }
}
