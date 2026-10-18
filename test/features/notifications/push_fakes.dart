import 'dart:async';

import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/notifications/domain/push.dart';

/// Servicio de avisos controlable (tokens sintéticos, sin FCM).
final class FakePushService implements PushService {
  new({
    this.available = true,
    this.current = PushPermission.granted,
    this.afterRequest = PushPermission.granted,
    this.currentToken = 'token-a',
  });

  bool available;
  PushPermission current;
  PushPermission afterRequest;
  String? currentToken;
  int requests = 0;
  int deletedTokens = 0;
  int settingsOpened = 0;
  final StreamController<String> refreshes = StreamController.broadcast();
  final StreamController<PushOpen> opens = StreamController.broadcast();

  @override
  bool get isAvailable => available;

  @override
  Future<PushPermission> permission() async => current;

  @override
  Future<PushPermission> requestPermission() async {
    requests++;
    return current = afterRequest;
  }

  @override
  Future<String?> token() async => currentToken;

  @override
  Future<bool> openSystemSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Future<void> deleteToken() async {
    deletedTokens++;
    currentToken = 'token-${deletedTokens + 1}';
  }

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Stream<PushOpen> get opened => opens.stream;
}

/// Registro de dispositivos en memoria que anota cada llamada.
final class FakeDeviceRegistry implements DeviceRegistry {
  final List<String> registered = [];
  final List<String> unregistered = [];
  bool offline = false;

  @override
  Future<VoidResult> register(String token) async {
    if (offline) return const Err(Failure.network());
    registered.add(token);
    return const Ok(null);
  }

  @override
  Future<VoidResult> unregister(String token) async {
    if (offline) return const Err(Failure.network());
    unregistered.add(token);
    return const Ok(null);
  }
}
