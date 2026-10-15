import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/settings/domain/preferences.dart';
import 'package:nexo_familia/features/settings/presentation/settings_providers.dart';

/// Cerrar sesión y eliminar la cuenta desde Ajustes.
///
/// Tras un `Ok` se olvida la familia activa guardada en el teléfono (es de
/// la cuenta anterior). El resto de preferencias son del dispositivo
/// (onboarding visto, ocultar detalles) y se conservan. La copia local de
/// las familias la purga el coordinador de sincronización al cerrarse la
/// sesión (ADR-004).
final class AccountActions {
  new({required this._auth, required this._preferences, required this._logger});

  final AuthRepository _auth;
  final PreferencesRepository _preferences;
  final SafeLogger _logger;

  Future<VoidResult> signOut() => _afterOk('signOut', _auth.signOut());

  /// Cierra la sesión en todos los dispositivos (también en este).
  Future<VoidResult> signOutEverywhere() =>
      _afterOk('signOutEverywhere', _auth.signOutEverywhere());

  /// Elimina la cuenta en el servidor (`deleteAccount`, idempotente: un
  /// reintento tras un fallo parcial continúa donde quedó).
  Future<VoidResult> deleteAccount() =>
      _afterOk('deleteAccount', _auth.deleteAccount());

  Future<VoidResult> _afterOk(String operation, Future<VoidResult> call) async {
    final result = await call;
    switch (result) {
      case Ok():
        try {
          await _preferences.update(
            (p) => p.copyWith(activeFamilyId: () => null),
          );
        } on Object {
          // La operación remota ya se hizo; una preferencia que no coincide
          // con ninguna familia se ignora al iniciar sesión.
          _logger.warning(
            'settings.preferences_write_failed',
            fields: {'feature': 'settings', 'operation': operation},
          );
        }
      case Err(:final failure):
        _logger.warning(
          'settings.account_operation_failed',
          fields: {'feature': 'settings', 'operation': operation},
          failure: failure,
        );
    }
    return result;
  }
}

final accountActionsProvider = Provider<AccountActions>(
  (ref) => AccountActions(
    auth: ref.watch(authRepositoryProvider),
    preferences: ref.watch(preferencesRepositoryProvider),
    logger: ref.watch(loggerProvider),
  ),
);
