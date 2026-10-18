import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/notifications/domain/push.dart';
import 'package:nexo_familia/features/notifications/domain/push_registration.dart';

/// Servicio de avisos. Por defecto no hay ninguno: la raíz de composición
/// lo conecta (FCM con Firebase; ninguno en el modo demostración).
final pushServiceProvider = Provider<PushService>(
  (ref) => const _NoPushService(),
);

final deviceRegistryProvider = Provider<DeviceRegistry>(
  (ref) => const _NoDeviceRegistry(),
);

final pushRegistrationProvider = Provider<PushRegistration>(
  (ref) => PushRegistration(
    service: ref.watch(pushServiceProvider),
    registry: ref.watch(deviceRegistryProvider),
  ),
);

/// Permiso actual del sistema (se vuelve a leer al invalidarlo).
final FutureProvider<PushPermission> pushPermissionProvider =
    FutureProvider.autoDispose<PushPermission>(
      (ref) => ref.watch(pushServiceProvider).permission(),
    );

final class _NoPushService implements PushService {
  const new();

  @override
  bool get isAvailable => false;

  @override
  Future<PushPermission> permission() async => PushPermission.notDetermined;

  @override
  Future<PushPermission> requestPermission() async =>
      PushPermission.notDetermined;

  @override
  Future<String?> token() async => null;

  @override
  Future<void> deleteToken() async {}

  @override
  Future<bool> openSystemSettings() async => false;

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();

  @override
  Stream<PushOpen> get opened => const Stream.empty();
}

final class _NoDeviceRegistry implements DeviceRegistry {
  const new();

  @override
  Future<VoidResult> register(String token) async => const Ok(null);

  @override
  Future<VoidResult> unregister(String token) async => const Ok(null);
}
