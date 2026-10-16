import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/common/presentation/relative_time.dart';
import 'package:nexo_familia/features/emergency/domain/emergency.dart';
import 'package:nexo_familia/features/emergency/presentation/emergency_providers.dart';
import 'package:nexo_familia/features/emergency/presentation/sos_text.dart';
import 'package:nexo_familia/features/emergency/presentation/sos_view_logic.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/family/presentation/family_widgets.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Alertas SOS activas de **otros** integrantes de la familia activa, para
/// Inicio. Cada una dice quién la envió, hace cuánto y si incluye ubicación
/// (nunca coordenadas), con "Lo vi" para confirmarla de forma explícita.
///
/// No muestra nada si no hay alertas activas (ni mientras cargan o si la
/// lectura falla: Inicio no debe romperse por esto).
class ActiveAlertsBanner extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familyId = ref.watch(activeFamilyIdProvider);
    if (familyId == null) return const SizedBox.shrink();
    final uid = ref.watch(currentUserProvider).value?.uid;
    final alerts = othersActiveAlerts(
      ref.watch(emergencyAlertsProvider(familyId)).value ?? const [],
      uid,
    );
    if (alerts.isEmpty || uid == null) return const SizedBox.shrink();
    final members = ref.watch(familyMembersProvider(familyId)).value;
    final l10n = AppLocalizations.of(context);
    String nameOf(String id) {
      final name = members
          ?.where((m) => m.uid == id)
          .firstOrNull
          ?.displayName
          .trim();
      return name == null || name.isEmpty ? l10n.emergencyUnnamedMember : name;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, alert) in alerts.indexed) ...[
          if (index > 0) const SizedBox(height: NxSpace.sm),
          _AlertCard(
            key: ValueKey(alert.id),
            alert: alert,
            authorName: nameOf(alert.uid),
            acknowledged: alert.acknowledgedBy(uid),
          ),
        ],
      ],
    );
  }
}

class _AlertCard extends ConsumerStatefulWidget {
  const new({
    required this.alert,
    required this.authorName,
    required this.acknowledged,
    super.key,
  });

  final EmergencyAlert alert;
  final String authorName;
  final bool acknowledged;

  @override
  ConsumerState<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends ConsumerState<_AlertCard> {
  bool _sending = false;

  /// El servidor ya confirmó la escritura (commit con `Ok`) aunque la caché
  /// aún no la refleje: se muestra como hecha y no se repite.
  bool _confirmed = false;

  Future<void> _acknowledge() async {
    setState(() => _sending = true);
    final alert = widget.alert;
    final result = await ref
        .read(emergencyRepositoryProvider)
        .acknowledge(alert.familyId, alert.id);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _confirmed = result.isOk;
    });
    if (result case Err(:final failure)) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(sosFailureMessage(l10n, failure))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.nx;
    final alert = widget.alert;
    final ink = c.onEmergencyContainer;
    final detailStyle = context.text.bodyMedium?.copyWith(color: ink);
    final acknowledged = widget.acknowledged || _confirmed;

    return Material(
      color: c.emergencyContainer,
      shape: RoundedRectangleBorder(
        borderRadius: NxRadius.lgAll,
        side: BorderSide(color: c.emergency.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(NxSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.sos,
                color: ink,
                size: nxScaledIcon(context, NxSize.iconMd),
              ),
            ),
            const SizedBox(width: NxSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MergeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            l10n.emergencyBannerTitle(widget.authorName),
                            style: context.text.titleMedium?.copyWith(
                              color: ink,
                            ),
                          ),
                        ),
                        const SizedBox(height: NxSpace.xxs),
                        // Se recalcula sola ("hace 3 min" no se congela). Si
                        // este teléfono va atrasado la hora del servidor
                        // queda en el futuro: se muestra la hora absoluta y no
                        // un engañoso "hace un momento".
                        PeriodicRebuild(
                          builder: (context) {
                            final now = ref.read(clockProvider).now();
                            final createdAt = alert.createdAt;
                            final unreliable =
                                createdAt.difference(now) >
                                const Duration(minutes: 1);
                            return Text(
                              unreliable
                                  ? l10n.emergencyCreatedAt(createdAt.toLocal())
                                  : l10n.emergencyBannerTime(
                                      relativeTime(l10n, createdAt, now),
                                    ),
                              style: detailStyle,
                            );
                          },
                        ),
                        const SizedBox(height: NxSpace.xxs),
                        Row(
                          children: [
                            Icon(
                              alert.location == null
                                  ? Icons.location_off_outlined
                                  : Icons.location_on_outlined,
                              color: ink,
                              size: nxScaledIcon(context, NxSize.iconSm),
                            ),
                            const SizedBox(width: NxSpace.xxs),
                            Expanded(
                              child: Text(
                                alert.location == null
                                    ? l10n.emergencyBannerNoLocation
                                    : l10n.emergencyBannerLocationIncluded,
                                style: detailStyle,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: NxSpace.sm),
                  if (acknowledged)
                    MergeSemantics(
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: ink,
                            size: nxScaledIcon(context, NxSize.iconSm),
                          ),
                          const SizedBox(width: NxSpace.xs),
                          Expanded(
                            child: Text(
                              l10n.emergencyBannerAcked,
                              style: context.text.labelLarge?.copyWith(
                                color: ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    NxButton(
                      label: l10n.emergencyBannerAck,
                      icon: Icons.visibility_outlined,
                      expand: false,
                      loading: _sending,
                      onPressed: _acknowledge,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
