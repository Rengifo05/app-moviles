import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/features/notifications/domain/push.dart';
import 'package:nexo_familia/features/notifications/domain/push_registration.dart';

import '../push_fakes.dart';

void main() {
  late FakePushService service;
  late FakeDeviceRegistry registry;
  late PushRegistration registration;

  setUp(() {
    service = FakePushService();
    registry = FakeDeviceRegistry();
    registration = PushRegistration(service: service, registry: registry);
  });

  test('registra el token una sola vez con permiso concedido', () async {
    await registration.sync();
    await registration.sync();
    expect(registry.registered, ['token-a']);
  });

  test('sin permiso, sin servicio o sin token no registra nada', () async {
    service.current = PushPermission.denied;
    await registration.sync();
    service
      ..current = PushPermission.notDetermined
      ..available = true;
    await registration.sync();
    service
      ..current = PushPermission.granted
      ..currentToken = null;
    await registration.sync();
    service
      ..currentToken = 'token-a'
      ..available = false;
    await registration.sync();
    expect(registry.registered, isEmpty);
  });

  test('sin red, el siguiente intento vuelve a registrar', () async {
    registry.offline = true;
    await registration.sync();
    registry.offline = false;
    await registration.sync();
    expect(registry.registered, ['token-a']);
  });

  test('un token nuevo se registra y el anterior se borra', () async {
    await registration.sync();
    await registration.onTokenRefresh('token-b');
    await registration.onTokenRefresh('token-b');
    expect(registry.registered, ['token-a', 'token-b']);
    expect(registry.unregistered, ['token-a']);
  });

  test(
    'si el token nuevo no se pudo registrar, el anterior se conserva',
    () async {
      await registration.sync();
      registry.offline = true;
      await registration.onTokenRefresh('token-b');
      expect(registry.unregistered, isEmpty);
    },
  );

  test('al cerrar sesión borra el registro de este teléfono', () async {
    await registration.sync();
    await registration.unregister();
    expect(registry.unregistered, ['token-a']);
    // La siguiente sesión vuelve a registrar.
    await registration.sync();
    expect(registry.registered, ['token-a', 'token-a']);
  });

  test('sin registrar en esta ejecución, borra el token actual', () async {
    await registration.unregister();
    expect(registry.unregistered, ['token-a']);
  });

  test('sin servicio no intenta borrar nada', () async {
    service.available = false;
    await registration.unregister();
    expect(registry.unregistered, isEmpty);
  });

  test('forget permite registrar de nuevo en la próxima sesión', () async {
    await registration.sync();
    registration.forget();
    await registration.sync();
    expect(registry.registered, ['token-a', 'token-a']);
  });
}
