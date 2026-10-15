import 'package:flutter/material.dart';
import 'package:nexo_familia/design_system/components/nx_avatar.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_text.dart';
import 'package:nexo_familia/features/family/presentation/family_widgets.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Texto agrandado por encima de ~130 %: los íconos decorativos se ocultan
/// para dejar el ancho al texto.
bool settingsLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) > 1.3;

/// Permite partir un texto sin espacios (p. ej. un correo) después de `@`
/// y de `.`, en lugar de a mitad de palabra.
String breakableAtSeparators(String text) => text.contains(' ')
    ? text
    : text.replaceAllMapped(_separator, (m) => '${m[0]}\u200B');

final RegExp _separator = RegExp('[@.]');

/// Fila de Ajustes que abre otra pantalla. Sin tarjeta: el contenido va
/// sobre el fondo, separado por encabezados de sección.
class SettingsLinkTile extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.onTap,
    super.key,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    // Con texto agrandado, el ícono le quitaría ancho al texto.
    leading: settingsLargeText(context)
        ? null
        : Icon(icon, size: nxScaledIcon(context, NxSize.iconMd)),
    title: Text(title, style: context.text.titleSmall),
    subtitle: subtitle == null
        ? null
        : Text(
            breakableAtSeparators(subtitle!),
            semanticsLabel: subtitle,
            style: context.text.bodyMedium?.copyWith(
              color: context.nx.inkMuted,
            ),
          ),
    trailing: Icon(
      Icons.chevron_right,
      size: nxScaledIcon(context, NxSize.iconMd),
    ),
    minTileHeight: NxSize.minTouchTarget,
    onTap: onTap,
  );
}

/// Resumen de la política de privacidad en una hoja inferior.
Future<void> showPrivacySummarySheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: NxSpace.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.privacySummaryTitle,
                        style: context.text.titleLarge,
                      ),
                    ),
                    const SizedBox(height: NxSpace.md),
                    Text(
                      l10n.privacySummaryBody,
                      style: context.text.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(NxSpace.gutter),
              child: NxButton(
                label: l10n.commonClose,
                variant: NxButtonVariant.secondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        );
      },
    );

/// Semilla estable para el tono del avatar (no depende de `hashCode`).
int settingsAvatarSeed(String uid) =>
    uid.codeUnits.fold(0, (sum, unit) => sum + unit);

/// Integrante que puede (o podría) ver mi ubicación: avatar, nombre y rol.
class AudienceMemberRow extends StatelessWidget {
  const new({required this.member, super.key});

  final FamilyMember member;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = member.displayName.trim();
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NxSpace.xs),
        child: Row(
          children: [
            NxAvatar(name: name, colorSeed: settingsAvatarSeed(member.uid)),
            const SizedBox(width: NxSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: context.text.titleSmall),
                  Text(
                    familyRoleLabel(l10n, member.role),
                    style: context.text.bodyMedium?.copyWith(
                      color: context.nx.inkMuted,
                    ),
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

/// Explicación **antes** de activar la compartición: qué se comparte, con
/// quién (cada integrante por su nombre), cuándo y que se puede pausar.
///
/// Devuelve `true` solo si la persona elige compartir; cerrar la hoja o
/// pulsar "Ahora no" no cambia nada ni pide permisos.
Future<bool> showShareExplanation(
  BuildContext context, {
  required String? familyName,
  required List<FamilyMember>? audience,
  required LocationPrecision precision,
}) async {
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ShareExplanationSheet(
      familyName: familyName,
      audience: audience,
      precision: precision,
    ),
  );
  return accepted ?? false;
}

class ShareExplanationSheet extends StatelessWidget {
  const new({
    required this.familyName,
    required this.audience,
    required this.precision,
    super.key,
  });

  final String? familyName;

  /// Integrantes que verán la ubicación (sin la persona actual); `null` si
  /// aún no se conocen.
  final List<FamilyMember>? audience;
  final LocationPrecision precision;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = familyName?.trim();
    final people = audience;
    // Las acciones quedan siempre a la vista; con texto grande se desplaza
    // solo la explicación.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: NxSpace.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.settingsShareSheetTitle,
                    style: context.text.titleLarge,
                  ),
                ),
                const SizedBox(height: NxSpace.sm),
                FamilyNote(
                  icon: Icons.map_outlined,
                  text: precision == LocationPrecision.approximate
                      ? l10n.settingsShareSheetWhatApprox
                      : l10n.settingsShareSheetWhatExact,
                  style: context.text.bodyLarge,
                ),
                if (people != null && people.isEmpty)
                  FamilyNote(
                    icon: Icons.groups_outlined,
                    text: l10n.settingsShareSheetNobody,
                    style: context.text.bodyLarge,
                  )
                else ...[
                  FamilyNote(
                    icon: Icons.groups_outlined,
                    text: name == null || name.isEmpty
                        ? l10n.settingsShareSheetWhoGeneric
                        : l10n.settingsShareSheetWho(name),
                    style: context.text.bodyLarge,
                  ),
                  if (people != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: NxSpace.xl,
                      ),
                      child: Column(
                        children: [
                          for (final member in people)
                            AudienceMemberRow(member: member),
                        ],
                      ),
                    ),
                ],
                FamilyNote(
                  icon: Icons.phone_android_outlined,
                  text: l10n.settingsShareSheetWhen,
                  style: context.text.bodyLarge,
                ),
                FamilyNote(
                  icon: Icons.pause_circle_outline,
                  text: l10n.settingsShareSheetPause,
                  style: context.text.bodyLarge,
                ),
                const SizedBox(height: NxSpace.xs),
                Text(
                  l10n.settingsShareSheetPermission,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.nx.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NxSpace.gutter,
            NxSpace.md,
            NxSpace.gutter,
            NxSpace.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NxButton(
                label: l10n.settingsPrivacyShare,
                icon: Icons.location_on_outlined,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: NxSpace.xs),
              NxButton(
                label: l10n.settingsShareSheetCancel,
                variant: NxButtonVariant.tertiary,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
