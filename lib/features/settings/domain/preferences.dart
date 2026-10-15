import 'package:meta/meta.dart';

/// Preferencias locales del dispositivo (no se sincronizan).
@immutable
final class AppPreferences {
  const new({
    this.onboardingCompleted = false,
    this.activeFamilyId,
    this.hideNotificationDetails = false,
  });

  final bool onboardingCompleted;
  final String? activeFamilyId;

  /// Oculta nombres y detalles de las notificaciones en la pantalla de
  /// bloqueo (amenaza 11).
  final bool hideNotificationDetails;

  AppPreferences copyWith({
    bool? onboardingCompleted,
    String? Function()? activeFamilyId,
    bool? hideNotificationDetails,
  }) => AppPreferences(
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    activeFamilyId: activeFamilyId != null
        ? activeFamilyId()
        : this.activeFamilyId,
    hideNotificationDetails:
        hideNotificationDetails ?? this.hideNotificationDetails,
  );
}

abstract interface class PreferencesRepository {
  Stream<AppPreferences> watch();

  Future<AppPreferences> read();

  Future<void> update(AppPreferences Function(AppPreferences) change);

  /// Borra todas las preferencias (al cerrar sesión o eliminar la cuenta).
  Future<void> clear();
}
