import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';

/// [FunctionsClient] sobre Cloud Functions *callable*.
///
/// El servidor envía un motivo estable en `details.reason`
/// (`docs/architecture/05-api-backend.md`); se usa como código del fallo.
final class FirebaseFunctionsClient implements FunctionsClient {
  new(this._functions, {this._timeout = const Duration(seconds: 20)});

  final FirebaseFunctions _functions;
  final Duration _timeout;

  @override
  Future<Result<Json>> call(String name, Json payload) async {
    try {
      final callable = _functions.httpsCallable(
        name,
        options: HttpsCallableOptions(timeout: _timeout),
      );
      final result = await callable.call<Object?>(payload);
      final data = result.data;
      return Ok(data is Map ? _normalize(data) : const <String, Object?>{});
    } on FirebaseFunctionsException catch (e) {
      return Err(mapFunctionsError(e.code, e.details, e));
    } on Object catch (e) {
      return Err(Failure.unexpected('functions', e));
    }
  }

  static Json _normalize(Map<Object?, Object?> map) => {
    for (final MapEntry(:key, :value) in map.entries)
      '$key': switch (value) {
        final Map<Object?, Object?> m => _normalize(m),
        final List<Object?> l => [
          for (final v in l)
            if (v is Map<Object?, Object?>) _normalize(v) else v,
        ],
        _ => value,
      },
  };
}

/// Traduce un código de `HttpsError` (+ `details.reason`) a [Failure].
Failure mapFunctionsError(String code, Object? details, [Object? cause]) {
  final reason = details is Map ? details['reason'] : null;
  final specific = reason is String && reason.isNotEmpty ? reason : code;
  final kind = switch (code) {
    'unauthenticated' => FailureKind.unauthenticated,
    'permission-denied' => FailureKind.permissionDenied,
    'not-found' => FailureKind.notFound,
    'already-exists' ||
    'aborted' ||
    'failed-precondition' => FailureKind.conflict,
    'invalid-argument' || 'out-of-range' => FailureKind.validation,
    'resource-exhausted' => FailureKind.rateLimited,
    'unavailable' ||
    'deadline-exceeded' ||
    'cancelled' => FailureKind.unavailable,
    _ => FailureKind.unexpected,
  };
  return Failure(kind, specific, cause: cause);
}
