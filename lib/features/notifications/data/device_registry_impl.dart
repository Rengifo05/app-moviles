import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/notifications/domain/push.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';

/// [DeviceRegistry] sobre el almacén remoto (reglas: solo el dueño escribe
/// sus dispositivos; `platform` es `android` o `ios`).
///
/// El id del documento es un hash del token: registrar dos veces el mismo
/// token es inocuo y el teléfono puede borrar exactamente su registro al
/// cerrar sesión o cuando FCM renueva el token, sin guardar nada más.
final class DeviceRegistryImpl implements DeviceRegistry {
  new({
    required this._remote,
    required this._currentUid,
    required this._platform,
  });

  final RemoteStore _remote;
  final String? Function() _currentUid;

  /// `android` o `ios`.
  final String _platform;

  /// Id del documento de un token (no revela el token).
  static String deviceIdOf(String token) =>
      sha256.convert(utf8.encode(token)).toString().substring(0, 32);

  @override
  Future<VoidResult> register(String token) async {
    final uid = _currentUid();
    if (uid == null) return const Err(Failure.unauthenticated());
    return await _remote.commit([
      RemoteWrite.put(BackendPaths.device(uid, deviceIdOf(token)), {
        'token': token,
        'platform': _platform,
        'updatedAt': serverTimestamp,
      }),
    ]);
  }

  @override
  Future<VoidResult> unregister(String token) async {
    final uid = _currentUid();
    if (uid == null) return const Err(Failure.unauthenticated());
    return await _remote.commit([
      RemoteWrite.remove(BackendPaths.device(uid, deviceIdOf(token))),
    ]);
  }
}
