import 'package:meta/meta.dart';
import 'package:nexo_familia/core/failure.dart';

/// Resultado de una operación que puede fallar de forma esperada.
///
/// Las excepciones se reservan para errores de programación; los fallos
/// esperados (red, permisos, validación) viajan como [Err] para que la UI
/// los maneje de forma exhaustiva con `switch`.
@immutable
sealed class Result<T> {
  const new();

  bool get isOk => this is Ok<T>;

  /// Valor si es [Ok]; `null` en caso contrario.
  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  /// Fallo si es [Err]; `null` en caso contrario.
  Failure? get failureOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final failure) => failure,
  };

  R fold<R>({
    required R Function(T value) ok,
    required R Function(Failure failure) err,
  }) => switch (this) {
    Ok<T>(:final value) => ok(value),
    Err<T>(:final failure) => err(failure),
  };

  /// Transforma el valor conservando el fallo.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Ok<T>(:final value) => Ok<R>(transform(value)),
    Err<T>(:final failure) => Err<R>(failure),
  };

  /// Encadena otra operación que también puede fallar.
  Future<Result<R>> then<R>(Future<Result<R>> Function(T value) next) =>
      switch (this) {
        Ok<T>(:final value) => next(value),
        Err<T>(:final failure) => Future.value(Err<R>(failure)),
      };
}

final class Ok<T> extends Result<T> {
  const new(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

final class Err<T> extends Result<T> {
  const new(this.failure);

  final Failure failure;

  @override
  bool operator ==(Object other) => other is Err<T> && other.failure == failure;

  @override
  int get hashCode => Object.hash(Err, failure);

  @override
  String toString() => 'Err($failure)';
}

/// Atajo para operaciones sin valor de retorno; el éxito es `const Ok(null)`.
typedef VoidResult = Result<void>;
