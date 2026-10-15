import 'package:uuid/uuid.dart';

/// Genera identificadores creados en el cliente.
///
/// Se usan también como claves de idempotencia: el mismo identificador
/// enviado dos veces representa la misma operación.
abstract interface class IdGenerator {
  String newId();
}

/// UUID v7: aleatorio y ordenable por tiempo de creación.
final class UuidV7IdGenerator implements IdGenerator {
  const new();

  static const Uuid _uuid = Uuid();

  @override
  String newId() => _uuid.v7();
}
