import 'dart:convert';

import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/settings/domain/data_export.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';

/// [DataExportRepository] sobre la Function `exportMyData`
/// (`docs/architecture/05-api-backend.md`). No registra el contenido.
final class DataExportRepositoryImpl implements DataExportRepository {
  new(this._functions);

  final FunctionsClient _functions;

  /// Formato que esta versión de la app sabe entregar.
  static const schema = 'nexo-familia/export@1';

  @override
  Future<Result<DataExport>> exportMyData() async {
    final result = await _functions.call(BackendFunctions.exportMyData, {});
    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: final data):
        final generatedAt = data['generatedAt'];
        if (data['schema'] != schema || generatedAt is! String) {
          // Nunca se entrega un archivo con un formato desconocido.
          return const Err(Failure.unexpected('export-schema'));
        }
        final day = generatedAt.length >= 10
            ? generatedAt.substring(0, 10)
            : 'sin-fecha';
        return Ok(
          DataExport(
            fileName: 'nexo-familia-mis-datos-$day.json',
            contents: const JsonEncoder.withIndent('  ').convert(data),
          ),
        );
    }
  }
}
