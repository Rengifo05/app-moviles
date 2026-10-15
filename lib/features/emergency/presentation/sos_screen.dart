import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/components/nx_hold_button.dart';
import 'package:nexo_familia/design_system/components/nx_state_views.dart';
import 'package:nexo_familia/design_system/components/nx_status_pill.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/emergency/domain/emergency.dart';
import 'package:nexo_familia/features/emergency/presentation/sos_controller.dart';
import 'package:nexo_familia/features/emergency/presentation/sos_text.dart';
import 'package:nexo_familia/features/emergency/presentation/sos_widgets.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Pantalla SOS (modal a pantalla completa, desde Inicio y Mapa).
///
/// Flujo: mantener pulsado → cuenta atrás cancelable → alerta guardada en el
/// teléfono → línea de estados honesta (`docs/architecture/02-modelo-de-datos.md`).
/// "Llamar al 123" está siempre visible: la app no contacta a los servicios
/// de emergencia.
class SosScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(sosControllerProvider);
    // En iOS las regiones vivas no se anuncian solas: se anuncia cada
    // segundo de la cuenta atrás (Android lo hace con `liveRegion`).
    ref.listen(sosControllerProvider, (previous, next) {
      if (next is! SosCountingDown) return;
      if (previous is SosCountingDown &&
          previous.secondsLeft == next.secondsLeft) {
        return;
      }
      if (!MediaQuery.supportsAnnounceOf(context)) return;
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          l10n.emergencyCountdownAnnouncement(next.secondsLeft),
          Directionality.of(context),
        ),
      );
    });

    final (
      Widget body,
      Widget? primaryAction,
      bool prominentCall,
    ) = switch (state) {
      SosReady(:final notice) => (_ReadyView(notice: notice), null, false),
      SosCountingDown(:final secondsLeft, :final fraction) => (
        _CountdownView(secondsLeft: secondsLeft, fraction: fraction),
        _CancelButton(
          onPressed: () => ref.read(sosControllerProvider.notifier).cancel(),
        ),
        false,
      ),
      SosPreparing() => (const _PreparingView(), null, false),
      SosNotSaved() => (const _NotSavedView(), null, true),
      SosTracking(:final alert) => (
        _AlertView(alert: alert),
        null,
        switch (alert.status) {
          SosStatus.queued || SosStatus.failed => true,
          SosStatus.notified => alert.notifiedCount == 0,
          _ => false,
        },
      ),
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.emergencyScreenTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: body),
            _BottomActions(
              primary: primaryAction,
              call: SosCallButton(prominent: prominentCall),
            ),
          ],
        ),
      ),
    );
  }
}

/// Zona inferior fija: la acción principal del momento (p. ej. Cancelar) y
/// "Llamar al 123", que nunca se desplaza fuera de la vista.
class _BottomActions extends StatelessWidget {
  const new({required this.call, this.primary});

  final Widget? primary;
  final Widget call;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: context.nx.outline)),
    ),
    child: Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: NxSpace.maxContentWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            NxSpace.gutter,
            NxSpace.sm,
            NxSpace.gutter,
            NxSpace.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (primary case final primary?) ...[
                primary,
                const SizedBox(height: NxSpace.sm),
              ],
              call,
            ],
          ),
        ),
      ),
    ),
  );
}

/// Contenido desplazable con los márgenes y el ancho máximo de la app.
class _Body extends StatelessWidget {
  const new({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: NxSpace.maxContentWidth),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          NxSpace.gutter,
          NxSpace.xs,
          NxSpace.gutter,
          NxSpace.lg,
        ),
        children: children,
      ),
    ),
  );
}

class _ReadyView extends ConsumerWidget {
  const new({this.notice});

  final SosNotice? notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.nx;
    final familyId = ref.watch(activeFamilyIdProvider);
    final signedIn = ref.watch(currentUserProvider).value != null;
    final offline = ref.watch(syncStatusProvider).value == SyncStatus.offline;
    final consent = familyId == null
        ? null
        : ref.watch(myConsentProvider(familyId)).value;
    final canRaise = familyId != null && signedIn;

