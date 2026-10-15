import 'package:nexo_familia/features/emergency/domain/emergency.dart';

/// Alerta propia que la pantalla SOS debe seguir: la más reciente que aún
/// no se terminó (también una fallida, para poder reintentarla o
/// descartarla). [ignore] excluye las que la persona acaba de terminar o
/// descartar en esta pantalla.
EmergencyAlert? myOpenAlert(
  List<EmergencyAlert> alerts,
  String? uid, {
  Set<String> ignore = const {},
}) {
  if (uid == null) return null;
  final mine = [
    for (final alert in alerts)
      if (alert.uid == uid &&
          alert.resolvedAt == null &&
          !ignore.contains(alert.id))
        alert,
  ]..sort(newestFirst);
  return mine.firstOrNull;
}

/// Alertas activas de **otros** integrantes (las que Inicio muestra), más
/// recientes primero. Solo las que el servidor registró: las pendientes de
/// otro dispositivo no existen aquí.
List<EmergencyAlert> othersActiveAlerts(
  List<EmergencyAlert> alerts,
  String? uid,
) {
  if (uid == null) return const [];
  return [
    for (final alert in alerts)
      if (alert.uid != uid &&
          alert.resolvedAt == null &&
          alert.delivery == SosDelivery.sent)
        alert,
  ]..sort(newestFirst);
}

int newestFirst(EmergencyAlert a, EmergencyAlert b) {
  final byDate = b.createdAt.compareTo(a.createdAt);
  return byDate != 0 ? byDate : b.id.compareTo(a.id);
}

/// Combina la versión recién recibida de una alerta con la última conocida
/// en pantalla. Terminar una alerta es definitivo: si el servidor ya lo
/// confirmó (commit con `Ok`) y la caché aún no lo refleja, no se "revive".
EmergencyAlert mergeKnown(EmergencyAlert fresh, EmergencyAlert known) =>
    fresh.resolvedAt == null && known.resolvedAt != null
    ? fresh.copyWith(resolvedAt: known.resolvedAt)
    : fresh;

/// Confirmaciones de otros integrantes (las únicas que cuentan como "la
/// vio"), por orden de llegada.
List<EmergencyAck> acksFromOthers(EmergencyAlert alert) => [
  for (final ack in alert.acks)
    if (ack.uid != alert.uid) ack,
]..sort((a, b) => a.at.compareTo(b.at));
