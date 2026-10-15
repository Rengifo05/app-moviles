import 'package:meta/meta.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/result.dart';

/// Fase de envío de una alerta desde el dispositivo que la creó.
enum SosDelivery {
  /// Guardada en el dispositivo; se enviará cuando haya conexión.
  queued,
  sending,

  /// El servidor confirmó que registró la alerta.
  sent,

  /// Falló de forma permanente (ver [EmergencyAlert.failureCode]).
  failed,
}

/// Estado visible de una alerta, derivado de forma **honesta** de los datos
/// verificables. Ver la máquina de estados en
/// `docs/architecture/02-modelo-de-datos.md`.
enum SosStatus {
  queued,
  sending,

  /// "Alerta registrada": el servidor la guardó.
  sent,

  /// "Aviso enviado a N dispositivos": el proveedor de notificaciones aceptó
  /// N mensajes. Aceptado no significa entregado ni leído.
  notified,

  /// Al menos un integrante confirmó explícitamente que la vio.
  acknowledged,

  /// La persona que la envió la dio por terminada.
  resolved,
  failed,
}

@immutable
final class EmergencyAck {
  const new({required this.uid, required this.at});

  final String uid;
  final DateTime at;
}

@immutable
final class EmergencyAlert {
  const new({
    required this.id,
    required this.familyId,
    required this.uid,
    required this.createdAt,
    required this.delivery,
    this.location,
    this.notifiedCount,
    this.acks = const [],
    this.resolvedAt,
    this.failureCode,
  });

  /// Generado en el dispositivo: reintentos y dobles pulsaciones no crean
  /// alertas duplicadas (idempotencia).
  final String id;
  final String familyId;

  /// Quién pidió ayuda.
  final String uid;
  final DateTime createdAt;
  final SosDelivery delivery;
  final GeoPoint? location;

  /// Mensajes aceptados por el proveedor de push; `null` mientras se
  /// desconoce.
  final int? notifiedCount;
  final List<EmergencyAck> acks;
  final DateTime? resolvedAt;
  final String? failureCode;

  bool get isActive => resolvedAt == null && delivery != SosDelivery.failed;

  /// Precedencia: terminada > fallida > en cola / enviando > confirmada >
  /// notificada > registrada.
  ///
  /// Solo se afirma lo verificable, y ante datos incoherentes se elige el
  /// estado que promete menos:
  /// * Mientras el envío propio no está confirmado (`queued`, `sending`) se
  ///   muestra esa fase aunque lleguen otros datos: es la que ofrece
  ///   reintentar y "Llamar al 123".
  /// * `acknowledged` exige la confirmación de **otro** integrante: que quien
  ///   pidió ayuda la vea en su dispositivo no significa que alguien más la
  ///   viera (las reglas ya lo impiden; el dominio no depende de ello).
  /// * `notified` exige un [notifiedCount] conocido y no negativo; 0 es
  ///   válido ("Nadie pudo ser notificado").
  SosStatus get status {
    if (resolvedAt != null) return SosStatus.resolved;
    return switch (delivery) {
      SosDelivery.failed => SosStatus.failed,
      SosDelivery.queued => SosStatus.queued,
      SosDelivery.sending => SosStatus.sending,
      SosDelivery.sent when acks.any((a) => a.uid != uid) =>
        SosStatus.acknowledged,
      SosDelivery.sent when (notifiedCount ?? -1) >= 0 => SosStatus.notified,
      SosDelivery.sent => SosStatus.sent,
    };
  }

  bool acknowledgedBy(String uid) => acks.any((a) => a.uid == uid);

  /// Copia con cambios. La identidad, la hora y la ubicación no cambian.
  ///
  /// [failureCode] solo describe una alerta `failed`: si la copia queda en
  /// otra fase (p. ej. al reintentar) y no se indica un código nuevo, se
  /// descarta para que una alerta enviada no arrastre un error antiguo.
  /// [notifiedCount] y [resolvedAt] no se pueden borrar: el recuento lo fija
  /// el servidor y terminar una alerta es definitivo.
  EmergencyAlert copyWith({
    SosDelivery? delivery,
    int? notifiedCount,
    List<EmergencyAck>? acks,
    DateTime? resolvedAt,
    String? failureCode,
  }) {
    final nextDelivery = delivery ?? this.delivery;
    return EmergencyAlert(
      id: id,
      familyId: familyId,
      uid: uid,
      createdAt: createdAt,
      location: location,
      delivery: nextDelivery,
      notifiedCount: notifiedCount ?? this.notifiedCount,
      acks: acks ?? this.acks,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      failureCode:
          failureCode ??
          (nextDelivery == SosDelivery.failed ? this.failureCode : null),
    );
  }
}

abstract final class SosRules {
  /// Mantener pulsado antes de iniciar la cuenta atrás.
  static const Duration holdToActivate = Duration(seconds: 2);

  /// Cuenta atrás cancelable antes de crear la alerta.
  static const Duration cancelWindow = Duration(seconds: 5);

  /// Límite de frecuencia (también se aplica en el servidor).
  static const int maxPerHour = 5;
}

abstract interface class EmergencyRepository {
  /// Guarda la alerta y la envía con prioridad. Si ya existe una alerta con
  /// el mismo id, no crea otra (idempotente).
  Future<Result<EmergencyAlert>> raise(EmergencyAlert alert);

  /// Alertas recientes de la familia (las propias pendientes incluidas).
  Stream<List<EmergencyAlert>> watchAlerts(String familyId);

  /// "Lo vi": confirmación explícita y verificable de un integrante.
  Future<VoidResult> acknowledge(String familyId, String alertId);

  /// Solo quien la envió puede terminarla.
  Future<VoidResult> resolve(String familyId, String alertId);

  /// Reintenta una alerta fallida o en cola.
  Future<VoidResult> retry(String alertId);
}
