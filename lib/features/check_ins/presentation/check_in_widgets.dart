import 'package:flutter/material.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/components/nx_status_pill.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_colors.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/check_ins/presentation/check_in_controller.dart';
import 'package:nexo_familia/features/check_ins/presentation/check_in_text.dart';
import 'package:nexo_familia/features/common/presentation/relative_time.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Ícono de cada tipo de check-in (nunca un emoji).
IconData checkInKindIcon(CheckInKind kind) => switch (kind) {
  CheckInKind.ok => Icons.check_circle_outline,
  CheckInKind.needHelp => Icons.front_hand_outlined,
};

/// Tono de cada tipo: positivo y ámbar. "Necesito ayuda" nunca usa el rojo,
/// reservado al SOS.
NxTone checkInKindTone(CheckInKind kind) => switch (kind) {
  CheckInKind.ok => NxTone.positive,
  CheckInKind.needHelp => NxTone.warning,
};

/// Texto agrandado (≥ 130 %): los íconos de apoyo se ponen en línea con el
/// título para dejarle al texto todo el ancho.
bool checkInLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(NxSize.iconMd) >=
    NxSize.iconMd * 1.3;

({Color accent, Color container, Color onContainer}) _toneColors(
  NxColors c,
  CheckInKind kind,
) => switch (kind) {
  CheckInKind.ok => (
    accent: c.positive,
    container: c.positiveContainer,
    onContainer: c.onPositiveContainer,
  ),
  CheckInKind.needHelp => (
    accent: c.warning,
    container: c.warningContainer,
    onContainer: c.onWarningContainer,
  ),
};

/// Opción grande y seleccionable ("Estoy bien" / "Necesito ayuda"). Las dos
/// forman un grupo de selección única para los lectores de pantalla.
class CheckInOptionTile extends StatelessWidget {
  const new({
    required this.kind,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final CheckInKind kind;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    final l10n = AppLocalizations.of(context);
    final tone = _toneColors(c, kind);
    final hint = switch (kind) {
      CheckInKind.ok => l10n.checkInOptionOkHint,
      CheckInKind.needHelp => l10n.checkInOptionHelpHint,
    };
    final foreground = selected ? tone.onContainer : c.ink;
    final muted = selected ? tone.onContainer : c.inkMuted;
    final large = checkInLargeText(context);
    final kindIcon = Icon(
      checkInKindIcon(kind),
      color: selected ? tone.onContainer : tone.accent,
      size: nxScaledIcon(context, large ? NxSize.iconMd : NxSize.iconLg),
    );
    final title = Text(
      checkInKindLabel(l10n, kind),
      style: context.text.titleMedium?.copyWith(color: foreground),
    );
    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        child: Material(
          color: selected ? tone.container : c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: NxRadius.lgAll,
            side: BorderSide(
              color: selected ? tone.accent : c.outlineStrong,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: NxSize.minTouchTarget + NxSpace.lg,
              ),
              child: Padding(
                padding: const EdgeInsets.all(NxSpace.md),
                child: Row(
                  children: [
                    if (!large) ...[
                      kindIcon,
                      const SizedBox(width: NxSpace.md),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (large)
                            Row(
                              children: [
                                kindIcon,
                                const SizedBox(width: NxSpace.xs),
                                Flexible(child: title),
                              ],
                            )
                          else
                            title,
                          const SizedBox(height: NxSpace.xxs),
                          Text(
                            hint,
                            style: context.text.bodyMedium?.copyWith(
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: NxSpace.sm),
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected ? tone.onContainer : c.inkMuted,
                      size: nxScaledIcon(context, NxSize.iconMd),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Estado del check-in recién enviado. Solo dice "Enviado a tu familia"
/// cuando la bandeja de salida confirmó la entrega, y aclara que eso no
/// significa que alguien ya lo haya visto. Las acciones (Listo, Reintentar,
/// Descartar) van en la barra inferior de la pantalla.
class CheckInResultView extends StatelessWidget {
  const new({required this.flow, super.key});

  final CheckInFlowState flow;

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    final l10n = AppLocalizations.of(context);
    final checkIn = flow.submitted!;
    final iconSize = nxScaledIcon(context, NxSize.iconLg + 8);
    final (Widget visual, String title, String body) = switch (flow.phase) {
      CheckInPhase.delivered => (
        Icon(Icons.task_alt, color: c.positive, size: iconSize),
        l10n.checkInDeliveredTitle,
        l10n.checkInDeliveredBody,
      ),
      CheckInPhase.failed => (
        Icon(Icons.error_outline, color: c.emergency, size: iconSize),
        l10n.checkInFailedTitle,
        l10n.checkInFailedBody,
      ),
      CheckInPhase.queued => (
        Icon(Icons.schedule_send_outlined, color: c.warning, size: iconSize),
        l10n.checkInQueuedTitle,
        l10n.checkInQueuedBody,
      ),
      CheckInPhase.sending ||
      CheckInPhase.editing ||
      CheckInPhase.locating ||
      CheckInPhase.saving => (
        SizedBox.square(
          dimension: iconSize,
          child: Padding(
            padding: const EdgeInsets.all(NxSpace.xxs),
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: c.secondary,
            ),
          ),
        ),
        l10n.checkInSendingTitle,
        l10n.checkInSendingBody,
      ),
    };

    final location = switch ((checkIn.location, flow.locationOmitted)) {
      (_?, _) => (
        Icons.place_outlined,
        flow.locationApproximate
            ? l10n.checkInWithApproxLocation
            : l10n.checkInWithLocation,
      ),
      (null, true) => (
        Icons.location_off_outlined,
        l10n.checkInLocationOmitted,
      ),
      (null, false) => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: NxSpace.lg),
        // Una sola región que se anuncia al cambiar de estado.
        Semantics(
          container: true,
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: visual),
              const SizedBox(height: NxSpace.md),
              Semantics(
                header: true,
                child: Text(title, style: context.text.headlineSmall),
              ),
              const SizedBox(height: NxSpace.xs),
              Text(
                body,
                style: context.text.bodyLarge?.copyWith(color: c.inkMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: NxSpace.lg),
        Divider(color: c.outline),
        const SizedBox(height: NxSpace.md),
        NxStatusPill(
          label: checkInKindLabel(l10n, checkIn.kind),
          icon: checkInKindIcon(checkIn.kind),
          tone: checkInKindTone(checkIn.kind),
        ),
        if (checkIn.message case final message?) ...[
          const SizedBox(height: NxSpace.sm),
          Text(message, style: context.text.bodyLarge),
        ],
        if (location case (final icon, final text)) ...[
          const SizedBox(height: NxSpace.sm),
          CheckInInfoLine(icon: icon, text: text),
        ],
      ],
    );
  }
}

/// Lista breve de check-ins propios aún no confirmados por el servidor.
class CheckInPendingList extends StatelessWidget {
  const new({
    required this.items,
    required this.now,
    required this.onRetry,
    required this.onDiscard,
    super.key,
  });

  final List<CheckIn> items;
  final DateTime now;
  final ValueChanged<String> onRetry;
  final ValueChanged<String> onDiscard;

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, item) in items.indexed) ...[
          if (index > 0) Divider(color: c.outline),
          _PendingRow(
            item: item,
            now: now,
            onRetry: () => onRetry(item.id),
            onDiscard: () => onDiscard(item.id),
          ),
        ],
      ],
    );
  }
}

class _PendingRow extends StatelessWidget {
  const new({
    required this.item,
    required this.now,
    required this.onRetry,
    required this.onDiscard,
  });

