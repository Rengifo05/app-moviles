import 'package:meta/meta.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/core/text.dart';

/// Usuario autenticado. Solo lo imprescindible para la app.
@immutable
final class AuthUser {
  const new({required this.uid, required this.email, this.displayName});

  final String uid;
  final String email;
  final String? displayName;

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.uid == uid &&
      other.email == email &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(uid, email, displayName);
}

/// Datos de registro. La confirmación de mayoría de edad y la aceptación de
/// la política de privacidad son obligatorias (decisión D5: MVP solo para
/// adultos).
@immutable
final class SignUpRequest {
  const new({
    required this.email,
    required this.password,
    required this.displayName,
    required this.confirmedAdult,
    required this.acceptedPrivacyPolicy,
  });

  final String email;
  final String password;
  final String displayName;
  final bool confirmedAdult;
  final bool acceptedPrivacyPolicy;
}

abstract interface class AuthRepository {
  /// Emite el usuario actual y cada cambio de sesión.
  Stream<AuthUser?> watchUser();

  AuthUser? get currentUser;

  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  });

  Future<Result<AuthUser>> signUp(SignUpRequest request);

  Future<VoidResult> sendPasswordReset(String email);

  Future<VoidResult> signOut();

  /// Elimina la cuenta y sus datos personales en el servidor.
  Future<VoidResult> deleteAccount();
}

/// Reglas de validación compartidas por la UI y los casos de uso. Devuelven
/// el código del error (para localizarlo) o `null` si el valor es válido.
abstract final class AuthValidators {
  static const int minPasswordLength = 8;
  static const int maxDisplayNameLength = 40;

  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  static String? email(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'email-required';
    // La longitud va antes: la expresión retrocede en tiempo cuadrático y,
    // sin límite, un texto enorme pegado congela la interfaz.
    if (v.length > 254 || !_email.hasMatch(v)) return 'email-invalid';
    return null;
  }

  static String? password(String value) {
    if (value.isEmpty) return 'password-required';
    if (value.length < minPasswordLength) return 'password-too-short';
    if (value.trim().isEmpty) return 'password-too-weak';
    return null;
  }

  static String? displayName(String value) {
    final v = value.trim();
    if (v.isEmpty || !hasVisibleContent(v)) return 'display-name-required';
    if (v.length > maxDisplayNameLength) return 'display-name-too-long';
    return null;
  }

  static List<String> signUp(SignUpRequest r) => [
    ?email(r.email),
    ?password(r.password),
    ?displayName(r.displayName),
    if (!r.confirmedAdult) 'adult-confirmation-required',
    if (!r.acceptedPrivacyPolicy) 'privacy-acceptance-required',
  ];
}
