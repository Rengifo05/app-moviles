import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/components/nx_section.dart';
import 'package:nexo_familia/design_system/components/nx_state_views.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/check_ins/presentation/check_in_controller.dart';
import 'package:nexo_familia/features/check_ins/presentation/check_in_providers.dart';
import 'package:nexo_familia/features/check_ins/presentation/check_in_text.dart';
import 'package:nexo_familia/features/check_ins/presentation/check_in_widgets.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
import 'package:nexo_familia/features/service_status/presentation/service_status_providers.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Check-in a pantalla completa: "Estoy bien" o "Necesito ayuda", con
/// mensaje y ubicación opcionales.
///
/// Se guarda primero en el teléfono (bandeja de salida) y la pantalla dice
/// en todo momento lo que de verdad pasó: enviando, guardado sin conexión,
/// enviado (confirmado por el servidor) o rechazado.
class CheckInScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final familyId = ref.watch(activeFamilyIdProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.checkInTitle)),
      body: familyId == null
          ? NxMessageView(
              icon: Icons.group_outlined,
              title: l10n.checkInNoFamily,
              actionLabel: l10n.checkInSetUpFamily,
              onAction: () => context.go(AppRoutes.familySetup),
            )
          : _body(context, l10n, familyId),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n, String familyId) {
    final flow = ref.watch(checkInControllerProvider);
    final controller = ref.read(checkInControllerProvider.notifier);
    final pending = ref.watch(pendingCheckInsProvider(familyId)).value;
    final tracked = flow.submitted?.id;
    final others = [
      for (final item in pending ?? const <CheckIn>[])
        if (item.id != tracked) item,
    ];
    final now = ref.watch(clockProvider).now();

    // La acción principal queda siempre a la vista (uso con una mano), con
    // el error o la indicación justo encima para que se vean al tocarla.
    return Column(
      children: [
        Expanded(
          child: NxPageBody(
            // El resultado empieza arriba, no donde quedó el formulario.
            key: ValueKey(flow.isEditing),
            children: [
              if (flow.isEditing)
                ..._form(context, l10n, familyId, flow, controller)
              else
                CheckInResultView(flow: flow),
              if (others.isNotEmpty) ...[
                const SizedBox(height: NxSpace.md),
                NxSectionHeader(title: l10n.checkInPendingTitle),
                CheckInPendingList(
                  items: others.reversed.toList(),
                  now: now,
                  onRetry: controller.retry,
                  onDiscard: controller.discard,
                ),
              ],
            ],
          ),
        ),
        CheckInActionBar(
          children: [
            if (flow.failure case final failure?) ...[
              NxBanner(
                icon: Icons.error_outline,
                message: checkInFailureMessage(l10n, failure),
              ),
              const SizedBox(height: NxSpace.sm),
            ],
            if (flow.isEditing)
              ..._sendAction(context, l10n, flow, controller)
            else if (flow.phase == CheckInPhase.failed) ...[
              NxButton(
                key: const ValueKey('check-in-retry'),
                label: l10n.commonRetry,
                icon: Icons.refresh,
                onPressed: () => controller.retry(tracked!),
              ),
              const SizedBox(height: NxSpace.xs),
              NxButton(
                label: l10n.checkInDiscard,
                variant: NxButtonVariant.secondary,
                onPressed: () => controller.discard(tracked!),
              ),
            ] else
              NxButton(
                // Claves distintas: "Listo" no hereda el estado (resaltado,
                // foco) del botón "Enviar" que ocupaba su lugar.
                key: const ValueKey('check-in-done'),
                label: l10n.checkInDone,
                onPressed: _close,
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _sendAction(
    BuildContext context,
    AppLocalizations l10n,
    CheckInFlowState flow,
    CheckInController controller,
  ) {
    // Interruptor remoto (runbook de incidentes): se dice, no se oculta.
    final paused = !ref.watch(currentServiceFlagsProvider).checkInsEnabled;
    final canSend =
        !paused &&
        flow.phase == CheckInPhase.editing &&
        flow.kind != null &&
        _message.text.trim().length <= CheckInRules.maxMessageLength;
    return [
      if (paused) ...[
        NxBanner(
          icon: Icons.pause_circle_outline,
          message: l10n.checkInPausedByService(
            ref.watch(appConfigProvider).emergencyNumber,
          ),
        ),
        const SizedBox(height: NxSpace.sm),
      ],
      if (flow.kind == null && flow.failure == null) ...[
        Text(
          l10n.checkInChooseFirst,
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(color: context.nx.inkMuted),
        ),
        const SizedBox(height: NxSpace.xs),
      ],
      NxButton(
        key: const ValueKey('check-in-send'),
        label: switch (flow.phase) {
          CheckInPhase.locating => l10n.checkInLocating,
          CheckInPhase.saving => l10n.checkInSaving,
          _ => l10n.checkInSend,
        },
        icon: Icons.send_outlined,
        loading: flow.isBusy,
        onPressed: canSend ? () => controller.submit(_message.text) : null,
      ),
    ];
  }

  List<Widget> _form(
    BuildContext context,
    AppLocalizations l10n,
    String familyId,
    CheckInFlowState flow,
    CheckInController controller,
  ) {
    final c = context.nx;
    final offline = ref.watch(syncStatusProvider).value == SyncStatus.offline;
    final consent = ref.watch(myConsentProvider(familyId)).value;
    final editable = flow.phase == CheckInPhase.editing;
    final length = _message.text.trim().length;
    const max = CheckInRules.maxMessageLength;
    final tooLong = length > max;

    return [
      if (offline) ...[
        NxBanner(
          icon: Icons.cloud_off_outlined,
          message: l10n.checkInOfflineBanner,
        ),
        const SizedBox(height: NxSpace.md),
      ],
      Semantics(
        header: true,
        child: Text(l10n.checkInHeading, style: context.text.headlineSmall),
      ),
      const SizedBox(height: NxSpace.xs),
      Text(
        l10n.checkInIntro,
        style: context.text.bodyLarge?.copyWith(color: c.inkMuted),
      ),
      const SizedBox(height: NxSpace.lg),
      for (final kind in CheckInKind.values) ...[
        CheckInOptionTile(
          kind: kind,
          selected: flow.kind == kind,
          onTap: editable ? () => controller.selectKind(kind) : null,
        ),
        const SizedBox(height: NxSpace.sm),
      ],
      const SizedBox(height: NxSpace.xs),
      CheckInInfoLine(icon: Icons.info_outline, text: l10n.checkInSosExplainer),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: NxButton(
          label: l10n.checkInGoToSos,
          icon: Icons.sos_outlined,
          variant: NxButtonVariant.tertiary,
          expand: false,
          onPressed: () => context.pushReplacement(AppRoutes.sos),
        ),
      ),
      const SizedBox(height: NxSpace.sm),
      TextField(
        controller: _message,
        enabled: editable,
        minLines: 2,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) {
          setState(() {});
          controller.clearFailure();
        },
        decoration: InputDecoration(
          labelText: l10n.checkInMessageLabel,
          hintText: l10n.checkInMessageHint,
          alignLabelWithHint: true,
          errorText: tooLong ? l10n.checkInMessageTooLong(max) : null,
          counter: Semantics(
            label: l10n.checkInMessageRemaining((max - length).clamp(0, max)),
            excludeSemantics: true,
            child: Text(
              l10n.checkInMessageCounter(length, max),
              style: context.text.bodySmall?.copyWith(
                color: tooLong ? c.emergency : c.inkMuted,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: NxSpace.xs),
      if (consent case final consent? when consent.isSharing)
        _LocationSwitch(
          value: flow.includeLocation,
          approximate: consent.precision == LocationPrecision.approximate,
          onChanged: editable
              ? (value) => controller.setIncludeLocation(include: value)
              : null,
        )
      else if (consent != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: NxSpace.xs),
          child: CheckInInfoLine(
            icon: Icons.location_off_outlined,
            text: l10n.checkInLocationNotShared,
          ),
        ),
    ];
  }
}

class _LocationSwitch extends StatelessWidget {
  const new({
    required this.value,
    required this.approximate,
    required this.onChanged,
  });

  final bool value;
  final bool approximate;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final subtitle = switch ((value, approximate)) {
      (true, true) => l10n.checkInIncludeLocationApprox,
      (true, false) => l10n.checkInIncludeLocationExact,
      (false, true) => l10n.checkInIncludeLocationOffApprox,
      (false, false) => l10n.checkInIncludeLocationOffExact,
    };
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      // Con texto agrandado, el ícono le quitaría ancho al texto.
      secondary: checkInLargeText(context)
          ? null
          : const Icon(Icons.place_outlined),
      title: Text(l10n.checkInIncludeLocation),
      subtitle: Text(subtitle),
    );
  }
}
