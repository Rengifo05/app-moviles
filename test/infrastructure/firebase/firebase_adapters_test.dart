import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/authentication/data/firebase_auth_repository.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/infrastructure/firebase/firebase_functions_client.dart';
import 'package:nexo_familia/infrastructure/firebase/firestore_remote_store.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';

final class _NoFunctions implements FunctionsClient {
  final calls = <String>[];

  @override
  Future<Result<Json>> call(String name, Json payload) async {
    calls.add(name);
    return const Ok({});
  }
}

/// Simula los errores de Firebase Auth para correo inexistente.
final class _ThrowingAuth extends MockFirebaseAuth {
  new(this.code);

  final String code;

  @override
  Future<fb.UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) => throw fb.FirebaseAuthException(code: code);

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    fb.ActionCodeSettings? actionCodeSettings,
  }) => throw fb.FirebaseAuthException(code: code);
}

void main() {
  group('FirestoreRemoteStore', () {
    late FakeFirebaseFirestore db;
    late FirestoreRemoteStore store;

    setUp(() {
      db = FakeFirebaseFirestore();
      store = FirestoreRemoteStore(db);
    });

    test('put, merge y remove en un lote; fechas ↔ Timestamp', () async {
      final when = DateTime.utc(2026, 3, 4, 5, 6, 7);
      final result = await store.commit([
        RemoteWrite.put('families/f1/geofences/g1', {
          'name': 'Casa',
          'updatedAt': when,
          'nested': {
            'at': when,
            'list': [when],
          },
        }),
        const RemoteWrite.merge('families/f1/geofences/g1', {'radiusM': 200}),
        const RemoteWrite.put('families/f1/geofences/g2', {'name': 'X'}),
        const RemoteWrite.remove('families/f1/geofences/g2'),
      ]);
      expect(result.isOk, isTrue);
      final raw = (await db.doc('families/f1/geofences/g1').get()).data()!;
      expect(raw['updatedAt'], isA<fs.Timestamp>());
      expect(raw['radiusM'], 200);

      final doc = (await store.getDoc('families/f1/geofences/g1')).valueOrNull!;
      expect(doc.data['updatedAt'], when);
      expect((doc.data['nested']! as Map)['at'], when);
      expect(((doc.data['nested']! as Map)['list']! as List).single, when);
      expect(
        (await store.getDoc('families/f1/geofences/g2')).valueOrNull,
        isNull,
      );
    });

    test('serverTimestamp se convierte en hora del servidor', () async {
      await store.commit([
        const RemoteWrite.put('users/u1', {'createdAt': serverTimestamp}),
      ]);
      final doc = (await store.getDoc('users/u1')).valueOrNull!;
      expect(doc.data['createdAt'], isA<DateTime>());
    });

    test('consultas con filtro, orden y límite', () async {
      for (var i = 0; i < 5; i++) {
        await db.doc('families/f1/events/e$i').set({
          'type': i.isEven ? 'checkIn' : 'sos',
          'createdAt': fs.Timestamp.fromMillisecondsSinceEpoch(1000 * i),
        });
      }
      final docs = await store
          .watchCollection(
            'families/f1/events',
            query: const RemoteQuery(
              orderBy: 'createdAt',
              descending: true,
              limit: 2,
              whereEquals: {'type': 'checkIn'},
            ),
          )
          .first;
      expect(docs.map((d) => d.id), ['e4', 'e2']);
    });

    test('watchDoc emite null si no existe', () async {
      expect(await store.watchDoc('users/nadie').first, isNull);
    });
  });

  group('traducción de errores', () {
    test('Firestore', () {
      Failure f(String code) => mapFirebaseError(
        fs.FirebaseException(plugin: 'cloud_firestore', code: code),
      );
      expect(f('permission-denied').kind, FailureKind.permissionDenied);
      expect(f('unavailable').isTransient, isTrue);
      expect(f('deadline-exceeded').isTransient, isTrue);
      expect(f('resource-exhausted').kind, FailureKind.rateLimited);
      expect(f('already-exists').kind, FailureKind.conflict);
      expect(f('raro').kind, FailureKind.unexpected);
      // El mensaje del error (puede contener rutas) no pasa al código.
      expect(f('permission-denied').code, 'permission-denied');
    });

    test('Functions usa details.reason como código', () {
      final failure = mapFunctionsError('not-found', {
        'reason': 'invitation-invalid',
      });
      expect(
        failure,
        const Failure(FailureKind.notFound, 'invitation-invalid'),
      );
      expect(mapFunctionsError('unavailable', null).isTransient, isTrue);
      expect(
        mapFunctionsError('resource-exhausted', {
          'reason': 'rate-limited',
        }).kind,
        FailureKind.rateLimited,
      );
    });

    test('Auth no distingue correo inexistente de contraseña errónea', () {
      expect(mapAuthError('user-not-found'), mapAuthError('wrong-password'));
      expect(mapAuthError('invalid-credential').code, 'invalid-credentials');
      expect(mapAuthError('email-already-in-use').code, 'email-in-use');
      expect(mapAuthError('network-request-failed').isTransient, isTrue);
    });
  });

  group('FirebaseAuthRepository', () {
    const request = SignUpRequest(
      email: 'ana@example.com',
      password: 'contraseña-segura',
      displayName: '  Ana  ',
      confirmedAdult: true,
      acceptedPrivacyPolicy: true,
    );

    test(
      'el registro crea la cuenta y el perfil con el nombre recortado',
      () async {
        final db = FakeFirebaseFirestore();
        final repo = FirebaseAuthRepository(
          auth: MockFirebaseAuth(),
          remote: FirestoreRemoteStore(db),
          functions: _NoFunctions(),
        );
        final user = (await repo.signUp(request)).valueOrNull!;
        expect(user.displayName, 'Ana');
        final profile = (await db.doc('users/${user.uid}').get()).data()!;
        expect(profile['displayName'], 'Ana');
        expect(profile.containsKey('password'), isFalse);
      },
    );

    test('valida antes de llamar a Firebase', () async {
      final repo = FirebaseAuthRepository(
        auth: MockFirebaseAuth(),
        remote: FirestoreRemoteStore(FakeFirebaseFirestore()),
        functions: _NoFunctions(),
      );
      final result = await repo.signUp(
        const SignUpRequest(
          email: 'ana@example.com',
          password: 'contraseña-segura',
          displayName: 'Ana',
          confirmedAdult: false,
          acceptedPrivacyPolicy: true,
        ),
      );
      expect(result.failureOrNull?.code, 'adult-confirmation-required');
    });

    test('credenciales incorrectas → error genérico', () async {
      final auth = _ThrowingAuth('user-not-found');
      final repo = FirebaseAuthRepository(
        auth: auth,
        remote: FirestoreRemoteStore(FakeFirebaseFirestore()),
        functions: _NoFunctions(),
      );
      final result = await repo.signIn(email: 'x@y.co', password: '12345678');
      expect(result.failureOrNull?.code, 'invalid-credentials');
    });

    test('restablecer no revela si el correo existe', () async {
      final auth = _ThrowingAuth('user-not-found');
      final repo = FirebaseAuthRepository(
        auth: auth,
        remote: FirestoreRemoteStore(FakeFirebaseFirestore()),
        functions: _NoFunctions(),
      );
      expect((await repo.sendPasswordReset('nadie@y.co')).isOk, isTrue);
    });

    test('eliminar la cuenta llama a la función y cierra sesión', () async {
      final functions = _NoFunctions();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u1', email: 'ana@example.com'),
      );
      final repo = FirebaseAuthRepository(
        auth: auth,
        remote: FirestoreRemoteStore(FakeFirebaseFirestore()),
        functions: functions,
      );
      expect((await repo.deleteAccount()).isOk, isTrue);
      expect(functions.calls, ['deleteAccount']);
      expect(repo.currentUser, isNull);
    });
  });
}
