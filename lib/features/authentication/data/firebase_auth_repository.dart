import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';

/// Autenticación con Firebase Auth (correo y contraseña, decisión D6).
final class FirebaseAuthRepository implements AuthRepository {
  new({required this._auth, required this._remote, required this._functions});

  final fb.FirebaseAuth _auth;
  final RemoteStore _remote;
  final FunctionsClient _functions;

  static AuthUser? _map(fb.User? user) => user == null
      ? null
      : AuthUser(
          uid: user.uid,
          email: user.email ?? '',
          displayName: user.displayName,
        );

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  @override
  Stream<AuthUser?> watchUser() => _auth.userChanges().map(_map);

  @override
  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return Ok(_map(credential.user)!);
    } on fb.FirebaseAuthException catch (e) {
      return Err(mapAuthError(e.code, e));
    }
  }

  @override
  Future<Result<AuthUser>> signUp(SignUpRequest request) async {
    final errors = AuthValidators.signUp(request);
    if (errors.isNotEmpty) return Err(Failure.validation(errors.first));
    final name = request.displayName.trim();
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: request.email.trim(),
        password: request.password,
      );
      final user = credential.user!;
      await user.updateDisplayName(name);
      final profile = await _remote.commit([
        RemoteWrite.put(BackendPaths.user(user.uid), {
          'displayName': name,
          'createdAt': serverTimestamp,
          'adultConfirmedAt': serverTimestamp,
          'privacyAcceptedAt': serverTimestamp,
          'privacyPolicyVersion': '2026-10',
        }),
      ]);
      if (profile case Err(:final failure)) {
        // Sin perfil, la cuenta quedaría a medias y reintentar el registro
        // daría "correo en uso": se deshace (y, si tampoco se puede borrar,
        // al menos se cierra la sesión).
        try {
          await user.delete();
        } on Object {
          // Se cierra la sesión abajo.
        }
        await _auth.signOut();
        return Err(failure);
      }
      // Verificación de correo (amenaza 2). No bloquea el registro: si el
      // envío falla, la cuenta funciona igual.
      try {
        await user.sendEmailVerification();
      } on Object {
        // Sin verificación enviada; la persona puede pedirla más adelante.
      }
      return Ok(
        AuthUser(uid: user.uid, email: user.email ?? '', displayName: name),
      );
    } on fb.FirebaseAuthException catch (e) {
      return Err(mapAuthError(e.code, e));
    }
  }

  @override
  Future<VoidResult> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on fb.FirebaseAuthException catch (e) {
      // No se revela si el correo existe: "user-not-found" se trata como
      // éxito, igual que en la pantalla.
      if (e.code != 'user-not-found') return Err(mapAuthError(e.code, e));
    }
    return const Ok(null);
  }

  @override
  Future<VoidResult> signOut() async {
    await _auth.signOut();
    return const Ok(null);
  }

  @override
  Future<VoidResult> deleteAccount() async {
    if (_auth.currentUser == null) return const Err(Failure.unauthenticated());
    // El servidor borra los datos y el usuario de Auth (deleteAccount).
    final result = await _functions.call(BackendFunctions.deleteAccount, {});
    if (result case Err(:final failure)) return Err(failure);
    await _auth.signOut();
    return const Ok(null);
  }
}

/// Errores de Firebase Auth → [Failure]. Correo inexistente y contraseña
/// incorrecta dan el MISMO error (no se revela qué cuentas existen).
Failure mapAuthError(String code, [Object? cause]) => switch (code) {
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' ||
  'invalid-login-credentials' => const Failure(
    FailureKind.validation,
    'invalid-credentials',
  ),
  'email-already-in-use' => const Failure(FailureKind.conflict, 'email-in-use'),
  'invalid-email' => const Failure.validation('email-invalid'),
  'weak-password' => const Failure.validation('password-too-weak'),
  'too-many-requests' => const Failure(FailureKind.rateLimited, 'rate-limited'),
  'network-request-failed' => Failure.network('network', cause),
  'user-disabled' => const Failure.permissionDenied('user-disabled'),
  'requires-recent-login' => const Failure.unauthenticated(
    'requires-recent-login',
  ),
  _ => Failure.unexpected('auth', cause),
};
