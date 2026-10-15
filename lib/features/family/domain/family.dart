import 'package:meta/meta.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/core/text.dart';

enum MemberRole {
  owner,
  admin,
  member;

  /// Puede invitar, expulsar y gestionar zonas.
  bool get canManage => this == owner || this == admin;
}

/// Una familia a la que pertenece el usuario actual, tal como la expone su
/// membresía (`users/{uid}/memberships/{familyId}`).
@immutable
final class FamilyGroup {
  const new({
    required this.id,
    required this.name,
    required this.myRole,
    required this.joinedAt,
  });

  final String id;
  final String name;

  /// Rol del usuario actual en esta familia.
  final MemberRole myRole;
  final DateTime joinedAt;
}

@immutable
final class FamilyMember {
  const new({
    required this.uid,
    required this.familyId,
    required this.displayName,
    required this.role,
    required this.joinedAt,
  });

  final String uid;
  final String familyId;
  final String displayName;
  final MemberRole role;
  final DateTime joinedAt;
}

/// Invitación recién creada. El [code] en claro solo existe aquí: el
/// servidor guarda únicamente su hash.
@immutable
final class CreatedInvitation {
  const new({
    required this.invitationId,
    required this.code,
    required this.expiresAt,
    required this.maxUses,
  });

  final String invitationId;
  final String code;
  final DateTime expiresAt;
  final int maxUses;
}

abstract final class FamilyRules {
  static const int maxNameLength = 40;
  static const int maxMembers = 12;

  /// Alfabeto sin caracteres ambiguos (0/O, 1/I/L).
  static const String codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const int codeLength = 10;

  static String? familyName(String value) {
    final v = value.trim();
    if (v.isEmpty || !hasVisibleContent(v)) return 'family-name-required';
    if (v.length > maxNameLength) return 'family-name-too-long';
    return null;
  }

  /// Espacios (también los Unicode, como el de no separación) y guiones,
  /// incluidos los tipográficos que insertan algunos teclados y apps al
  /// copiar (‐ ‑ ‒ – — ― −).
  static final RegExp _codeSeparators = RegExp(r'[\s\-\u2010-\u2015\u2212]');

  /// Normaliza lo que escribe el usuario: mayúsculas, sin espacios ni
  /// guiones. Devuelve `null` si no tiene el formato de un código.
  ///
  /// Las mayúsculas se aplican solo a letras ASCII: `toUpperCase` de
  /// Unicode convierte letras ajenas al alfabeto en letras válidas
  /// ('ſ' → 'S') y su resultado varía según la plataforma ('ß' → 'SS' en
  /// web), así que un texto que no es un código podría aceptarse como tal.
  static String? normalizeCode(String input) {
    final stripped = input.replaceAll(_codeSeparators, '');
    if (stripped.length != codeLength) return null;
    final code = StringBuffer();
    for (final unit in stripped.codeUnits) {
      final isAsciiLower = unit >= 0x61 && unit <= 0x7A;
      final char = String.fromCharCode(isAsciiLower ? unit - 0x20 : unit);
      if (!codeAlphabet.contains(char)) return null;
      code.write(char);
    }
    return code.toString();
  }

  /// Presentación legible: `ABCDE-FGHJK`.
  static String formatCode(String code) => code.length == codeLength
      ? '${code.substring(0, 5)}-${code.substring(5)}'
      : code;
}

abstract interface class FamilyRepository {
  /// Familias a las que pertenece el usuario actual.
  Stream<List<FamilyGroup>> watchMyFamilies();

  Stream<List<FamilyMember>> watchMembers(String familyId);

  Future<Result<FamilyGroup>> createFamily(String name);

  /// Solo owner/admin. El servidor valida el permiso.
  Future<Result<CreatedInvitation>> createInvitation(String familyId);

  /// Devuelve el id de la familia a la que se unió.
  Future<Result<String>> acceptInvitation(String code);

  Future<VoidResult> leaveFamily(String familyId);

  Future<VoidResult> removeMember(String familyId, String uid);
}
