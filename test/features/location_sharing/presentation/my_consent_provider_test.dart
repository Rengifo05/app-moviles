import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';

/// Cuenta que cambia (teléfono compartido).
final class _Auth implements AuthRepository {
  AuthUser? user = const AuthUser(uid: 'ana', email: 'ana@example.com');
  final StreamController<AuthUser?> changes = StreamController.broadcast();

  void switchTo(AuthUser? next) => changes.add(user = next);

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> watchUser() => Stream.multi((controller) {
    controller.add(user);
    final sub = changes.stream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });

  @override
  Future<VoidResult> signOut() => throw UnimplementedError();

  @override
  Future<VoidResult> signOutEverywhere() => throw UnimplementedError();

  @override
  Future<VoidResult> deleteAccount() => throw UnimplementedError();

  @override
  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<Result<AuthUser>> signUp(SignUpRequest request) =>
      throw UnimplementedError();

  @override
  Future<VoidResult> sendPasswordReset(String email) =>
      throw UnimplementedError();
}

/// Devuelve el consentimiento de quien tenga la sesión AL SUSCRIBIRSE, como
/// el repositorio real.
final class _Location implements LocationRepository {
  new(this._auth);

  final _Auth _auth;

  static const Map<String, SharingState> states = {
    'ana': SharingState.paused,
    'luis': SharingState.sharing,
  };

  @override
  Stream<SharingConsent> watchMyConsent(String familyId) {
    final uid = _auth.currentUser!.uid;
    return Stream.value(
      SharingConsent(
        familyId: familyId,
        uid: uid,
        state: states[uid]!,
        precision: LocationPrecision.exact,
      ),
    );
  }

  @override
  Future<VoidResult> updateConsent(SharingConsent consent) =>
      throw UnimplementedError();

  @override
  Stream<List<MemberLocation>> watchFamilyLocations(String familyId) =>
      throw UnimplementedError();

  @override
  Future<VoidResult> publishMyLocation(
    String familyId,
    MemberLocation location,
  ) => throw UnimplementedError();
}

void main() {
  test('al cambiar de cuenta se ve el consentimiento de la nueva', () async {
    final auth = _Auth();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        locationRepositoryProvider.overrideWithValue(_Location(auth)),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(myConsentProvider('f1'), (_, _) {});
    addTearDown(sub.close);

    expect((await container.read(myConsentProvider('f1').future)).uid, 'ana');

    auth.switchTo(const AuthUser(uid: 'luis', email: 'luis@example.com'));
    await pumpEventQueue();

    final consent = await container.read(myConsentProvider('f1').future);
    expect(consent.uid, 'luis');
    expect(consent.state, SharingState.sharing);
  });
}
