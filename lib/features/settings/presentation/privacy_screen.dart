import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/components/nx_section.dart';
import 'package:nexo_familia/design_system/components/nx_state_views.dart';
import 'package:nexo_familia/design_system/components/nx_status_pill.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_actions.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/family/presentation/family_text.dart';
import 'package:nexo_familia/features/family/presentation/family_widgets.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
import 'package:nexo_familia/features/settings/presentation/privacy_actions.dart';
import 'package:nexo_familia/features/settings/presentation/settings_text.dart';
import 'package:nexo_familia/features/settings/presentation/settings_widgets.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Centro de privacidad: el **único** lugar donde cada persona decide si
/// comparte su ubicación con la familia activa y con qué precisión (amenaza
/// 9). También muestra quién puede verla, qué se guarda y cuánto tiempo, y
/// permite salir de la familia.
///
/// Ningún cambio se confirma antes de que el servidor lo acepte: si falla
/// (p. ej. sin conexión), se dice que no se aplicó y se ofrece reintentar.
class PrivacyScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final familyId = ref.watch(activeFamilyIdProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsPrivacyTitle)),
      body: SafeArea(
        top: false,
        child: familyId == null
            ? NxMessageView(
                icon: Icons.groups_outlined,
                title: l10n.settingsPrivacyNoFamily,
              )
            // Cambiar de familia descarta los mensajes de la anterior.
            : _PrivacyBody(key: ValueKey(familyId), familyId: familyId),
      ),
    );
  }
}

class _PrivacyBody extends ConsumerStatefulWidget {
  const new({required this.familyId, super.key});

  final String familyId;

  @override
  ConsumerState<_PrivacyBody> createState() => _PrivacyBodyState();
}

class _PrivacyBodyState extends ConsumerState<_PrivacyBody> {
  AppLifecycleListener? _lifecycle;

  /// Cambio en curso; desactiva los demás controles.
  ConsentChange? _busy;
  bool _leaving = false;

  /// Resultado del último cambio y cómo repetirlo si falló.
  ConsentOutcome? _outcome;
  Future<void> Function()? _retry;

