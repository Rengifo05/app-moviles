import 'package:nexo_familia/features/notifications/domain/push.dart';

/// Mantiene registrado este dispositivo para los avisos SOS (ADR-005):
/// solo con sesión, servicio disponible y permiso concedido; cambia el
/// registro cuando FCM renueva el token y lo borra antes de cerrar sesión.
final class PushRegistration {
  new({required this._service, required this._registry});

  final PushService _service;
  final DeviceRegistry _registry;

  /// Token registrado en esta ejecución (para poder borrarlo).
  String? _registered;

  /// Registra el token actual si corresponde. Los fallos (sin red) se
  /// reintentan en la próxima llamada: no bloquean nada.
  Future<void> sync() async {
    if (!_service.isAvailable) return;
    if (await _service.permission() != PushPermission.granted) return;
    final token = await _service.token();
    if (token == null || token == _registered) return;
    if ((await _registry.register(token)).isOk) _registered = token;
  }

  /// FCM entregó un token nuevo: se registra y se borra el anterior.
  Future<void> onTokenRefresh(String token) async {
    final previous = _registered;
    if (previous == token) return;
    if ((await _registry.register(token)).isOk) {
      _registered = token;
      if (previous != null) await _registry.unregister(previous);
    }
  }

  /// La sesión terminó sin pasar por [unregister] (por ejemplo, "Cerrar
  /// sesión en todos los dispositivos" desde otro teléfono, que ya borró
  /// los registros en el servidor): la próxima sesión vuelve a registrar.
  void forget() => _registered = null;

  /// Antes de cerrar sesión (con la sesión aún abierta: las reglas exigen
  /// ser el dueño del registro).
  Future<void> unregister() async {
    if (!_service.isAvailable) return;
    final token = _registered ?? await _service.token();
    if (token != null) await _registry.unregister(token);
    _registered = null;
  }
}
