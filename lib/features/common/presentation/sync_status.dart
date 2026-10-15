import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Estado de la conexión con el servidor para la familia activa.
enum SyncStatus {
  /// Recibiendo datos del servidor.
  live,

  /// Sin conexión: se muestran los últimos datos guardados.
  offline,

  /// Aún no se sabe (arrancando o sin familia activa).
  unknown,
}

/// La raíz de composición lo conecta con el espejo remoto. Las pantallas lo
/// usan para mostrar "Sin conexión. Mostramos los últimos datos guardados."
final syncStatusProvider = StreamProvider<SyncStatus>(
  (ref) => Stream.value(SyncStatus.unknown),
);