  final CheckIn item;
  final DateTime now;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    final l10n = AppLocalizations.of(context);
    final failed = item.delivery == DeliveryState.failed;
    final tone = _toneColors(c, item.kind);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NxSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            checkInKindIcon(item.kind),
            color: tone.accent,
            size: nxScaledIcon(context, NxSize.iconMd),
          ),
          const SizedBox(width: NxSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Un solo anuncio por check-in; los botones van aparte.
                MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        checkInKindLabel(l10n, item.kind),
                        style: context.text.titleSmall,
                      ),
                      if (item.message case final message?)
                        Text(
                          message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium?.copyWith(
                            color: c.inkMuted,
                          ),
                        ),
                      const SizedBox(height: NxSpace.xs),
                      Wrap(
                        spacing: NxSpace.xs,
                        runSpacing: NxSpace.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (failed)
                            NxStatusPill(
                              label: l10n.checkInStatusFailed,
                              icon: Icons.error_outline,
                              tone: NxTone.emergency,
                            )
                          else
                            NxStatusPill(
                              label: l10n.checkInStatusPending,
                              icon: Icons.schedule,
                            ),
                          Text(
                            l10n.checkInSavedAt(
                              relativeTime(l10n, item.createdAt, now),
                            ),
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (failed) ...[
                  const SizedBox(height: NxSpace.sm),
                  Wrap(
                    spacing: NxSpace.xs,
                    runSpacing: NxSpace.xs,
                    children: [
                      NxButton(
                        label: l10n.commonRetry,
                        icon: Icons.refresh,
                        variant: NxButtonVariant.secondary,
                        expand: false,
                        onPressed: onRetry,
                      ),
                      NxButton(
                        label: l10n.checkInDiscard,
                        variant: NxButtonVariant.tertiary,
                        expand: false,
                        onPressed: onDiscard,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra inferior fija con la acción principal. Respeta el área segura y el
/// ancho máximo del contenido; un borde fino la separa de lo que se
/// desplaza por debajo (sin sombra).
class CheckInActionBar extends StatelessWidget {
  const new({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(top: BorderSide(color: c.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: NxSpace.maxContentWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                NxSpace.gutter,
                NxSpace.sm,
                NxSpace.gutter,
                NxSpace.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Línea con ícono y texto secundario.
class CheckInInfoLine extends StatelessWidget {
  const new({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.nx;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: c.inkMuted,
          size: nxScaledIcon(context, NxSize.iconSm),
        ),
        const SizedBox(width: NxSpace.xs),
        Expanded(
          child: Text(
            text,
            style: context.text.bodyMedium?.copyWith(color: c.inkMuted),
          ),
        ),
      ],
    );
  }
}
