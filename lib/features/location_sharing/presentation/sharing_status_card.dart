import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/design_system/components/nx_section.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Estado de **mi** compartición de ubicación en la familia activa, con
/// acceso a Privacidad para pausarla o cambiarla (indicador persistente de
/// la amenaza 9: quién puede ver mi ubicación).
///
/// Pensada para Inicio. No muestra nada si no hay familia activa.
class SharingStatusCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familyId = ref.watch(activeFamilyIdProvider);
    if (familyId == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final c = context.nx;
    final consent = ref.watch(myConsentProvider(familyId));
    final myUid = ref.watch(currentUserProvider).value?.uid;
    final others = ref
        .watch(familyMembersProvider(familyId))
        .value
        ?.where((m) => m.uid != myUid)
        .length;

    final content = switch (consent) {
      AsyncValue(value: final mine?) => switch (mine.state) {
        SharingState.sharing => (
          icon: Icons.location_on_outlined,
          color: c.positive,
          title: mine.precision == LocationPrecision.approximate
              ? l10n.locationCardSharingApprox
              : l10n.locationCardSharingExact,
          detail: others == null ? null : l10n.locationCardAudience(others),
          action: l10n.locationCardManage,
        ),
        SharingState.paused => (
          icon: Icons.pause_circle_outline,
          color: c.inkMuted,
          title: l10n.locationCardPaused,
          detail: l10n.locationCardPausedDetail,
          action: l10n.locationCardConfigure,
        ),
        SharingState.notConfigured => (
          icon: Icons.location_off_outlined,
          color: c.inkMuted,
          title: l10n.locationCardNotConfigured,
          detail: l10n.locationCardNotConfiguredDetail,
          action: l10n.locationCardConfigure,
        ),
      },
      AsyncError() => (
        icon: Icons.error_outline,
        color: c.inkMuted,
        title: l10n.locationCardError,
        detail: null,
        action: l10n.locationCardConfigure,
      ),
      _ => (
        icon: Icons.location_searching,
        color: c.inkMuted,
        title: l10n.commonLoading,
        detail: null,
        action: null,
      ),
    };

    return NxSurface(
      padding: const EdgeInsets.fromLTRB(
        NxSpace.md,
        NxSpace.md,
        NxSpace.xs,
        NxSpace.xs,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: NxSpace.xs),
            child: MergeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    content.icon,
                    color: content.color,
                    size: nxScaledIcon(context, NxSize.iconMd),
                  ),
                  const SizedBox(width: NxSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(content.title, style: context.text.titleSmall),
                        if (content.detail case final detail?) ...[
                          const SizedBox(height: NxSpace.xxs),
                          Text(
                            detail,
                            style: context.text.bodyMedium?.copyWith(
                              color: c.inkMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (content.action case final action?)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => context.go(AppRoutes.privacy),
                style: TextButton.styleFrom(
                  foregroundColor: c.secondary,
                  minimumSize: const Size(
                    NxSize.minTouchTarget,
                    NxSize.minTouchTarget,
                  ),
                  textStyle: context.text.labelLarge,
                ),
                child: Text(action),
              ),
            )
          else
            const SizedBox(height: NxSpace.xs),
        ],
      ),
    );
  }
}