  @override
  void initState() {
    super.initState();
    // Al volver de los ajustes del sistema el permiso puede haber cambiado.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(deviceLocationPermissionProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  String get _familyId => widget.familyId;

  FamilyGroup? get _family => ref
      .read(myFamiliesProvider)
      .value
      ?.where((f) => f.id == _familyId)
      .firstOrNull;

  List<FamilyMember>? _audience() {
    final myUid = ref.read(currentUserProvider).value?.uid;
    return ref
        .read(familyMembersProvider(_familyId))
        .value
        ?.where((m) => m.uid != myUid)
        .toList();
  }

  Future<void> _run(
    ConsentChange change,
    Future<ConsentOutcome> Function() action,
  ) async {
    if (_busy != null) return;
    setState(() {
      _busy = change;
      _outcome = null;
      _retry = null;
    });
    final ConsentOutcome outcome;
    try {
      outcome = await action();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
    if (!mounted) return;
    if (change == ConsentChange.share) {
      ref.invalidate(deviceLocationPermissionProvider);
    }
    setState(() {
      _outcome = outcome;
      _retry = outcome.applied ? null : () => _run(change, action);
    });
  }

  Future<void> _share(SharingConsent consent) async {
    if (_busy != null) return;
    // Primero la explicación: qué se comparte, con quién y que se puede
    // pausar. Sin aceptarla no se pide el permiso ni se guarda nada.
    final accepted = await showShareExplanation(
      context,
      familyName: _family?.name,
      audience: _audience(),
      precision: consent.precision,
    );
    if (!accepted || !mounted) return;
    final actions = ref.read(privacyActionsProvider);
    await _run(ConsentChange.share, () => actions.share(consent));
  }

  Future<void> _pause(SharingConsent consent) {
    final actions = ref.read(privacyActionsProvider);
    return _run(ConsentChange.pause, () => actions.pause(consent));
  }

  Future<void> _keepPaused(SharingConsent consent) {
    final actions = ref.read(privacyActionsProvider);
    return _run(ConsentChange.keepPaused, () => actions.keepPaused(consent));
  }

  Future<void> _setPrecision(
    SharingConsent consent,
    LocationPrecision precision,
  ) async {
    if (precision == consent.precision) return;
    final actions = ref.read(privacyActionsProvider);
    await _run(
      ConsentChange.precision,
      () => actions.setPrecision(consent, precision),
    );
  }

  Future<void> _openSystemSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    final message = AppLocalizations.of(context)
        .settingsSystemSettingsNotOpened;
    final opened = await ref
        .read(deviceLocationServiceProvider)
        .openSystemSettings();
    if (!opened) messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _leave() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final family = _family;
    final name = family?.name ?? l10n.navFamily;
    final members = ref.read(familyMembersProvider(_familyId)).value;
    final isLast = members != null && members.length <= 1;
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
    final result = await ref.read(familyActionsProvider).leave(_familyId);
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
    final consentValue = ref.watch(myConsentProvider(_familyId));
    final consent = consentValue.value;
    final offline = ref.watch(syncStatusProvider).value == SyncStatus.offline;
    final familyName = ref
        .watch(myFamiliesProvider)
        .value
        ?.where((f) => f.id == _familyId)
        .firstOrNull
        ?.name
        .trim();
    final permission = (consent?.isSharing ?? false)
        ? ref.watch(deviceLocationPermissionProvider).value
        : null;

    return NxPageBody(
      children: [
        if (offline) ...[
          const SizedBox(height: NxSpace.xs),
          NxBanner(
            icon: Icons.cloud_off_outlined,
            message: l10n.commonOfflineBanner,
          ),
        ],
        const SizedBox(height: NxSpace.sm),
        Semantics(
          header: true,
          child: Text(
            familyName == null || familyName.isEmpty
                ? l10n.settingsPrivacyHeadingGeneric
                : l10n.settingsPrivacyHeading(familyName),
            style: context.text.headlineSmall,
          ),
        ),
        const SizedBox(height: NxSpace.xs),
        Text(
          l10n.settingsPrivacyIntro,
          style: context.text.bodyLarge?.copyWith(color: context.nx.inkMuted),
        ),
        const SizedBox(height: NxSpace.lg),
        if (consent != null) ...[
          _ConsentState(
            consent: consent,
            busy: _busy,
            onShare: () => _share(consent),
            onPause: () => _pause(consent),
            onKeepPaused: () => _keepPaused(consent),
          ),
          ..._feedback(l10n, consent, permission),
          NxSectionHeader(title: l10n.settingsPrivacyPrecisionTitle),
          _PrecisionChoice(
            value: consent.precision,
            enabled: _busy == null,
            busy: _busy == ConsentChange.precision,
            onChanged: (p) => _setPrecision(consent, p),
          ),
        ] else if (consentValue.hasError)
          NxBanner(
            icon: Icons.error_outline,
            tone: NxTone.neutral,
            message: l10n.settingsPrivacyStateError,
            actionLabel: l10n.commonRetry,
            onAction: () => ref.invalidate(myConsentProvider(_familyId)),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NxSpace.lg),
            child: NxLoadingView(label: l10n.commonLoading),
          ),
        NxSectionHeader(title: l10n.settingsPrivacyAudienceTitle),
        _Audience(familyId: _familyId, sharing: consent?.isSharing ?? false),
        NxSectionHeader(title: l10n.settingsPrivacyDataTitle),
        FamilyNote(
          icon: Icons.location_on_outlined,
          text: l10n.settingsPrivacyDataLocation,
        ),
        FamilyNote(
          icon: Icons.event_note_outlined,
          text: l10n.settingsPrivacyDataEvents,
        ),
        FamilyNote(
          icon: Icons.notification_important_outlined,
          text: l10n.settingsPrivacyDataSos,
        ),
        FamilyNote(
          icon: Icons.history_outlined,
          text: l10n.settingsPrivacyDataAudit,
        ),
        FamilyNote(
          icon: Icons.lock_outline,
          text: l10n.settingsPrivacyDataEncryption,
        ),
        SettingsLinkTile(
          icon: Icons.policy_outlined,
          title: l10n.settingsAboutPrivacySummary,
          onTap: () => showPrivacySummarySheet(context),
        ),
        const SizedBox(height: NxSpace.xl),
        NxButton(
          label: l10n.settingsPrivacyLeave,
          icon: Icons.logout,
          variant: NxButtonVariant.destructive,
          loading: _leaving,
          onPressed: _busy == null ? _leave : null,
        ),
      ],
    );
  }

  /// Avisos bajo el estado: el resultado del último cambio y, si se
  /// comparte, el permiso del sistema que falta.
  List<Widget> _feedback(
    AppLocalizations l10n,
    SharingConsent consent,
    DeviceLocationPermission? permission,
  ) {
    final outcome = _outcome;
    final widgets = <Widget?>[
      if (outcome != null)
        switch (outcome.result) {
          Ok() => switch (consentSuccessMessage(l10n, outcome, consent)) {
            final message? => NxBanner(
              icon: Icons.check_circle_outline,
              tone: NxTone.positive,
              message: message,
              actionLabel:
                  outcome.change == ConsentChange.share && consent.isSharing
                  ? l10n.settingsPrivacyGoToMap
                  : null,
              onAction: () => context.go(AppRoutes.map),
            ),
            null => null,
          },
          Err(:final failure) => NxBanner(
            icon: Icons.error_outline,
            message: consentFailureMessage(l10n, outcome.change, failure),
            actionLabel: failure.isTransient ? l10n.commonRetry : null,
            onAction: _retry == null ? null : () => unawaited(_retry!()),
          ),
        },
      if (consent.isSharing &&
          permission == DeviceLocationPermission.serviceDisabled)
        NxBanner(
          icon: Icons.location_disabled_outlined,
          message: l10n.settingsPrivacyServiceDisabled,
          actionLabel: l10n.commonOpenSettings,
          onAction: _openSystemSettings,
        )
      else if (consent.isSharing && permission != null && !permission.isGranted)
        NxBanner(
          icon: Icons.location_disabled_outlined,
          message: l10n.settingsPrivacyPermissionMissing,
          actionLabel: l10n.commonOpenSettings,
          onAction: _openSystemSettings,
        ),
    ].nonNulls.toList();
    return [
      for (final widget in widgets) ...[
        const SizedBox(height: NxSpace.sm),
        widget,
      ],
    ];
  }
}

