import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/notifications/data/device_registry_impl.dart';
import 'package:nexo_familia/infrastructure/demo/in_memory_remote_store.dart';

import '../../../helpers/fakes.dart';

void main() {
  late InMemoryRemoteStore store;
  String? uid;

  DeviceRegistryImpl registry({String platform = 'android'}) =>
      DeviceRegistryImpl(
        remote: store,
        currentUid: () => uid,
        platform: platform,
      );

  setUp(() {
    store = InMemoryRemoteStore(clock: FakeClock());
    uid = 'ana';
  });

  test('el id del documento es un hash estable que no revela el token', () {
    final id = DeviceRegistryImpl.deviceIdOf('token-sintetico-1');
    expect(id, hasLength(32));
    expect(id, isNot(contains('token')));
    expect(DeviceRegistryImpl.deviceIdOf('token-sintetico-1'), id);
    expect(DeviceRegistryImpl.deviceIdOf('token-sintetico-2'), isNot(id));
  });

  test('registra el token en los dispositivos de la persona', () async {
    final result = await registry(platform: 'ios').register('token-1');
    expect(result.isOk, isTrue);
    final id = DeviceRegistryImpl.deviceIdOf('token-1');
    final doc = store.snapshot['users/ana/devices/$id'];
    expect(doc, isNotNull);
    expect(doc!['token'], 'token-1');
    expect(doc['platform'], 'ios');
    expect(doc['updatedAt'], isA<DateTime>());
  });

  test('registrar dos veces el mismo token deja un solo documento', () async {
    await registry().register('token-1');
    await registry().register('token-1');
    expect(
      store.snapshot.keys.where((k) => k.startsWith('users/ana/devices/')),
      hasLength(1),
    );
  });

  test('borrar quita solo el registro de ese token', () async {
    await registry().register('token-1');
    await registry().register('token-2');
    await registry().unregister('token-1');
    final keys = store.snapshot.keys.where(
      (k) => k.startsWith('users/ana/devices/'),
    );
    expect(keys, [
      'users/ana/devices/${DeviceRegistryImpl.deviceIdOf('token-2')}',
    ]);
  });

  test('sin sesión no escribe nada', () async {
    uid = null;
    expect(
      await registry().register('token-1'),
      const Err<void>(Failure.unauthenticated()),
    );
    expect(
      await registry().unregister('token-1'),
      const Err<void>(Failure.unauthenticated()),
    );
    expect(store.snapshot, isEmpty);
  });

  test('sin red devuelve el fallo', () async {
    store.simulatedFailure = const Failure.network();
    final result = await registry().register('token-1');
    expect(result, const Err<void>(Failure.network()));
  });
}
