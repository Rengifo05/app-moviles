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
    final fb.User user;
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      user = credential.user!;
    } on fb.FirebaseAuthException catch (e) {
      return Err(mapAuthError(e.code, e));
    }
    // Una cuenta sin perfil es un registro que no terminó (sin conexión o
    // app cerrada a mitad): no se entra sin los consentimientos guardados.
    // Si no se puede comprobar (red), se deja entrar: no se bloquea a nadie
    // por un fallo transitorio.
    if (await _remote.getDoc(BackendPaths.user(user.uid)) case Ok(
      value: null,
    )) {
      await _auth.signOut();
      return const Err(Failure(FailureKind.conflict, 'signup-incomplete'));
    }
    return Ok(_map(user)!);
  }

  @override
  Future<Result<AuthUser>> signUp(SignUpRequest request) async {
    final errors = AuthValidators.signUp(request);
    if (errors.isNotEmpty) return Err(Failure.validation(errors.first));
    final name = request.displayName.trim();
    final email = request.email.trim();
    final fb.User user;
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: request.password,
      );
      user = credential.user!;
    } on fb.FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        return await _resumeIncompleteSignUp(email, request.password, name);
      }
      return Err(mapAuthError(e.code, e));
    }
    return await _finishSignUp(user, name, undoOnFailure: true);
  }

  /// Guarda el perfil **antes** que nada más: es lo que leen las Functions
  /// (nombre) y lo que prueba los consentimientos. Si no se guarda, la
  /// cuenta no queda a medias con la sesión abierta: se deshace (o, si ni
  /// eso se puede, se cierra la sesión y reintentar el registro la repara;
  /// ver [_resumeIncompleteSignUp]). El nombre en Auth y la verificación de
  /// correo (amenaza 2) van después y no bloquean.
  Future<Result<AuthUser>> _finishSignUp(
    fb.User user,
    String name, {
    required bool undoOnFailure,
  }) async {
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
      if (undoOnFailure) {
        try {
          await user.delete();
        } on Object {
          // Sin red tampoco se puede borrar: se repara al reintentar.
        }
      }
      await _auth.signOut();
      return Err(failure);
    }
    for (final step in [
      () => user.updateDisplayName(name),
      user.sendEmailVerification,
    ]) {
      try {
        await step();
      } on Object {
        // No bloquea: el perfil ya tiene el nombre y la cuenta funciona.
      }
    }
    return Ok(
      AuthUser(uid: user.uid, email: user.email ?? '', displayName: name),
    );
  }

  /// "Correo en uso" puede ser un registro anterior que creó la cuenta pero
  /// no el perfil. Si la contraseña coincide y no hay perfil, se completa con
  /// los consentimientos de ESTE formulario; en cualquier otro caso responde
  /// "correo en uso", como siempre.
  Future<Result<AuthUser>> _resumeIncompleteSignUp(
    String email,
    String password,
    String name,
  ) async {
    const inUse = Failure(FailureKind.conflict, 'email-in-use');
    final fb.User user;
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      user = credential.user!;
    } on fb.FirebaseAuthException {
      return const Err(inUse);
    }
    final existing = await _remote.getDoc(BackendPaths.user(user.uid));
    if (existing case Ok(value: null)) {
      return await _finishSignUp(user, name, undoOnFailure: false);
    }
    await _auth.signOut();
    return Err(existing.failureOrNull ?? inUse);
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

  @override
  Future<VoidResult> signOutEverywhere() async {
    if (_auth.currentUser == null) return const Err(Failure.unauthenticated());
    final result = await _functions.call(
      BackendFunctions.signOutEverywhere,
      {},
    );
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
