import 'package:meta/meta.dart';
import 'package:nexo_familia/core/failure.dart';
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

enum RemoteOp { put, merge, remove, create }

/// Una escritura dentro de un lote atómico.
@immutable
final class RemoteWrite {
  /// Crea o reemplaza el documento completo.
  const new put(this.path, Json this.data) : op = RemoteOp.put;

  /// Fusiona campos con el documento existente (o lo crea).
  const new merge(this.path, Json this.data) : op = RemoteOp.merge;

  const new remove(this.path) : op = RemoteOp.remove, data = null;

  /// Crea el documento solo si no existe; si ya existe no hace nada y el
  /// lote sigue siendo correcto. Es la escritura idempotente de los
  /// documentos de solo inserción (eventos): el reintento de un envío que sí
  /// llegó al servidor no choca con las reglas, que prohíben modificarlos.
  const new create(this.path, Json this.data) : op = RemoteOp.create;

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

/// Error no terminal de las escuchas: el servidor no responde y lo último
/// recibido puede estar desactualizado. La escucha sigue abierta.
const offlineSignal = Failure(FailureKind.network, 'served-from-cache');

/// Acceso mínimo a un almacén de documentos (Firestore o el backend de
/// demostración). Las rutas siguen el formato de Firestore:
/// `families/{familyId}/members/{uid}`.
///
/// Los `Stream` emiten errores de tipo `Failure` y, como las escuchas de
/// Firestore, terminan tras el primer error: para seguir recibiendo datos
/// hay que suscribirse de nuevo. Única excepción: [offlineSignal], que avisa
/// de que el servidor no responde mientras la escucha sigue abierta (vuelve
/// a emitir datos al reconectar). Los `Future` devuelven `Result`. La
/// autorización la decide el backend (reglas de Firestore), nunca el
/// cliente.
abstract interface class RemoteStore {
  Stream<List<RemoteDoc>> watchCollection(String path, {RemoteQuery? query});

  Stream<RemoteDoc?> watchDoc(String path);

  Future<Result<RemoteDoc?>> getDoc(String path);

  /// Aplica todas las escrituras o ninguna. Sin conexión con el servidor
  /// **falla** (error transitorio) en lugar de quedar en espera: la bandeja
  /// de salida decide cuándo reintentar y la interfaz nunca da por hecho lo
  /// que el servidor no confirmó (ADR-004).
  Future<VoidResult> commit(List<RemoteWrite> writes);
}

/// Invoca lógica confiable del servidor (Cloud Functions).
abstract interface class FunctionsClient {
  Future<Result<Json>> call(String name, Json payload);
}
