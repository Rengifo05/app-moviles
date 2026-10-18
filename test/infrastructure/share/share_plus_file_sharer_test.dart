import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/features/settings/domain/data_export.dart';
import 'package:nexo_familia/infrastructure/share/share_plus_file_sharer.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  late Directory temp;

  setUp(() async => temp = await Directory.systemTemp.createTemp('nx-share'));
  tearDown(() => temp.delete(recursive: true));

  const file = DataExport(
    fileName: 'nexo-familia-mis-datos-2026-01-01.json',
    contents: '{"schema": "nexo-familia/export@1"}',
  );

  test('comparte el archivo y lo borra al cerrarse la hoja', () async {
    String? seen;
    final sharer = SharePlusFileSharer(
      tempDir: () async => temp,
      share: (params) async {
        final path = params.files!.single.path;
        seen = await File(path).readAsString();
      },
    );
    expect((await sharer.share(file)).isOk, isTrue);
    expect(seen, file.contents);
    expect(temp.listSync(recursive: true), isEmpty);
  });

  test('si compartir falla, también lo borra', () async {
    final sharer = SharePlusFileSharer(
      tempDir: () async => temp,
      share: (_) async => throw StateError('sin hoja'),
    );
    expect((await sharer.share(file)).isOk, isFalse);
    expect(temp.listSync(recursive: true), isEmpty);
  });

  test('al arrancar borra una exportación que quedó a medias', () async {
    final leftover = File('${temp.path}/nexo_exports/viejo.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{}');
    await SharePlusFileSharer(tempDir: () async => temp).discardLeftovers();
    expect(leftover.existsSync(), isFalse);
  });

  test('ShareParams sigue aceptando archivos por ruta', () {
    expect(
      ShareParams(files: [XFile('/x/y.json')]).files!.single.path,
      '/x/y.json',
    );
  });
}
