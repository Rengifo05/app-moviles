import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';

/// Documento remoto guardado localmente.
@immutable
final class CachedDoc {
  const new(this.id, this.data, this.syncedAt);

  final String id;
  final Json data;

  /// Cuándo llegó del servidor por última vez.
  final DateTime syncedAt;
}

/// Caché local de documentos remotos (Drift en la app, memoria en pruebas).
/// El ámbito (`scope`) es el id de la familia, o [userScope] para datos del
/// usuario.
abstract interface class DocumentCache {
  static const String userScope = '_user';

  Stream<List<CachedDoc>> watchCollection(String collection);

  Stream<CachedDoc?> watchDoc(String collection, String docId);

  /// Reemplaza atómicamente la colección por la instantánea recibida: borra
  /// lo que ya no está y actualiza el resto.
  Future<void> replaceCollection(
    String collection,
    String scope,
    List<RemoteDoc> docs,
    DateTime syncedAt,
  );

  Future<void> upsert(
    String collection,
    String scope,
    RemoteDoc doc,
    DateTime syncedAt,
  );

  Future<void> remove(String collection, String docId);

  /// Purga todo lo de una familia (al salir o perder el acceso).
  Future<void> clearScope(String scope);

  /// Ámbitos con documentos guardados (incluido [userScope] si lo hay).
  Future<Set<String>> scopes();

  Future<void> clearAll();
}

/// Serializa documentos a JSON conservando las fechas (UTC, milisegundos).
///
/// Formato: una fecha se guarda como `{"$date": milisegundos}`. Un mapa del
/// propio documento con una sola clave reservada (`$date` o `$map`) se
/// envuelve como `{"$map": {...}}` para que nunca se confunda con una
/// fecha: la ida y vuelta es exacta para cualquier JSON con fechas.
abstract final class DocumentCodec {
  static const String _dateKey = r'$date';
  static const String _mapKey = r'$map';

  /// Lanza [UnsupportedError] si hay valores que no son JSON (aparte de
  /// [DateTime]): objetos, mapas con claves no textuales, `NaN` o infinito.
  static String encode(Json data) => jsonEncode(_wrap(data));

  static Json decode(String source) => _revive(jsonDecode(source))! as Json;

  /// Un mapa con una única clave reservada se leería como marcador.
  static bool _looksLikeMarker(Map<String, Object?> map) =>
      map.length == 1 &&
      (map.containsKey(_dateKey) || map.containsKey(_mapKey));

  static Object? _wrap(Object? value) => switch (value) {
    null || bool() || int() || String() => value,
    final double d when d.isFinite => d,
    final DateTime dt => {_dateKey: dt.toUtc().millisecondsSinceEpoch},
    final Map<Object?, Object?> map => _wrapMap(map),
    final List<Object?> list => [for (final v in list) _wrap(v)],
    // Solo el tipo: el valor puede contener datos personales.
    _ => throw UnsupportedError('Tipo no serializable: ${value.runtimeType}'),
  };

  static Map<String, Object?> _wrapMap(Map<Object?, Object?> map) {
    final entries = <String, Object?>{};
    for (final MapEntry(:key, :value) in map.entries) {
      if (key is! String) {
        throw UnsupportedError('Clave no textual: ${key.runtimeType}');
      }
      entries[key] = _wrap(value);
    }
    return _looksLikeMarker(entries) ? {_mapKey: entries} : entries;
  }

  static Object? _revive(Object? value) => switch (value) {
    {_dateKey: final int millis} when (value as Map).length == 1 =>
      DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
    {_mapKey: final Map<String, Object?> escaped}
        when (value as Map).length == 1 =>
      _reviveEntries(escaped),
    final Map<String, Object?> map => _reviveEntries(map),
    final List<Object?> list => [for (final v in list) _revive(v)],
    _ => value,
  };

  static Map<String, Object?> _reviveEntries(Map<String, Object?> map) => {
    for (final MapEntry(:key, :value) in map.entries) key: _revive(value),
  };
}
