import 'dart:async';

import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';

/// Almacén de documentos en memoria con la misma semántica básica que
/// Firestore (rutas, lotes atómicos, hora del servidor, escuchas en vivo).
///
/// Lo usa el backend de demostración y las pruebas. **No aplica reglas de
/// seguridad**: la autorización real se prueba contra el emulador de
/// Firestore (`firestore/test/`).
///
/// Semántica de Firestore que reproduce:
/// * Sin `orderBy`, una consulta devuelve los documentos por ID.
/// * `orderBy` excluye los documentos que no tienen el campo y ordena por
///   tipo (null < bool < número < fecha < texto) y, a igualdad, por ID.
///   `descending` solo tiene efecto junto con `orderBy`.
/// * `whereEquals` solo coincide si el campo existe (`null` explícito no
///   equivale a ausente) y compara listas y mapas por contenido y fechas por
///   instante.
/// * `limit` debe ser al menos 1.
/// * Un error termina la escucha: para seguir hay que suscribirse de nuevo.
/// * `merge` fusiona en profundidad los mapas anidados.
/// * Rutas con segmentos vacíos, IDs reservados (`.`, `..`, `__…__`) o del
///   tipo equivocado → `invalid-path`.
/// * Todo lo que entra y sale se copia en profundidad: mutar un documento
///   devuelto, o el mapa que se escribió, no altera el almacén.
final class InMemoryRemoteStore implements RemoteStore {
  new({this._clock = const SystemClock()});

  final Clock _clock;
  final Map<String, Json> _docs = {};
  final StreamController<void> _changes = StreamController.broadcast(
    sync: true,
  );
  int _transactionDepth = 0;
  bool _pendingChange = false;

  /// Instante de la transacción de servidor en curso: como en Firestore,
  /// todas sus marcas `serverTimestamp` lo comparten.
  DateTime? _transactionNow;

  DateTime _now() => _transactionNow ?? _clock.now();

  /// Si es distinto de null, todas las operaciones fallan con este fallo
  /// (simula desconexión o indisponibilidad en pruebas).
  Failure? simulatedFailure;

  /// Reloj con el que se resuelve `serverTimestamp`.
  Clock get clock => _clock;

  /// Copia profunda y de solo lectura del contenido (para pruebas y la
  /// semilla).
  Map<String, Json> get snapshot => Map.unmodifiable({
    for (final MapEntry(:key, :value) in _docs.entries) key: _copy(value),
  });

  static bool _isDocPath(String path) => _isPath(path, doc: true);

  static bool _isCollectionPath(String path) => _isPath(path, doc: false);

  static bool _isPath(String path, {required bool doc}) {
    final segments = path.split('/');
    return segments.length.isEven == doc && segments.every(_isValidId);
  }

  /// Firestore rechaza los IDs vacíos, `.`, `..` y los de la forma `__…__`.
  static bool _isValidId(String id) =>
      id.isNotEmpty && id != '.' && id != '..' && !_reservedId.hasMatch(id);

  static final _reservedId = RegExp(r'^__.*__$');

  static const _invalidPath = Failure.validation('invalid-path');

  @override
  Stream<List<RemoteDoc>> watchCollection(String path, {RemoteQuery? query}) {
    final limit = query?.limit;
    if (limit != null && limit < 1) {
      throw RangeError.range(limit, 1, null, 'limit');
    }
    if (!_isCollectionPath(path)) return Stream.error(_invalidPath);
    return _watch(() => _query(path, query));
  }

  @override
  Stream<RemoteDoc?> watchDoc(String path) {
    if (!_isDocPath(path)) return Stream.error(_invalidPath);
    return _watch(() => _read(path));
  }

