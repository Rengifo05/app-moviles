import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_status_pill.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/service_status/domain/service_status.dart';
import 'package:nexo_familia/features/service_status/presentation/service_status_providers.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Avisos del equipo en Inicio: un problema del servicio y la
/// recomendación de actualizar. Sin avisos no ocupa espacio.
class ServiceNoticeBanner extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final flags = ref.watch(currentServiceFlagsProvider);
    final number = ref.watch(appConfigProvider).emergencyNumber;
    final banners = [
      if (flags.notice case final notice?)
        NxBanner(
          icon: Icons.report_problem_outlined,
          message: switch (notice) {
            ServiceNotice.pushDegraded => l10n.serviceNoticePushDegraded(
              number,
            ),
            ServiceNotice.serviceDegraded => l10n.serviceNoticeDegraded,
          },
        ),
      if (flags.updateRecommended(ref.watch(appBuildNumberProvider)))
        NxBanner(
          icon: Icons.system_update_outlined,
          tone: NxTone.info,
          message: l10n.serviceUpdateRecommended,
        ),
    ];
    if (banners.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final banner in banners) ...[
          banner,
          const SizedBox(height: NxSpace.sm),
        ],
      ],
    );
  }
}