/// Estado de mi compartición con su acción principal: compartir, pausar o
/// (si aún no decide) no compartir por ahora.
class _ConsentState extends StatelessWidget {
  const new({
    required this.consent,
    required this.busy,
    required this.onShare,
    required this.onPause,
    required this.onKeepPaused,
  });

  final SharingConsent consent;
  final ConsentChange? busy;
  final VoidCallback onShare;
  final VoidCallback onPause;
  final VoidCallback onKeepPaused;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.nx;
    final idle = busy == null;
    final (icon, color) = switch (consent.state) {
      SharingState.sharing => (Icons.location_on_outlined, c.positive),
      SharingState.paused => (Icons.pause_circle_outline, c.inkMuted),
      SharingState.notConfigured => (Icons.location_off_outlined, c.inkMuted),
    };
    return NxSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Con texto agrandado, el ícono le quitaría ancho al texto
                // (el estado ya va en el título).
                if (!settingsLargeText(context)) ...[
                  Icon(icon, color: color, size: nxScaledIcon(context, 28)),
                  const SizedBox(width: NxSpace.sm),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        consentStateTitle(l10n, consent),
                        style: context.text.titleMedium,
                      ),
                      const SizedBox(height: NxSpace.xxs),
                      Text(
                        consentStateDetail(l10n, consent),
                        style: context.text.bodyMedium?.copyWith(
                          color: c.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: NxSpace.md),
          if (consent.isSharing)
            NxButton(
              label: l10n.settingsPrivacyPause,
              icon: Icons.pause,
              variant: NxButtonVariant.secondary,
              loading: busy == ConsentChange.pause,
              onPressed: idle ? onPause : null,
            )
          else ...[
            NxButton(
              label: l10n.settingsPrivacyShare,
              icon: Icons.location_on_outlined,
              loading: busy == ConsentChange.share,
              onPressed: idle ? onShare : null,
            ),
            if (consent.state == SharingState.notConfigured) ...[
              const SizedBox(height: NxSpace.xs),
              NxButton(
                label: l10n.settingsPrivacyKeepPaused,
                variant: NxButtonVariant.tertiary,
                loading: busy == ConsentChange.keepPaused,
                onPressed: idle ? onKeepPaused : null,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PrecisionChoice extends StatelessWidget {
  const new({
    required this.value,
    required this.enabled,
    required this.busy,
    required this.onChanged,
  });

  final LocationPrecision value;
  final bool enabled;
  final bool busy;
  final ValueChanged<LocationPrecision> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = context.text.bodyMedium?.copyWith(color: context.nx.inkMuted);
    Widget option(LocationPrecision precision, String title, String detail) =>
        RadioListTile<LocationPrecision>(
          value: precision,
          enabled: enabled,
          contentPadding: EdgeInsets.zero,
          title: Text(title, style: context.text.titleSmall),
          subtitle: Text(detail, style: muted),
        );
    return Semantics(
      liveRegion: busy,
      child: RadioGroup<LocationPrecision>(
        groupValue: value,
        onChanged: (next) {
          if (next != null && enabled) onChanged(next);
        },
        child: Column(
          children: [
            option(
              LocationPrecision.exact,
              l10n.settingsPrivacyPrecisionExact,
              l10n.settingsPrivacyPrecisionExactDetail,
            ),
            option(
              LocationPrecision.approximate,
              l10n.settingsPrivacyPrecisionApprox,
              l10n.settingsPrivacyPrecisionApproxDetail,
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: NxSpace.xs),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Quién puede ver (o vería) mi ubicación: los demás integrantes.
class _Audience extends ConsumerWidget {
  const new({required this.familyId, required this.sharing});

  final String familyId;
  final bool sharing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final myUid = ref.watch(currentUserProvider).value?.uid;
    final members = ref.watch(familyMembersProvider(familyId));
    final muted = context.text.bodyMedium?.copyWith(color: context.nx.inkMuted);
    final others = members.value?.where((m) => m.uid != myUid).toList();
    if (others == null) {
      return members.hasError
          ? Text(l10n.settingsPrivacyAudienceError, style: muted)
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: NxSpace.md),
              child: NxLoadingView(label: l10n.commonLoading),
            );
    }
    if (others.isEmpty) {
      return Text(l10n.settingsPrivacyAudienceEmpty, style: muted);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sharing
              ? l10n.settingsPrivacyAudienceSharing
              : l10n.settingsPrivacyAudienceNotSharing,
          style: muted,
        ),
        const SizedBox(height: NxSpace.xxs),
        for (final member in others) AudienceMemberRow(member: member),
      ],
    );
  }
}
