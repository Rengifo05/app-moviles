import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/app/session.dart';
import 'package:nexo_familia/app/session_providers.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/settings/domain/preferences.dart';
import 'package:nexo_familia/features/settings/presentation/settings_providers.dart';

const user = AuthUser(uid: 'u1', email: 'ana@example.com');

FamilyGroup family(String id) => FamilyGroup(
  id: id,
  name: 'Familia $id',
  myRole: MemberRole.owner,
  joinedAt: DateTime.utc(2026),
);

void main() {
  group('redirectFor', () {
    const ready = SessionReady(user, 'f1');
    const cases = <(SessionState, String, String?)>[
      (SessionLoading(), '/home', AppRoutes.splash),
      (SessionLoading(), AppRoutes.splash, null),
      (NeedsOnboarding(), '/home', AppRoutes.onboarding),
      (NeedsOnboarding(), AppRoutes.onboarding, null),
      (SignedOut(), '/home', AppRoutes.signIn),
      (SignedOut(), AppRoutes.signUp, null),
      (SignedOut(), AppRoutes.resetPassword, null),
      (SignedOut(), '/authx', AppRoutes.signIn),
      (NeedsFamily(user), '/home', AppRoutes.familySetup),
      (NeedsFamily(user), AppRoutes.joinFamily, null),
      (ready, AppRoutes.splash, AppRoutes.home),
      (ready, AppRoutes.signIn, AppRoutes.home),
      (ready, AppRoutes.onboarding, AppRoutes.home),
      (ready, AppRoutes.familySetup, AppRoutes.home),
      // Con familia se puede crear o unirse a otra.
      (ready, AppRoutes.createFamily, null),
      (ready, AppRoutes.joinFamily, null),
      (ready, AppRoutes.sos, null),
      (ready, '/family/members/u2', null),
    ];
    for (final (session, location, expected) in cases) {
      test('${session.runtimeType} en $location → $expected', () {
        expect(redirectFor(session, location), expected);
      });
    }
  });

  group('sessionProvider', () {
    ProviderContainer container({
      AppPreferences prefs = const AppPreferences(onboardingCompleted: true),
      AuthUser? currentUser = user,
      List<FamilyGroup> families = const [],
    }) {
      final c = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith((ref) => Stream.value(prefs)),
          currentUserProvider.overrideWith((ref) => Stream.value(currentUser)),
          myFamiliesProvider.overrideWith((ref) => Stream.value(families)),
          activeFamilyIdOverride,
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<SessionState> settle(ProviderContainer c) {
      c.listen(sessionProvider, (_, _) {});
      return pumpEventQueue().then((_) => c.read(sessionProvider));
    }

    test('sin onboarding pide el onboarding', () async {
      final c = container(prefs: const AppPreferences());
      expect(await settle(c), isA<NeedsOnboarding>());
    });

    test('sin usuario pide iniciar sesión', () async {
      final c = container(currentUser: null);
      expect(await settle(c), isA<SignedOut>());
    });

    test('sin familias pide crear o unirse a una', () async {
      expect(await settle(container()), isA<NeedsFamily>());
    });

    test('usa la familia activa guardada si sigue existiendo', () async {
      final c = container(
        prefs: const AppPreferences(
          onboardingCompleted: true,
          activeFamilyId: 'f2',
        ),
        families: [family('f1'), family('f2')],
      );
      final session = await settle(c);
      expect((session as SessionReady).familyId, 'f2');
      expect(c.read(activeFamilyIdProvider), 'f2');
    });

    test('si la familia guardada ya no existe, usa la primera', () async {
      final c = container(
        prefs: const AppPreferences(
          onboardingCompleted: true,
          activeFamilyId: 'eliminada',
        ),
        families: [family('f1')],
      );
      expect(((await settle(c)) as SessionReady).familyId, 'f1');
    });
  });
}
