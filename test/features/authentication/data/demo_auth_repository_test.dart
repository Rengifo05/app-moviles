import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/authentication/data/demo_auth_repository.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/infrastructure/demo/in_memory_remote_store.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';

const request = SignUpRequest(
  email: ' Ana@Example.com ',
  password: 'contraseña-segura',
  displayName: 'Ana',
  confirmedAdult: true,
  acceptedPrivacyPolicy: true,
);

void main() {
  late InMemoryRemoteStore store;
  late DemoAuthRepository repo;
  final calls = <String>[];

  setUp(() {
    calls.clear();
    store = InMemoryRemoteStore();
    repo = DemoAuthRepository(
      store: store,
      random: math.Random(1),
      callFunction: (name, payload) async {
        calls.add(name);
        return const Ok(<String, Object?>{});
      },
    );
  });

  test(
    'registro válido inicia sesión y crea el perfil sin la contraseña',
    () async {
      final result = await repo.signUp(request);
      final user = result.valueOrNull!;
      expect(user.email, 'ana@example.com');
      expect(repo.currentUser, user);
      final profile = store.serverRead('users/${user.uid}')!;
      expect(profile['displayName'], 'Ana');
      expect(store.snapshot.toString(), isNot(contains('contraseña-segura')));
    },
  );

  test('el registro exige mayoría de edad y aceptar la privacidad', () async {
    final result = await repo.signUp(
      const SignUpRequest(
        email: 'a@b.co',
        password: '12345678',
        displayName: 'A',
        confirmedAdult: false,
        acceptedPrivacyPolicy: true,
      ),
    );
    expect(result.failureOrNull?.code, 'adult-confirmation-required');
  });

  test('no permite registrar dos veces el mismo correo', () async {
    await repo.signUp(request);
    final again = await repo.signUp(request);
    expect(again.failureOrNull?.kind, FailureKind.conflict);
  });

  test(
    'credenciales incorrectas y correo inexistente dan el mismo error',
    () async {
      await repo.signUp(request);
      await repo.signOut();
      final wrongPassword = await repo.signIn(
        email: 'ana@example.com',
        password: 'otra',
      );
      final unknown = await repo.signIn(
        email: 'nadie@example.com',
        password: 'contraseña-segura',
      );
      expect(wrongPassword.failureOrNull, unknown.failureOrNull);
      final ok = await repo.signIn(
        email: 'ANA@example.com',
        password: 'contraseña-segura',
      );
      expect(ok.isOk, isTrue);
    },
  );

  test('watchUser emite el estado actual y los cambios', () async {
    final emitted = <AuthUser?>[];
    final sub = repo.watchUser().listen(emitted.add);
    await pumpEventQueue();
    await repo.signUp(request);
    await repo.signOut();
    await pumpEventQueue();
    expect(emitted.length, 3);
    expect(emitted.first, isNull);
    expect(emitted[1]?.email, 'ana@example.com');
    expect(emitted.last, isNull);
    await sub.cancel();
  });

  test('eliminar la cuenta llama a la función y cierra la sesión', () async {
    await repo.signUp(request);
    final result = await repo.deleteAccount();
    expect(result.isOk, isTrue);
    expect(calls, ['deleteAccount']);
    expect(repo.currentUser, isNull);
    final again = await repo.signIn(
      email: 'ana@example.com',
      password: 'contraseña-segura',
    );
    expect(again.isOk, isFalse);
  });

  test('cerrar sesión en todos los dispositivos llama a la función y cierra '
      'la sesión aquí', () async {
    await repo.signUp(request);
    expect((await repo.signOutEverywhere()).isOk, isTrue);
    expect(calls, ['signOutEverywhere']);
    expect(repo.currentUser, isNull);
  });

  test('restablecer contraseña no revela si el correo existe', () async {
    expect((await repo.sendPasswordReset('nadie@example.com')).isOk, isTrue);
  });

  test('serverTimestamp marca el perfil con fechas del servidor', () async {
    final user = (await repo.signUp(request)).valueOrNull!;
    expect(
      store.serverRead('users/${user.uid}')!['createdAt'],
      isA<DateTime>(),
    );
    expect(serverTimestamp, isNotNull);
  });
}
