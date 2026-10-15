/// Códigos estables (`Failure.code`) del flujo SOS. La interfaz los traduce
/// a mensajes; los del servidor siguen `docs/architecture/05-api-backend.md`.
abstract final class SosCodes {
  /// Quien envió la alerta no puede confirmarse a sí misma ("Lo vi").
  static const cannotAckOwn = 'cannot-ack-own';

  /// Solo la autora puede terminar su alerta.
  static const notAuthor = 'not-author';

  /// Una alerta solo se puede crear a nombre de la sesión actual.
  static const notOwnAlert = 'not-own-alert';

  /// La alerta no está en el dispositivo (ni enviada ni pendiente).
  static const notFound = 'sos-not-found';

  /// No se pudo guardar en la bandeja de salida del dispositivo.
  static const notSaved = 'sos-not-saved';

  /// Se está enviando ahora mismo: no se puede descartar (podría llegar).
  static const sending = 'sos-sending';

  /// Del servidor: la alerta quedó registrada pero el aviso no se envió;
  /// es transitorio y el reintento completa la notificación.
  static const notificationUnavailable = 'notification-unavailable';

  /// Del servidor: la persona ya no pertenece a la familia.
  static const notMember = 'not-member';

  /// Del servidor: límite de alertas por hora.
  static const rateLimited = 'rate-limited';
}
