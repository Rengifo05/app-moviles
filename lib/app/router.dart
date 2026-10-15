import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/app/app_shell.dart';
import 'package:nexo_familia/app/session.dart';
import 'package:nexo_familia/app/session_providers.dart';
import 'package:nexo_familia/features/activity/presentation/activity_screen.dart';
import 'package:nexo_familia/features/authentication/presentation/reset_password_screen.dart';
import 'package:nexo_familia/features/authentication/presentation/sign_in_screen.dart';
import 'package:nexo_familia/features/authentication/presentation/sign_up_screen.dart';
import 'package:nexo_familia/features/check_ins/presentation/check_in_screen.dart';
import 'package:nexo_familia/features/emergency/presentation/sos_screen.dart';
import 'package:nexo_familia/features/family/presentation/create_family_screen.dart';
import 'package:nexo_familia/features/family/presentation/family_screen.dart';
import 'package:nexo_familia/features/family/presentation/family_setup_screen.dart';
import 'package:nexo_familia/features/family/presentation/invite_screen.dart';
import 'package:nexo_familia/features/family/presentation/join_family_screen.dart';
import 'package:nexo_familia/features/family/presentation/member_detail_screen.dart';
import 'package:nexo_familia/features/geofences/presentation/geofence_editor_screen.dart';
import 'package:nexo_familia/features/home/presentation/home_screen.dart';
import 'package:nexo_familia/features/location_sharing/presentation/map_screen.dart';
import 'package:nexo_familia/features/onboarding/presentation/onboarding_screen.dart';
import 'package:nexo_familia/features/settings/presentation/account_screen.dart';
import 'package:nexo_familia/features/settings/presentation/privacy_screen.dart';
import 'package:nexo_familia/features/settings/presentation/settings_screen.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Enrutador de la app. Las redirecciones dependen solo de la sesión
/// ([redirectFor], probada por separado).
final routerProvider = Provider<GoRouter>((ref) {
  final session = ValueNotifier<SessionState>(ref.read(sessionProvider));
  ref
    ..listen(sessionProvider, (_, next) => session.value = next)
    ..onDispose(session.dispose);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: session,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) => redirectFor(session.value, state.uri.path),
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, _) => const OnboardingScreen(),
      ),
      GoRoute(path: AppRoutes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(path: AppRoutes.signUp, builder: (_, _) => const SignUpScreen()),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (_, _) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.familySetup,
        builder: (_, _) => const FamilySetupScreen(),
        routes: [
          GoRoute(
            path: 'create',
            builder: (_, _) => const CreateFamilyScreen(),
          ),
          GoRoute(path: 'join', builder: (_, _) => const JoinFamilyScreen()),
        ],
      ),
      // Rutas modales a pantalla completa por encima de la barra inferior.
      GoRoute(
        path: AppRoutes.sos,
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, _) =>
            const MaterialPage(fullscreenDialog: true, child: SosScreen()),
      ),
      GoRoute(
        path: AppRoutes.checkIn,
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, _) =>
            const MaterialPage(fullscreenDialog: true, child: CheckInScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (_, _) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.map,
                builder: (_, _) => const MapScreen(),
                routes: [
                  GoRoute(
                    path: 'zones/new',
                    parentNavigatorKey: _rootKey,
                    builder: (_, _) => const GeofenceEditorScreen(),
                  ),
                  GoRoute(
                    path: 'zones/:id',
                    parentNavigatorKey: _rootKey,
                    builder: (_, state) => GeofenceEditorScreen(
                      geofenceId: state.pathParameters['id'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.activity,
                builder: (_, _) => const ActivityScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.family,
                builder: (_, _) => const FamilyScreen(),
                routes: [
                  GoRoute(
                    path: 'invite',
                    builder: (_, _) => const InviteScreen(),
                  ),
                  GoRoute(
                    path: 'members/:uid',
                    builder: (_, state) =>
                        MemberDetailScreen(uid: state.pathParameters['uid']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (_, _) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'privacy',
                    builder: (_, _) => const PrivacyScreen(),
                  ),
                  GoRoute(
                    path: 'account',
                    builder: (_, _) => const AccountScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
