import 'package:meta/meta.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';

export 'package:nexo_familia/features/common/presentation/routes.dart';

/// Estado global de la sesión que decide qué parte de la app se muestra.
@immutable
sealed class SessionState {
  const new();
}

final class SessionLoading extends SessionState {
  const new();
}

final class NeedsOnboarding extends SessionState {
  const new();
}

final class SignedOut extends SessionState {
  const new();
}

final class NeedsFamily extends SessionState {
  const new(this.user);

  final AuthUser user;
}

final class SessionReady extends SessionState {
  const new(this.user, this.familyId);

  final AuthUser user;
  final String familyId;
}

/// Redirección según la sesión. Función pura para probarla sin widgets.
String? redirectFor(SessionState session, String location) {
  bool under(String prefix) =>
      location == prefix || location.startsWith('$prefix/');

  return switch (session) {
    SessionLoading() => location == AppRoutes.splash ? null : AppRoutes.splash,
    NeedsOnboarding() =>
      under(AppRoutes.onboarding) ? null : AppRoutes.onboarding,
    SignedOut() => under('/auth') ? null : AppRoutes.signIn,
    NeedsFamily() =>
      under(AppRoutes.familySetup) ? null : AppRoutes.familySetup,
    SessionReady() =>
      under(AppRoutes.splash) ||
              under(AppRoutes.onboarding) ||
              under('/auth') ||
              // Crear o unirse a OTRA familia sigue permitido.
              location == AppRoutes.familySetup
          ? AppRoutes.home
          : null,
  };
}
