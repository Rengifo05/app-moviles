import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/settings/data/data_export_repository_impl.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';

final class _Functions implements FunctionsClient {
  new(this.response);

  Result<Json> response;
  final List<String> calls = [];

  @override
  Future<Result<Json>> call(String name, Json payload) async {
    calls.add(name);
    return response;
  }
}

void main() {
  test('entrega el JSON legible con un nombre de archivo fechado', () async {
    final functions = _Functions(
      const Ok({
        'schema': 'nexo-familia/export@1',
        'generatedAt': '2026-10-18T05:00:00.000Z',
        'data': {
          'profile': {'displayName': 'Ana Prueba'},
        },
      }),
    );
    final result = await DataExportRepositoryImpl(functions).exportMyData();
    expect(functions.calls, ['exportMyData']);
    final file = result.valueOrNull!;
    expect(file.fileName, 'nexo-familia-mis-datos-2026-10-18.json');
    expect(file.contents, contains('\n  "schema"'));
    expect((jsonDecode(file.contents) as Map)['data'], {
      'profile': {'displayName': 'Ana Prueba'},
    });
  });

  test('un formato desconocido no se entrega', () async {
    final result = await DataExportRepositoryImpl(
      _Functions(
        const Ok({'schema': 'otro@9', 'generatedAt': '2026-10-18T05:00:00Z'}),
      ),
    ).exportMyData();
    expect(result, const Err<void>(Failure.unexpected('export-schema')));
  });

  test('propaga el fallo del servidor', () async {
    final result = await DataExportRepositoryImpl(
      _Functions(const Err(Failure(FailureKind.rateLimited, 'rate-limited'))),
    ).exportMyData();
    expect(
      result,
      const Err<void>(Failure(FailureKind.rateLimited, 'rate-limited')),
    );
  });
}
