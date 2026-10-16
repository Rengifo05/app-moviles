import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/components/nx_section.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/common/presentation/failure_text.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_widgets.dart';
import 'package:nexo_familia/features/settings/presentation/account_actions.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Con sesión y sin familia: crear una o unirse con un código.
class FamilySetupScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<FamilySetupScreen> createState() => _FamilySetupScreenState();
}

class _FamilySetupScreenState extends ConsumerState<FamilySetupScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _signingOut = true);
    // Igual que en Cuenta: antes de cerrar la sesión se borra el registro
    // de avisos de este teléfono (ADR-005).
    final result = await ref.read(accountActionsProvider).signOut();
    if (result case Err(:final failure)) {
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(l10n, failure))),
      );
    }
    // En caso de éxito, la sesión cambia y el enrutador lleva a iniciar
    // sesión.
    if (mounted) setState(() => _signingOut = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = ref.watch(currentUserProvider).value?.displayName?.trim();
    return FamilyFormScaffold(
      appBarTitle: l10n.navFamily,
      title: name == null || name.isEmpty
          ? l10n.familySetupGreetingNoName
          : l10n.familySetupGreeting(name),
      subtitle: l10n.familySetupBody,
      children: [
        NxButton(
          label: l10n.familySetupCreate,
          onPressed: () => context.push(AppRoutes.createFamily),
        ),
        const SizedBox(height: NxSpace.sm),
        NxButton(
          label: l10n.familySetupJoin,
          variant: NxButtonVariant.secondary,
          onPressed: () => context.push(AppRoutes.joinFamily),
        ),
        const SizedBox(height: NxSpace.md),
        NxSectionHeader(title: l10n.familySetupWhatTitle),
        FamilyNote(
          icon: Icons.groups_outlined,
          text: l10n.familySetupWhatGroup(FamilyRules.maxMembers),
        ),
        FamilyNote(icon: Icons.lock_outline, text: l10n.familySetupWhatConsent),
        FamilyNote(
          icon: Icons.mark_email_read_outlined,
          text: l10n.familySetupWhatInvite,
        ),
        const SizedBox(height: NxSpace.xl),
        NxButton(
          label: l10n.familySetupSignOut,
          icon: Icons.logout,
          variant: NxButtonVariant.tertiary,
          loading: _signingOut,
          onPressed: _signOut,
        ),
      ],
    );
  }
}
