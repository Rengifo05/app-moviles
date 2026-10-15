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
final class FirestoreRemoteStore implements RemoteStore {
  new(this._db);

  final fs.FirebaseFirestore _db;

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
        .snapshots()
        .map(
          (snap) => [
            for (final doc in snap.docs)
              RemoteDoc(doc.id, _fromMap(doc.data())),
          ],
        )
        .handleError((Object e, StackTrace s) => throw mapFirebaseError(e));
  }

  @override
  Stream<RemoteDoc?> watchDoc(String path) => _db
      .doc(path)
      .snapshots()
      .map((snap) {
        final data = snap.data();
        return data == null ? null : RemoteDoc(snap.id, _fromMap(data));
      })
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
      final batch = _db.batch();
      for (final w in writes) {
        final ref = _db.doc(w.path);
        switch (w.op) {
          case RemoteOp.put:
            batch.set(ref, _toMap(w.data!));
          case RemoteOp.merge:
            batch.set(ref, _toMap(w.data!), fs.SetOptions(merge: true));
          case RemoteOp.remove:
            batch.delete(ref);
        }
      }
      await batch.commit();
      return const Ok(null);
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
