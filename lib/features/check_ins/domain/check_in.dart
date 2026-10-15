import 'package:meta/meta.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/result.dart';

enum CheckInKind {
  /// "Estoy bien".
  ok,

  /// "Necesito ayuda". No sustituye al SOS: es un aviso menos urgente.
  needHelp,
}

/// Estado de entrega de una operación creada en el dispositivo.
enum DeliveryState {
  /// Guardada en el dispositivo, pendiente de enviar (p. ej. sin conexión).
  pending,

  /// El servidor la confirmó.
  delivered,

  /// Falló de forma permanente; requiere acción del usuario.
  failed,
}

@immutable
final class CheckIn {
  const new({
    required this.id,
    required this.familyId,
    required this.uid,
    required this.kind,
    required this.createdAt,
    required this.delivery,
    this.message,
    this.location,
  });

  /// Generado en el dispositivo; sirve como clave de idempotencia.
  final String id;
  final String familyId;
  final String uid;
  final CheckInKind kind;
  final DateTime createdAt;
  final DeliveryState delivery;
  final String? message;

  /// Solo se adjunta si la persona comparte su ubicación con esa familia.
  final GeoPoint? location;
}

abstract final class CheckInRules {
  static const int maxMessageLength = 140;

  static String? message(String? value) =>
      value != null && value.trim().length > maxMessageLength
      ? 'check-in-message-too-long'
      : null;
}

abstract interface class CheckInRepository {
  /// Guarda el check-in localmente y lo encola para enviarlo. Devuelve el
  /// check-in con su estado de entrega inicial.
  Future<Result<CheckIn>> submit(CheckIn checkIn);

  /// Check-ins propios aún no confirmados por el servidor.
  Stream<List<CheckIn>> watchPending(String familyId);
}
