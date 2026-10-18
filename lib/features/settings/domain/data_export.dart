import 'package:nexo_familia/core/result.dart';

/// Archivo con los datos de la persona (derecho de acceso, Ley 1581).
final class DataExport {
  const new({required this.fileName, required this.contents});

  /// p. ej. `nexo-familia-mis-datos-2026-10-18.json`.
  final String fileName;

  /// JSON legible (con sangría).
  final String contents;
}

/// Pide al servidor los datos de la persona en todas sus familias.
abstract interface class DataExportRepository {
  Future<Result<DataExport>> exportMyData();
}

/// Entrega un archivo a la persona (hoja de compartir del sistema). Que la
/// hoja se cierre sin elegir destino no es un error.
abstract interface class FileSharer {
  Future<VoidResult> share(DataExport file);
}