  Stream<T> _watch<T>(T Function() read) {
    late StreamController<T> controller;
    StreamSubscription<void>? changes;
    void emit() {
      if (controller.isClosed) return;
      final failure = simulatedFailure;
      if (failure == null) {
        controller.add(read());
        return;
      }
      // Como en Firestore, tras un error la escucha no vuelve a emitir.
      unawaited(changes?.cancel());
      controller.addError(failure);
      unawaited(controller.close());
    }

    controller = StreamController<T>(
      onListen: () {
        // La primera emisión es asíncrona, como en Firestore.
        scheduleMicrotask(emit);
        changes = _changes.stream.listen(
          (_) => emit(),
          onDone: () => unawaited(controller.close()),
        );
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  RemoteDoc? _read(String path) {
    final data = _docs[path];
    return data == null ? null : RemoteDoc(_idOf(path), _copy(data));
  }

  List<RemoteDoc> _query(String collection, RemoteQuery? query) {
    final orderBy = query?.orderBy;
    final where = query?.whereEquals ?? const <String, Object?>{};
    final matches =
        [
          for (final path in serverList(collection))
            if (_matches(_docs[path]!, orderBy, where))
              (id: _idOf(path), data: _docs[path]!),
        ]..sort((a, b) {
          final byField = orderBy == null
              ? 0
              : _compareValues(a.data[orderBy], b.data[orderBy]);
          return byField != 0 ? byField : a.id.compareTo(b.id);
        });
    final ordered = orderBy != null && query!.descending
        ? matches.reversed
        : matches;
    final limit = query?.limit;
    return [
      for (final m in limit == null ? ordered : ordered.take(limit))
        RemoteDoc(m.id, _copy(m.data)),
    ];
  }

  static bool _matches(
    Json data,
    String? orderBy,
    Map<String, Object?> where,
  ) =>
      (orderBy == null || data.containsKey(orderBy)) &&
      where.entries.every(
        (w) => data.containsKey(w.key) && _equals(data[w.key], w.value),
      );

  /// Igualdad de Firestore: listas y mapas por contenido, fechas por instante
  /// (sin importar la zona) y números por valor (`1 == 1.0`).
  static bool _equals(Object? a, Object? b) => switch ((a, b)) {
    (final DateTime x, final DateTime y) => x.isAtSameMomentAs(y),
    (final List<Object?> x, final List<Object?> y) =>
      x.length == y.length &&
          Iterable<int>.generate(x.length).every((i) => _equals(x[i], y[i])),
    (final Map<String, Object?> x, final Map<String, Object?> y) =>
      x.length == y.length &&
          x.entries.every(
            (e) => y.containsKey(e.key) && _equals(e.value, y[e.key]),
          ),
    _ => a == b,
  };

  /// Orden por tipo como en Firestore; dentro del mismo tipo, el natural.
  static int _typeRank(Object? value) => switch (value) {
    null => 0,
    bool() => 1,
    num() => 2,
    DateTime() => 3,
    String() => 4,
    _ => 5,
  };

  static int _compareValues(Object? a, Object? b) {
    final byType = _typeRank(a).compareTo(_typeRank(b));
    if (byType != 0) return byType;
    return switch ((a, b)) {
      (final bool x, final bool y) => x == y ? 0 : (x ? 1 : -1),
      (final num x, final num y) => x.compareTo(y),
      (final DateTime x, final DateTime y) => x.compareTo(y),
      (final String x, final String y) => x.compareTo(y),
      _ => 0,
    };
  }

  @override
  Future<Result<RemoteDoc?>> getDoc(String path) async {
    final failure = simulatedFailure;
    if (failure != null) return Err(failure);
    if (!_isDocPath(path)) return const Err(_invalidPath);
    return Ok(_read(path));
  }

  @override
  Future<VoidResult> commit(List<RemoteWrite> writes) async {
    final failure = simulatedFailure;
    if (failure != null) return Err(failure);
    // Se valida todo antes de escribir nada: el lote es atómico.
    if (!writes.every((w) => _isDocPath(w.path))) {
      return const Err(_invalidPath);
    }
    if (writes.isEmpty) return const Ok(null);
    final now = _now();
    for (final w in writes) {
      switch (w.op) {
        case RemoteOp.put:
          _docs[w.path] = _resolve(w.data!, now);
        case RemoteOp.merge:
          _docs[w.path] = _merge(
            _docs[w.path] ?? const {},
            _resolve(w.data!, now),
          );
        case RemoteOp.remove:
          _docs.remove(w.path);
      }
    }
    _notify();
    return const Ok(null);
  }

  // --- Acceso directo de la lógica de servidor simulada ---------------------

  /// Ejecuta [body] (síncrono) como una transacción de servidor: sus marcas
  /// `serverTimestamp` comparten instante, los observadores ven un único
  /// cambio al final y, si [body] lanza, el almacén vuelve al estado previo
  /// a [body] sin notificar nada. Una transacción anidada usa el instante y
  /// la notificación de la exterior; si lanza, solo se revierte lo suyo (la
  /// exterior puede capturar el error y seguir).
  T serverTransaction<T>(T Function() body) {
    // Copia superficial suficiente: los documentos guardados nunca se
    // mutan en su sitio, siempre se reemplazan.
    final backup = Map.of(_docs);
    final pendingBefore = _pendingChange;
    var completed = false;
    _transactionNow ??= _clock.now();
    _transactionDepth++;
    try {
      final result = body();
      completed = true;
      return result;
    } finally {
      _transactionDepth--;
      if (!completed) {
        _docs
          ..clear()
          ..addAll(backup);
        _pendingChange = pendingBefore;
      }
      if (_transactionDepth == 0) {
        _transactionNow = null;
        if (_pendingChange) {
          _pendingChange = false;
          _changes.add(null);
        }
      }
    }
  }

  /// Escritura directa, usada por la lógica de servidor simulada.
  void serverWrite(String path, Json data) {
    _docs[path] = _resolve(data, _now());
    _notify();
  }

  void serverDelete(String path) {
    if (_docs.remove(path) != null) _notify();
  }

  /// Borra el documento [path] y todo lo que cuelga de él (subcolecciones).
  void serverDeleteTree(String path) {
    final before = _docs.length;
    _docs.removeWhere((k, _) => k == path || k.startsWith('$path/'));
    if (_docs.length != before) _notify();
  }

  Json? serverRead(String path) {
    final data = _docs[path];
    return data == null ? null : _copy(data);
  }

  /// Rutas de los documentos directos de [collection] (sin subcolecciones).
  /// Es una lista nueva: se puede borrar mientras se recorre.
  List<String> serverList(String collection) {
    final depth = collection.split('/').length + 1;
    return [
      for (final k in _docs.keys)
        if (k.startsWith('$collection/') && k.split('/').length == depth) k,
    ];
  }

  void _notify() {
    if (_transactionDepth > 0) {
      _pendingChange = true;
    } else {
      _changes.add(null);
    }
  }

  static String _idOf(String path) => path.substring(path.lastIndexOf('/') + 1);

  // --- Copias y valores especiales ------------------------------------------

  static Json _resolve(Json data, DateTime now) => {
    for (final MapEntry(:key, :value) in data.entries)
      key: _resolveValue(value, now),
  };

  static Object? _resolveValue(Object? value, DateTime now) => switch (value) {
    ServerTimestamp() => now,
    final Map<String, Object?> map => _resolve(map, now),
    final List<Object?> list => [
      for (final item in list) _resolveValue(item, now),
    ],
    _ => value,
  };

  /// Fusión de `merge`: los mapas anidados se combinan campo a campo; un
  /// mapa vacío o cualquier otro valor reemplaza al anterior.
  static Json _merge(Json base, Json patch) => {
    ...base,
    for (final MapEntry(:key, :value) in patch.entries)
      key: switch ((base[key], value)) {
        (final Map<String, Object?> old, final Map<String, Object?> added)
            when added.isNotEmpty =>
          _merge(old, added),
        _ => value,
      },
  };

  static Json _copy(Json data) => {
    for (final MapEntry(:key, :value) in data.entries) key: _copyValue(value),
  };

  static Object? _copyValue(Object? value) => switch (value) {
    final Map<String, Object?> map => _copy(map),
    final List<Object?> list => [for (final item in list) _copyValue(item)],
    _ => value,
  };

  /// Cierra las escuchas abiertas (sus `Stream` terminan).
  Future<void> dispose() => _changes.close();
}