    return _Body(
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.emergencyReadyTitle,
            style: context.text.headlineSmall,
          ),
        ),
        const SizedBox(height: NxSpace.xs),
        Text(
          l10n.emergencyReadyBody,
          style: context.text.bodyLarge?.copyWith(color: c.inkMuted),
        ),
        if (notice case final notice?) ...[
          const SizedBox(height: NxSpace.md),
          NxBanner(
            icon: Icons.info_outline,
            tone: NxTone.info,
            message: switch (notice) {
              SosNotice.cancelled => l10n.emergencyCancelledNotice,
              SosNotice.discarded => l10n.emergencyDiscardedNotice,
            },
          ),
        ],
        if (offline && canRaise) ...[
          const SizedBox(height: NxSpace.md),
          NxBanner(
            icon: Icons.cloud_off_outlined,
            message: l10n.emergencyOfflineBanner,
          ),
        ],
        const SizedBox(height: NxSpace.xl),
        if (canRaise) ...[
          Center(
            child: NxHoldButton(
              label: l10n.emergencyHoldLabel,
              hint: l10n.emergencyHoldHint(SosRules.holdToActivate.inSeconds),
              // Explícito a propósito: la regla del dominio manda aunque
              // cambie el valor por defecto del componente.
              // ignore: avoid_redundant_argument_values
              holdDuration: SosRules.holdToActivate,
              onConfirmed: () =>
                  ref.read(sosControllerProvider.notifier).startCountdown(),
            ),
          ),
          const SizedBox(height: NxSpace.lg),
          Center(child: _LocationNote(consent: consent)),
        ] else
          NxBanner(
            icon: Icons.group_outlined,
            tone: NxTone.neutral,
            message: l10n.emergencyNoFamily,
          ),
      ],
    );
  }
}

/// Qué ubicación llevará la alerta, según el consentimiento propio.
class _LocationNote extends StatelessWidget {
  const new({required this.consent});

  final SharingConsent? consent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final consent = this.consent;
    if (consent == null) return const SizedBox.shrink();
    if (!consent.isSharing) {
      return NxStatusPill(
        icon: Icons.location_off_outlined,
        label: l10n.emergencyLocationNotShared,
      );
    }
    return NxStatusPill(
      icon: Icons.location_on_outlined,
      tone: NxTone.info,
      label: consent.precision == LocationPrecision.approximate
          ? l10n.emergencyLocationApproxIncluded
          : l10n.emergencyLocationIncluded,
    );
  }
}

class _CountdownView extends StatelessWidget {
  const new({required this.secondsLeft, required this.fraction});

  final int secondsLeft;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _Body(
      children: [
        const SizedBox(height: NxSpace.lg),
        ExcludeSemantics(
          child: Text(
            l10n.emergencyCountdownTitle,
            style: context.text.titleLarge,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: NxSpace.lg),
        Center(
          child: SosCountdownRing(
            secondsLeft: secondsLeft,
            fraction: fraction,
            semanticsLabel: l10n.emergencyCountdownAnnouncement(secondsLeft),
          ),
        ),
        const SizedBox(height: NxSpace.lg),
        Text(
          l10n.emergencyCountdownHint,
          style: context.text.bodyLarge?.copyWith(color: context.nx.inkMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// "Cancelar" de la cuenta atrás: grande y en la zona del pulgar.
class _CancelButton extends StatelessWidget {
  const new({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: NxSize.minTouchTarget + 16),
    child: NxButton(
      label: AppLocalizations.of(context).emergencyCountdownCancel,
      icon: Icons.close,
      onPressed: onPressed,
    ),
  );
}

class _PreparingView extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NxSpace.lg),
        child: Semantics(
          liveRegion: true,
          label: l10n.emergencyPreparing,
          excludeSemantics: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: NxSpace.md),
              Text(
                l10n.emergencyPreparing,
                style: context.text.titleMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotSavedView extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return NxMessageView(
      icon: Icons.error_outline,
      title: l10n.emergencyNotSavedTitle,
      body: l10n.emergencyNotSavedBody,
      actionLabel: l10n.commonRetry,
      onAction: () =>
          unawaited(ref.read(sosControllerProvider.notifier).retrySave()),
    );
  }
}

class _AlertView extends ConsumerStatefulWidget {
  const new({required this.alert});

  final EmergencyAlert alert;

  @override
  ConsumerState<_AlertView> createState() => _AlertViewState();
}

class _AlertViewState extends ConsumerState<_AlertView> {
  bool _busy = false;

  Future<void> _run(Future<VoidResult> Function() action) async {
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result case Err(:final failure)) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(sosFailureMessage(l10n, failure))));
    }
  }

