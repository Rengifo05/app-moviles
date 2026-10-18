import 'package:meta/meta.dart';
import 'package:nexo_familia/core/result.dart';

/// Permiso del sistema para mostrar avisos.
enum PushPermission { notDetermined, granted, denied }

/// Aviso SOS tocado por la persona: abre esa alerta.
@immutable
final class PushOpen {
  const new({required this.familyId, required this.alertId});

  final String familyId;
  final String alertId;

  @override
  bool operator ==(Object other) =>
      other is PushOpen &&
      other.familyId == familyId &&
      other.alertId == alertId;

  @override
  int get hashCode => Object.hash(familyId, alertId);
}

/// Avisos push del sistema (ADR-005).
abstract interface class PushService {
  /// `false` sin un servicio de avisos configurado (modo demostración o
  /// proyecto sin push): la app lo dice y nunca finge que habrá avisos.
  bool get isAvailable;

  Future<PushPermission> permission();

  /// Muestra el diálogo del sistema. Llamarlo solo tras explicar para qué.
  Future<PushPermission> requestPermission();

  /// Token de este dispositivo, o `null` si no hay (sin permiso o sin red).
  Future<String?> token();

  Stream<String> get tokenRefreshes;

  /// Avisos SOS tocados (incluido el que abrió la app).
  Stream<PushOpen> get opened;

  /// Abre los ajustes de la app en el sistema (para activar los avisos
  /// después de haberlos denegado). `false` si no se pudieron abrir.
  Future<bool> openSystemSettings();

  /// Invalida el token de este teléfono en el servicio de avisos (el
  /// siguiente será otro). Nunca lanza: sin red, no hace nada.
  Future<void> deleteToken();
}

/// Registro de este dispositivo para recibir los avisos de la familia
/// (`users/{uid}/devices/{id}`).
abstract interface class DeviceRegistry {
  Future<VoidResult> register(String token);

  /// Antes de cerrar sesión: un teléfono que ya no es de la persona no debe
  /// recibir alertas de su familia.
  Future<VoidResult> unregister(String token);
}
