import 'dart:io';

import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/settings/domain/data_export.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// [FileSharer] con la hoja de compartir del sistema (`share_plus`).
///
/// El archivo contiene datos personales (ubicación, mensajes): se escribe
/// en una carpeta propia del directorio temporal, se comparte por su ruta y
/// se borra en cuanto la hoja se cierra. `share_plus` hace su propia copia
/// para la app de destino. Si la app se cerrara a mitad, [discardLeftovers]
/// (al arrancar) borra lo que haya quedado.
final class SharePlusFileSharer implements FileSharer {
  const new({this._tempDir = getTemporaryDirectory, this._share});

  final Future<Directory> Function() _tempDir;
  final Future<void> Function(ShareParams params)? _share;

  static const _folder = 'nexo_exports';

  Future<Directory> _exportsDir() async =>
      Directory('${(await _tempDir()).path}/$_folder');

  /// Borra cualquier exportación que haya quedado en el teléfono.
  Future<void> discardLeftovers() async {
    try {
      final dir = await _exportsDir();
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on Object {
      // Sin acceso al directorio: no hay nada que borrar.
    }
  }

  @override
  Future<VoidResult> share(DataExport file) async {
    try {
      await discardLeftovers();
      final dir = await (await _exportsDir()).create(recursive: true);
      final path = '${dir.path}/${file.fileName}';
      await File(path).writeAsString(file.contents, flush: true);
      try {
        final params = ShareParams(
          files: [XFile(path, mimeType: 'application/json')],
          subject: file.fileName,
        );
        final share = _share;
        if (share != null) {
          await share(params);
        } else {
          await SharePlus.instance.share(params);
        }
      } finally {
        await discardLeftovers();
      }
      return const Ok(null);
    } on Object catch (e) {
      return Err(Failure.unexpected('share', e));
    }
  }
}