  Future<void> _confirmEnd({required bool registered}) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          registered ? l10n.emergencyResolveTitle : l10n.emergencyDiscardTitle,
        ),
        content: Text(
          registered ? l10n.emergencyResolveBody : l10n.emergencyDiscardBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              registered ? l10n.emergencyKeepActive : l10n.emergencyKeepTrying,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: context.nx.emergency),
            child: Text(
              registered ? l10n.emergencyResolve : l10n.emergencyDiscard,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(ref.read(sosControllerProvider.notifier).end);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final alert = widget.alert;
    final status = alert.status;
    final number = ref.watch(appConfigProvider).emergencyNumber;
    final members = ref.watch(familyMembersProvider(alert.familyId)).value;
    String nameOf(String uid) {
      final name = members
          ?.where((m) => m.uid == uid)
          .firstOrNull
          ?.displayName
          .trim();
      return name == null || name.isEmpty ? l10n.emergencyUnnamedMember : name;
    }

    final location = switch (alert.location) {
      null => l10n.emergencyWithoutLocation,
      _ when (alert.locationAccuracyMeters ?? 0) >= 1000 =>
        l10n.emergencyWithApproxLocation,
      _ => l10n.emergencyWithLocation,
    };
    final registered = alert.delivery == SosDelivery.sent;
    final canRetry = status == SosStatus.queued || status == SosStatus.failed;
    final canEnd = status != SosStatus.resolved && status != SosStatus.sending;

    return _Body(
      children: [
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(sosTitle(l10n, alert), style: context.text.headlineSmall),
        ),
        const SizedBox(height: NxSpace.xxs),
        _AlertMeta(
          created: l10n.emergencyCreatedAt(alert.createdAt.toLocal()),
          location: location,
          hasLocation: alert.location != null,
        ),
        const SizedBox(height: NxSpace.lg),
        SosStepList(
          steps: sosSteps(l10n, alert, emergencyNumber: number, nameOf: nameOf),
        ),
        if (canRetry) ...[
          const SizedBox(height: NxSpace.lg),
          NxButton(
            label: l10n.commonRetry,
            icon: Icons.refresh,
            variant: NxButtonVariant.secondary,
            loading: _busy,
            onPressed: () =>
                _run(ref.read(sosControllerProvider.notifier).retry),
          ),
        ],
        if (canEnd) ...[
          const SizedBox(height: NxSpace.lg),
          NxButton(
            label: registered ? l10n.emergencyResolve : l10n.emergencyDiscard,
            variant: NxButtonVariant.tertiary,
            onPressed: _busy ? null : () => _confirmEnd(registered: registered),
          ),
        ],
        if (status == SosStatus.resolved) ...[
          const SizedBox(height: NxSpace.lg),
          NxButton(
            label: l10n.commonClose,
            variant: NxButtonVariant.secondary,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
    );
  }
}

/// Hora de creación y si la alerta lleva ubicación (sin coordenadas).
class _AlertMeta extends StatelessWidget {
  const new({
    required this.created,
    required this.location,
    required this.hasLocation,
  });

  final String created;
  final String location;
  final bool hasLocation;

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    final style = context.text.bodyMedium?.copyWith(color: c.inkMuted);
    return Wrap(
      spacing: NxSpace.md,
      runSpacing: NxSpace.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(created, style: style),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasLocation
                  ? Icons.location_on_outlined
                  : Icons.location_off_outlined,
              size: nxScaledIcon(context, NxSize.iconSm),
              color: c.inkMuted,
            ),
            const SizedBox(width: NxSpace.xxs),
            Flexible(child: Text(location, style: style)),
          ],
        ),
      ],
    );
  }
}
