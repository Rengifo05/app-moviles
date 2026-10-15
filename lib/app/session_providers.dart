import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/app/session.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/settings/domain/preferences.dart';
import 'package:nexo_familia/features/settings/presentation/settings_providers.dart';
import 'package:riverpod/misc.dart';

/// Estado de la sesión derivado de preferencias, autenticación y familias.
final sessionProvider = Provider<SessionState>((ref) {
  final prefsValue = ref.watch(preferencesProvider);
  // Si las preferencias locales fallan, se usan las de por defecto: la app
  // debe poder arrancar (y pedir de nuevo el onboarding) antes que quedarse
  // bloqueada.
  final prefs = prefsValue.hasError ? const AppPreferences() : prefsValue.value;
  if (prefs == null) return const SessionLoading();
  if (!prefs.onboardingCompleted) return const NeedsOnboarding();

  final userValue = ref.watch(currentUserProvider);
  if (userValue.isLoading && !userValue.hasValue) return const SessionLoading();
  final user = userValue.value;
  if (user == null) return const SignedOut();

  final familiesValue = ref.watch(myFamiliesProvider);
  final families = familiesValue.value;
  if (families == null) {
    return familiesValue.hasError ? NeedsFamily(user) : const SessionLoading();
  }
  if (families.isEmpty) return NeedsFamily(user);
  final preferred = prefs.activeFamilyId;
  final active = families.any((f) => f.id == preferred)
      ? preferred!
      : families.first.id;
  return SessionReady(user, active);
});

/// Sobrescritura de [activeFamilyIdProvider] basada en la sesión.
final Override activeFamilyIdOverride = activeFamilyIdProvider.overrideWith((
  ref,
) {
  final session = ref.watch(sessionProvider);
  return session is SessionReady ? session.familyId : null;
});
