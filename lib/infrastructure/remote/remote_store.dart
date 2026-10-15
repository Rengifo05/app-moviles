import 'package:meta/meta.dart';
import 'package:nexo_familia/core/result.dart';

/// Documento JSON tal como lo devuelve el backend.
typedef Json = Map<String, Object?>;

@immutable
final class RemoteDoc {
  const new(this.id, this.data);

  final String id;
  final Json data;
}

/// Marcador que las implementaciones sustituyen por la hora del servidor.
final class ServerTimestamp {
  const new();
}

/// Valor de un campo para que el servidor fije la hora.
const Object serverTimestamp = ServerTimestamp();

enum RemoteOp { put, merge, remove }

/// Una escritura dentro de un lote atómico.
@immutable
final class RemoteWrite {
  /// Crea o reemplaza el documento completo.
  const new put(this.path, Json this.data) : op = RemoteOp.put;

  /// Fusiona campos con el documento existente (o lo crea).
  const new merge(this.path, Json this.data) : op = RemoteOp.merge;

  const new remove(this.path) : op = RemoteOp.remove, data = null;

  final String path;
  final RemoteOp op;
  final Json? data;
}

/// Consulta simple sobre una colección.
@immutable
final class RemoteQuery {
  const new({
    this.orderBy,
    this.descending = false,
    this.limit,
    this.whereEquals,
  });

  final String? orderBy;
  final bool descending;
  final int? limit;
  final Map<String, Object?>? whereEquals;
}

/// Acceso mínimo a un almacén de documentos (Firestore o el backend de
/// demostración). Las rutas siguen el formato de Firestore:
/// `families/{familyId}/members/{uid}`.
///
/// Los `Stream` emiten errores de tipo `Failure` y, como las escuchas de
/// Firestore, terminan tras el primer error: para seguir recibiendo datos
/// hay que suscribirse de nuevo. Los `Future` devuelven `Result`. La
/// autorización la decide el backend (reglas de Firestore), nunca el
/// cliente.
abstract interface class RemoteStore {
  Stream<List<RemoteDoc>> watchCollection(String path, {RemoteQuery? query});

  Stream<RemoteDoc?> watchDoc(String path);

  Future<Result<RemoteDoc?>> getDoc(String path);

  /// Aplica todas las escrituras o ninguna.
  Future<VoidResult> commit(List<RemoteWrite> writes);
}

/// Invoca lógica confiable del servidor (Cloud Functions).
abstract interface class FunctionsClient {
  Future<Result<Json>> call(String name, Json payload);
}
