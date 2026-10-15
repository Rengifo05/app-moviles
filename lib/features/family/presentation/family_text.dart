import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/features/common/presentation/failure_text.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Operación de familia que produjo un fallo. Algunos códigos
/// (`not-allowed`, `not-member`) significan cosas distintas según la
/// operación.
enum FamilyOperation { create, join, invite, leave, remove, switchFamily }

/// Rol como texto: el rol nunca se comunica solo con color.
String familyRoleLabel(AppLocalizations l10n, MemberRole role) =>
    switch (role) {
      MemberRole.owner => l10n.familyRoleOwner,
      MemberRole.admin => l10n.familyRoleAdmin,
      MemberRole.member => l10n.familyRoleMember,
    };

/// Mensaje para un código de `FamilyRules.familyName` (null si es válido).
String? familyNameValidationMessage(AppLocalizations l10n, String? code) =>
    switch (code) {
      null => null,
      'family-name-required' => l10n.familyErrorNameRequired,
      'family-name-too-long' => l10n.familyErrorNameTooLong(
        FamilyRules.maxNameLength,
      ),
      _ => l10n.familyErrorNameInvalid(FamilyRules.maxNameLength),
    };

/// Mensaje para un fallo de una operación de familia. Traduce los códigos
/// del contrato del backend (`details.reason`) y recurre al mensaje
/// genérico por categoría para el resto.
String familyFailureMessage(
  AppLocalizations l10n,
  Failure failure,
  FamilyOperation operation,
) => switch (failure.code) {
  'family-name-required' ||
  'family-name-too-long' => familyNameValidationMessage(l10n, failure.code)!,
  'family-name-invalid' => l10n.familyErrorNameInvalid(
    FamilyRules.maxNameLength,
  ),
  'too-many-families' => l10n.familyErrorTooManyFamilies,
  'invitation-format' => l10n.familyErrorInvitationFormat,
  'invitation-invalid' => l10n.familyErrorInvitationInvalid,
  'already-member' => l10n.familyErrorAlreadyMember,
  'family-full' => l10n.familyErrorFamilyFull(FamilyRules.maxMembers),
  'rate-limited' => l10n.familyErrorRateLimited,
  'too-many-invitations' => l10n.familyErrorTooManyInvitations,
  'not-allowed' when operation == FamilyOperation.invite =>
    l10n.familyErrorNotAllowedInvite,
  'not-allowed' when operation == FamilyOperation.remove =>
    l10n.familyErrorNotAllowedRemove,
  'not-member' when operation == FamilyOperation.remove =>
    l10n.familyErrorNotMember,
  _ => failureMessage(l10n, failure),
};

/// "Vence en 48 h" / "Vence en 35 min", o `null` si ya venció.
///
/// Las horas se redondean al valor más cercano: un código recién creado
/// (47 h 59 min) se muestra como 48 h, como lo anuncia el servidor.
String? inviteExpiresText(AppLocalizations l10n, Duration remaining) {
  if (remaining <= Duration.zero) return null;
  if (remaining < const Duration(hours: 1)) {
    final minutes = remaining.inMinutes < 1 ? 1 : remaining.inMinutes;
    return l10n.familyInviteExpiresMinutes(minutes);
  }
  return l10n.familyInviteExpiresHours((remaining.inMinutes / 60).round());
}

/// El código letra por letra para los lectores de pantalla
/// (`A B C D E, F G H J K`), que de otro modo lo leerían como una palabra.
String spellInvitationCode(String code) {
  final formatted = FamilyRules.formatCode(code);
  return formatted
      .split('-')
      .map((part) => part.split('').join(' '))
      .join(', ');
}
