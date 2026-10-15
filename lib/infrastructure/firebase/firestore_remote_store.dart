import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';

/// [RemoteStore] sobre Cloud Firestore.
///
/// Traduce en ambos sentidos: `Timestamp` ↔ `DateTime` (UTC),
/// [serverTimestamp] → `FieldValue.serverTimestamp()`, y los errores de
/// Firebase a [Failure]. La autorización la aplican las reglas.
///
/// Dos diferencias deliberadas con el comportamiento por defecto de
/// Firestore (ADR-004):
/// * Las escrituras van en una **transacción**, que falla sin conexión. Un
///   lote (`WriteBatch`) quedaría en espera indefinida y Firestore lo
///   mostraría como aplicado antes de que el servidor lo acepte: la bandeja
///   de salida no podría reintentar ni la interfaz ser honesta.
/// * Las escuchas piden los metadatos: una instantánea servida desde la
///   caché local se notifica como [offlineSignal] en lugar de como datos
///   frescos del servidor.
final class FirestoreRemoteStore implements RemoteStore {
  new(this._db);

  final fs.FirebaseFirestore _db;

  /// Tiempo máximo de una escritura; pasado, falla como transitoria.
  static const commitTimeout = Duration(seconds: 15);

  @override
  Stream<List<RemoteDoc>> watchCollection(String path, {RemoteQuery? query}) {
    fs.Query<Map<String, dynamic>> q = _db.collection(path);
    final q0 = query;
    if (q0 != null) {
      for (final MapEntry(:key, :value)
          in (q0.whereEquals ?? const {}).entries) {
        q = q.where(key, isEqualTo: _toFirestore(value));
      }
      if (q0.orderBy case final field?) {
        q = q.orderBy(field, descending: q0.descending);
      }
      if (q0.limit case final limit?) q = q.limit(limit);
    }
    return q
        .snapshots(includeMetadataChanges: true)
        .transform(
          serverSnapshots(
            (snap) => snap.metadata.isFromCache,
            (snap) => [
              for (final doc in snap.docs)
                RemoteDoc(doc.id, _fromMap(doc.data())),
            ],
          ),
        )
        .handleError((Object e, StackTrace s) => throw mapFirebaseError(e));
  }

  @override
  Stream<RemoteDoc?> watchDoc(String path) => _db
      .doc(path)
      .snapshots(includeMetadataChanges: true)
      .transform(
        serverSnapshots((snap) => snap.metadata.isFromCache, (snap) {
          final data = snap.data();
          return data == null ? null : RemoteDoc(snap.id, _fromMap(data));
        }),
      )
      .handleError((Object e, StackTrace s) => throw mapFirebaseError(e));

  @override
  Future<Result<RemoteDoc?>> getDoc(String path) async {
    try {
      final snap = await _db.doc(path).get();
      final data = snap.data();
      return Ok(data == null ? null : RemoteDoc(snap.id, _fromMap(data)));
    } on Object catch (e) {
      return Err(mapFirebaseError(e));
    }
  }

  @override
  Future<VoidResult> commit(List<RemoteWrite> writes) async {
    if (writes.isEmpty) return const Ok(null);
    try {
      await _db.runTransaction<void>((tx) async {
        // Firestore exige hacer todas las lecturas antes de escribir.
        final existing = <String>{};
        for (final w in writes) {
          if (w.op != RemoteOp.create) continue;
          if ((await tx.get(_db.doc(w.path))).exists) existing.add(w.path);
        }
        for (final w in writes) {
          final ref = _db.doc(w.path);
          switch (w.op) {
            case RemoteOp.put:
              tx.set(ref, _toMap(w.data!));
            case RemoteOp.merge:
              tx.set(ref, _toMap(w.data!), fs.SetOptions(merge: true));
            case RemoteOp.remove:
              tx.delete(ref);
            case RemoteOp.create:
              // Ya existe: un reintento de algo que el servidor ya aceptó.
              if (!existing.contains(w.path)) tx.set(ref, _toMap(w.data!));
          }
        }
      }, timeout: commitTimeout);
      return const Ok(null);
    } on TimeoutException catch (e) {
      return Err(Failure.unavailable('timeout', e));
    } on Object catch (e) {
      return Err(mapFirebaseError(e));
    }
  }

  static Map<String, Object?> _toMap(Json data) => {
    for (final MapEntry(:key, :value) in data.entries) key: _toFirestore(value),
  };

  static Object? _toFirestore(Object? value) => switch (value) {
    ServerTimestamp() => fs.FieldValue.serverTimestamp(),
    final DateTime d => fs.Timestamp.fromDate(d.toUtc()),
    final Map<String, Object?> m => _toMap(m),
    final List<Object?> l => [for (final v in l) _toFirestore(v)],
    _ => value,
  };

  static Json _fromMap(Map<String, dynamic> data) => {
    for (final MapEntry(:key, :value) in data.entries)
      key: _fromFirestore(value),
  };

  static Object? _fromFirestore(Object? value) => switch (value) {
    final fs.Timestamp t => t.toDate().toUtc(),
    final Map<String, dynamic> m => _fromMap(m),
    final List<dynamic> l => [for (final v in l) _fromFirestore(v)],
    _ => value,
  };
}

/// Deja pasar solo los datos confirmados por el servidor: una instantánea
/// de la caché local se convierte en [offlineSignal] (error no terminal),
/// una sola vez por cada pérdida de conexión.
StreamTransformer<S, T> serverSnapshots<S, T>(
  bool Function(S snapshot) isFromCache,
  T Function(S snapshot) convert,
) {
  var offline = false;
  return StreamTransformer.fromHandlers(
    handleData: (snapshot, sink) {
      if (isFromCache(snapshot)) {
        if (!offline) sink.addError(offlineSignal);
        offline = true;
      } else {
        offline = false;
        sink.add(convert(snapshot));
      }
    },
  );
}

/// Traduce un error de Firebase a [Failure] sin conservar el mensaje (puede
/// contener rutas con identificadores); la causa queda solo para depurar.
Failure mapFirebaseError(Object error) {
  if (error is Failure) return error;
  final code = error is fs.FirebaseException ? error.code : 'unknown';
  return switch (code) {
    'permission-denied' => Failure.permissionDenied('permission-denied', error),
    'unauthenticated' => const Failure.unauthenticated(),
    'not-found' => const Failure.notFound(),
    'already-exists' || 'aborted' => const Failure.conflict(),
    'failed-precondition' => const Failure.conflict('failed-precondition'),
    'invalid-argument' ||
    'out-of-range' => const Failure.validation('invalid-argument'),
    'resource-exhausted' => const Failure(
      FailureKind.rateLimited,
      'resource-exhausted',
    ),
    'unavailable' ||
    'deadline-exceeded' ||
    'cancelled' => Failure.unavailable(code, error),
    _ => Failure.unexpected('firestore', error),
  };
}
