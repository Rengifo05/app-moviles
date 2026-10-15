import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/settings/domain/preferences.dart';
import 'package:nexo_familia/features/settings/presentation/settings_providers.dart';

/// Operaciones de familia que dispara la interfaz.
///
/// Encadena el repositorio con la preferencia local de familia activa: al
/// crear o unirse, la nueva familia pasa a ser la activa (la sesión cambia
/// sola y el enrutador lleva a Inicio); al salir, se olvida.
///
/// Ninguna va por la bandeja de salida: todas necesitan la respuesta del
/// servidor (permisos, códigos de un solo uso) y la interfaz solo confirma
/// después de recibirla.
final class FamilyActions {
  new({
    required this._families,
    required this._preferences,
    required this._logger,
  });

  final FamilyRepository _families;
  final PreferencesRepository _preferences;
  final SafeLogger _logger;

  Future<Result<FamilyGroup>> createFamily(String name) async {
    final result = await _families.createFamily(name.trim());
    switch (result) {
      case Ok(:final value):
        await _activate(value.id);
      case Err(:final failure):
        _warn('createFamily', failure);
    }
    return result;
  }

  /// Se une con un código tal como lo escribió la persona (el repositorio
  /// lo normaliza).
  Future<Result<String>> joinWithCode(String code) async {
    final result = await _families.acceptInvitation(code.trim());
    switch (result) {
      case Ok(:final value):
        await _activate(value);
      case Err(:final failure):
        _warn('acceptInvitation', failure);
    }
    return result;
  }

  Future<Result<CreatedInvitation>> createInvitation(String familyId) async {
    final result = await _families.createInvitation(familyId);
    if (result case Err(:final failure)) _warn('createInvitation', failure);
    return result;
  }

  Future<VoidResult> leave(String familyId) async {
    final result = await _families.leaveFamily(familyId);
    switch (result) {
      case Ok():
        await _updatePreferences(
          (p) => p.activeFamilyId == familyId
              ? p.copyWith(activeFamilyId: () => null)
              : p,
        );
      case Err(:final failure):
        _warn('leaveFamily', failure);
    }
    return result;
  }

  Future<VoidResult> removeMember(String familyId, String uid) async {
    final result = await _families.removeMember(familyId, uid);
    if (result case Err(:final failure)) _warn('removeMember', failure);
    return result;
  }

  /// Cambia la familia activa (solo es una preferencia local).
  Future<VoidResult> switchTo(String familyId) =>
      _updatePreferences((p) => p.copyWith(activeFamilyId: () => familyId));

  /// Si guardar la preferencia falla, la operación remota ya se hizo: la
  /// sesión elige entonces la primera familia disponible.
  Future<void> _activate(String familyId) async {
    await switchTo(familyId);
  }

  Future<VoidResult> _updatePreferences(
    AppPreferences Function(AppPreferences) change,
  ) async {
    try {
      await _preferences.update(change);
      return const Ok(null);
    } on Object catch (error) {
      final failure = Failure.unexpected('preferences-write', error);
      _warn('updatePreferences', failure);
      return Err(failure);
    }
  }

  void _warn(String operation, Failure failure) => _logger.warning(
    'family.operation_failed',
    fields: {'feature': 'family', 'operation': operation},
    failure: failure,
  );
}

final familyActionsProvider = Provider<FamilyActions>(
  (ref) => FamilyActions(
    families: ref.watch(familyRepositoryProvider),
    preferences: ref.watch(preferencesRepositoryProvider),
    logger: ref.watch(loggerProvider),
  ),
);
