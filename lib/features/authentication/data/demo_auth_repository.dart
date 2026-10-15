import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/infrastructure/demo/in_memory_remote_store.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';

/// Autenticación del modo demostración: cuentas en memoria, sin red.
///
/// Las contraseñas nunca se guardan en claro (SHA-256 con sal por cuenta).
/// Los datos se pierden al cerrar la app: es un modo para probar la
/// interfaz, no un sistema de identidad.
final class DemoAuthRepository implements AuthRepository {
  new({required this._store, required this._callFunction, math.Random? random})
    : _random = random ?? math.Random.secure();

  final InMemoryRemoteStore _store;
  final Future<Result<Json>> Function(String, Json) _callFunction;
  final math.Random _random;

  final Map<String, _Account> _accounts = {};
  final StreamController<AuthUser?> _changes = StreamController.broadcast();
  AuthUser? _current;

  @override
  AuthUser? get currentUser => _current;

  @override
  Stream<AuthUser?> watchUser() async* {
    yield _current;
    yield* _changes.stream;
  }

  @override
  Future<Result<AuthUser>> signUp(SignUpRequest request) async {
    final errors = AuthValidators.signUp(request);
    if (errors.isNotEmpty) return Err(Failure.validation(errors.first));
    final email = _normalize(request.email);
    if (_accounts.containsKey(email)) {
      return const Err(Failure(FailureKind.conflict, 'email-in-use'));
    }
    final uid = _newId();
    final salt = _newId();
    _accounts[email] = _Account(
      uid: uid,
      displayName: request.displayName.trim(),
      salt: salt,
      passwordHash: _hash(salt, request.password),
    );
    _store.serverWrite('users/$uid', {
      'displayName': request.displayName.trim(),
      'createdAt': serverTimestamp,
      'adultConfirmedAt': serverTimestamp,
      'privacyAcceptedAt': serverTimestamp,
      'privacyPolicyVersion': '2026-10',
    });
    return Ok(_setCurrent(email));
  }

  @override
  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  }) async {
    final key = _normalize(email);
    final account = _accounts[key];
    // Mismo error para correo inexistente y contraseña incorrecta: no se
    // revela qué cuentas existen.
    if (account == null ||
        account.passwordHash != _hash(account.salt, password)) {
      return const Err(Failure(FailureKind.validation, 'invalid-credentials'));
    }
    return Ok(_setCurrent(key));
  }

  @override
  Future<VoidResult> sendPasswordReset(String email) async =>
      // En demostración no hay correo; se responde igual exista o no la
      // cuenta, para no revelar qué correos están registrados.
      const Ok(null);

  @override
  Future<VoidResult> signOut() async {
    _current = null;
    _changes.add(null);
    return const Ok(null);
  }

  @override
  Future<VoidResult> deleteAccount() async {
    final user = _current;
    if (user == null) return const Err(Failure.unauthenticated());
    final result = await _callFunction('deleteAccount', const {});
    if (result case Err(:final failure)) return Err(failure);
    _accounts.remove(user.email);
    await signOut();
    return const Ok(null);
  }

  AuthUser _setCurrent(String email) {
    final account = _accounts[email]!;
    final user = AuthUser(
      uid: account.uid,
      email: email,
      displayName: account.displayName,
    );
    _current = user;
    _changes.add(user);
    return user;
  }

  static String _normalize(String email) => email.trim().toLowerCase();

  static String _hash(String salt, String password) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();

  String _newId() => List.generate(
    20,
    (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_random.nextInt(36)],
  ).join();

  Future<void> dispose() => _changes.close();
}

final class _Account {
  const new({
    required this.uid,
    required this.displayName,
    required this.salt,
    required this.passwordHash,
  });

  final String uid;
  final String displayName;
  final String salt;
  final String passwordHash;
}
