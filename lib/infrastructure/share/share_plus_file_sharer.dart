import 'dart:convert';

import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/settings/domain/data_export.dart';
import 'package:share_plus/share_plus.dart';

/// [FileSharer] con la hoja de compartir del sistema (`share_plus`).
///
/// `share_plus` escribe el archivo en el directorio temporal de la app (no
/// se copia a la nube: ver data_extraction_rules.xml) para entregarlo.
final class SharePlusFileSharer implements FileSharer {
  const new();

  @override
  Future<VoidResult> share(DataExport file) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              utf8.encode(file.contents),
              mimeType: 'application/json',
              name: file.fileName,
            ),
          ],
          fileNameOverrides: [file.fileName],
          subject: file.fileName,
        ),
      );
      return const Ok(null);
    } on Object catch (e) {
      return Err(Failure.unexpected('share', e));
    }
  }
}
