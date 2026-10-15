import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';

void main() {
  group('RemoteWrite', () {
    test('put y merge guardan la ruta, la operación y los datos', () {
      const put = RemoteWrite.put('items/a', {'n': 1});
      const merge = RemoteWrite.merge('items/a', {'n': 2});
      expect((put.path, put.op), ('items/a', RemoteOp.put));
      expect(put.data, {'n': 1});
      expect((merge.path, merge.op), ('items/a', RemoteOp.merge));
      expect(merge.data, {'n': 2});
    });

    test('remove no lleva datos', () {
      const remove = RemoteWrite.remove('items/a');
      expect(remove.op, RemoteOp.remove);
      expect(remove.data, isNull);
    });
  });

  test('RemoteQuery por defecto es ascendente, sin orden, límite ni '
      'filtros', () {
    const query = RemoteQuery();
    expect(query.orderBy, isNull);
    expect(query.descending, isFalse);
    expect(query.limit, isNull);
    expect(query.whereEquals, isNull);
  });

  test('serverTimestamp es el marcador constante ServerTimestamp', () {
    expect(serverTimestamp, isA<ServerTimestamp>());
    expect(identical(serverTimestamp, const ServerTimestamp()), isTrue);
  });
}
