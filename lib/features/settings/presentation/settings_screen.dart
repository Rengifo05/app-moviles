import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/design_system/components/nx_section.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/family/presentation/family_widgets.dart';
import 'package:nexo_familia/features/settings/presentation/settings_providers.dart';
import 'package:nexo_familia/features/settings/presentation/settings_widgets.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Pestaña Ajustes: accesos a Privacidad y Cuenta, preferencias de
/// notificaciones y "Acerca de".
class SettingsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final email = ref.watch(currentUserProvider).value?.email.trim();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      body: SafeArea(
        top: false,
        child: NxPageBody(
          children: [
            NxSectionHeader(title: l10n.settingsSectionPrivacy),
            SettingsLinkTile(
              icon: Icons.shield_outlined,
              title: l10n.settingsPrivacyTile,
              subtitle: l10n.settingsPrivacyTileSubtitle,
              onTap: () => context.go(AppRoutes.privacy),
            ),
            NxSectionHeader(title: l10n.settingsSectionAccount),
            SettingsLinkTile(
              icon: Icons.person_outline,
              title: l10n.settingsAccountTile,
              subtitle: email == null || email.isEmpty
                  ? l10n.settingsAccountTileSubtitle
                  : email,
              onTap: () => context.go(AppRoutes.account),
            ),
            NxSectionHeader(title: l10n.settingsSectionNotifications),
            const _NotificationSettings(),
            NxSectionHeader(title: l10n.settingsSectionAbout),
            const _About(),
          ],
        ),
      ),
    );
  }
}

class _NotificationSettings extends ConsumerWidget {
  const new();

  Future<void> _setHideDetails(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = AppLocalizations.of(context).settingsHideDetailsError;
    try {
      await ref
          .read(preferencesRepositoryProvider)
          .update((p) => p.copyWith(hideNotificationDetails: value));
    } on Object {
      // El interruptor sigue mostrando el valor guardado (lo lee del
      // repositorio): solo falta avisar de que no cambió.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(preferencesProvider).value;
    final pushAvailable = ref.watch(pushNotificationsAvailableProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: prefs?.hideNotificationDetails ?? false,
          onChanged: prefs == null
              ? null
              : (value) => _setHideDetails(context, ref, value),
          title: Text(l10n.settingsHideDetails, style: context.text.titleSmall),
          subtitle: Text(
            l10n.settingsHideDetailsSubtitle,
            style: context.text.bodyMedium?.copyWith(
              color: context.nx.inkMuted,
            ),
          ),
        ),
        if (!pushAvailable)
          FamilyNote(
            icon: Icons.notifications_off_outlined,
            text: l10n.settingsPushUnavailable,
          ),
      ],
    );
  }
}

class _About extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(appConfigProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: NxSpace.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(config.appName, style: context.text.titleSmall),
                Text(
                  l10n.settingsAboutVersion(appVersionLabel),
                  style: context.text.bodyMedium?.copyWith(
                    color: context.nx.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        FamilyNote(
          icon: Icons.info_outline,
          text: l10n.settingsAboutDisclaimer(
            config.appName,
            config.emergencyNumber,
          ),
        ),
        SettingsLinkTile(
          icon: Icons.policy_outlined,
          title: l10n.settingsAboutPrivacySummary,
          onTap: () => showPrivacySummarySheet(context),
        ),
      ],
    );
  }
}
