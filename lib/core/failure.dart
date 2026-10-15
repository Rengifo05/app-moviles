import 'package:meta/meta.dart';

/// Categoría de un fallo. La UI y el sincronizador deciden según la
/// categoría (exhaustiva); el [Failure.code] concreta el motivo.
enum FailureKind {
  /// Sin conexión o tiempo de espera agotado.
  network,

  /// El servicio remoto no está disponible temporalmente.
  unavailable,

  /// Demasiadas solicitudes; reintentar más tarde.
  rateLimited,

  /// No hay sesión o expiró.
  unauthenticated,

  /// El backend rechazó la operación por falta de autorización.
  permissionDenied,

  /// El sistema operativo no concedió un permiso (ubicación, avisos…).
  devicePermissionDenied,

  /// El recurso no existe (o ya no es visible para el usuario).
  notFound,

  /// Conflicto de versión o estado (otro dispositivo cambió el dato).
  conflict,

  /// Datos inválidos; reintentar no sirve sin corregirlos.
  validation,

  /// Error no previsto. Se registra solo su código.
  unexpected;

  /// Si reintentar la misma operación más tarde puede tener éxito.
  bool get isTransient => switch (this) {
    network || unavailable || rateLimited => true,
    unauthenticated ||
    permissionDenied ||
    devicePermissionDenied ||
    notFound ||
    conflict ||
    validation ||
    unexpected => false,
  };
}

/// Fallo esperado de una operación.
///
/// [code] es un identificador técnico estable (`kebab-case`), seguro para
/// registrarse y usado por la UI para elegir el mensaje localizado.
/// [cause] conserva el error original para depuración local; **nunca** se
/// envía a los registros porque puede contener datos personales.
@immutable
class Failure {
  const new(this.kind, this.code, {this.cause});

  const new network([String code = 'network', Object? cause])
    : this(FailureKind.network, code, cause: cause);

  const new unavailable([String code = 'unavailable', Object? cause])
    : this(FailureKind.unavailable, code, cause: cause);

  const new permissionDenied([String code = 'permission-denied', Object? cause])
    : this(FailureKind.permissionDenied, code, cause: cause);

  const new validation(String code) : this(FailureKind.validation, code);

  const new notFound([String code = 'not-found'])
    : this(FailureKind.notFound, code);

  const new conflict([String code = 'conflict'])
    : this(FailureKind.conflict, code);

  const new unauthenticated([String code = 'unauthenticated'])
    : this(FailureKind.unauthenticated, code);

  const new unexpected([String code = 'unexpected', Object? cause])
    : this(FailureKind.unexpected, code, cause: cause);

  final FailureKind kind;
  final String code;
  final Object? cause;

  bool get isTransient => kind.isTransient;

  // La causa no participa en la igualdad: dos fallos con la misma categoría
  // y código son el mismo fallo para la lógica de la app.
  @override
  bool operator ==(Object other) =>
      other is Failure && other.kind == kind && other.code == code;

  @override
  int get hashCode => Object.hash(kind, code);

  // No incluye [cause] para evitar filtrar datos en `print` o registros.
  @override
  String toString() => 'Failure(${kind.name}, $code)';
}
