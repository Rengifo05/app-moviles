import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/features/activity/domain/activity.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/remote_json.dart';
import 'package:nexo_familia/infrastructure/sync/document_cache.dart';

/// Historial familiar (check-ins, zonas, SOS y cambios de integrantes).
///
/// Solo lectura: lee la copia local de `families/{f}/events` que mantiene
/// `RemoteMirror` (los 100 más recientes por `createdAt`), así que funciona
/// sin conexión con lo último recibido. Los documentos de tipo desconocido o
/// mal formados se ignoran: una versión más nueva del backend o un dato
/// corrupto nunca rompen la pantalla.
final class ActivityRepositoryImpl implements ActivityRepository {
  new({required this._cache, required this._clock});

  final DocumentCache _cache;
  final Clock _clock;

  @override
  Stream<List<ActivityItem>> watchActivity(String familyId, {int limit = 50}) =>
      _cache.watchCollection(BackendPaths.events(familyId)).map((docs) {
        final now = _clock.now();
        final items = [
          for (final doc in docs) ?ActivityParser.parse(familyId, doc, now),
        ]..sort(newestFirst);
        return items.length > limit ? items.sublist(0, limit) : items;
      });
}

/// Más recientes primero; a igual hora, por id (orden estable).
int newestFirst(ActivityItem a, ActivityItem b) {
  final byDate = b.occurredAt.compareTo(a.occurredAt);
  return byDate != 0 ? byDate : b.id.compareTo(a.id);
}

/// Convierte un documento de `events` (contrato: "Eventos" en
/// `docs/architecture/05-api-backend.md`) en un [ActivityItem].
abstract final class ActivityParser {
  /// `null` si el tipo es desconocido, faltan campos obligatorios o el evento
  /// ya venció (`expireAt` pasado: la política TTL de Firestore puede tardar
  /// hasta 24 h en borrarlo).
  static ActivityItem? parse(String familyId, CachedDoc doc, DateTime now) {
    final data = doc.data;
    final actorUid = _nonEmpty(data['actorUid']);
    final occurredAt = occurredAtOf(data);
    if (actorUid == null || occurredAt == null) return null;
    if (RemoteJson.date(data['expireAt']) case final expireAt?
        when !expireAt.isAfter(now)) {
      return null;
    }
    return switch (data['type']) {
      'checkIn' => _checkIn(familyId, doc.id, actorUid, occurredAt, data),
      'geofence' => _geofence(familyId, doc.id, actorUid, occurredAt, data),
      'sos' => _sos(familyId, doc.id, actorUid, occurredAt, data),
      'membership' => _membership(familyId, doc.id, actorUid, occurredAt, data),
      _ => null,
    };
  }

  /// Hora del evento. La del dispositivo (`clientCreatedAt`) dice cuándo
  /// ocurrió (p. ej. un check-in hecho sin conexión y enviado después), pero
  /// no puede ser posterior a la recepción en el servidor (`createdAt`): si
  /// lo es, el reloj del emisor iba adelantado y manda la del servidor.
  static DateTime? occurredAtOf(Json data) {
    final server = RemoteJson.date(data['createdAt']);
    final client = RemoteJson.date(data['clientCreatedAt']);
    if (client == null) return server;
    if (server == null) return client;
    return client.isAfter(server) ? server : client;
  }

  static CheckInActivity? _checkIn(
    String familyId,
    String id,
    String actorUid,
    DateTime occurredAt,
    Json data,
  ) {
    final kind = switch (data['kind']) {
      'ok' => CheckInKind.ok,
      'needHelp' => CheckInKind.needHelp,
      _ => null,
    };
    if (kind == null) return null;
    return CheckInActivity(
      id: id,
      familyId: familyId,
      actorUid: actorUid,
      occurredAt: occurredAt,
      kind: kind,
      message: _nonEmpty(data['message']),
    );
  }

  static GeofenceActivity? _geofence(
    String familyId,
    String id,
    String actorUid,
    DateTime occurredAt,
    Json data,
  ) {
    final transition = switch (data['transition']) {
      'enter' => GeofenceTransition.enter,
      'exit' => GeofenceTransition.exit,
      _ => null,
    };
    final name = _nonEmpty(data['geofenceName']);
    if (transition == null || name == null) return null;
    return GeofenceActivity(
      id: id,
      familyId: familyId,
      actorUid: actorUid,
      occurredAt: occurredAt,
      geofenceName: name,
      transition: transition,
    );
  }

  static SosActivity? _sos(
    String familyId,
    String id,
    String actorUid,
    DateTime occurredAt,
    Json data,
  ) {
    final alertId = _nonEmpty(data['alertId']);
    if (alertId == null) return null;
    // El evento no dice si la alerta terminó (eso vive en `emergencies`):
    // el historial no lo afirma.
    return SosActivity(
      id: id,
      familyId: familyId,
      actorUid: actorUid,
      occurredAt: occurredAt,
      alertId: alertId,
      resolved: false,
    );
  }

  static MembershipActivity? _membership(
    String familyId,
    String id,
    String actorUid,
    DateTime occurredAt,
    Json data,
  ) {
    final change = switch (data['change']) {
      'joined' => MembershipChange.joined,
      'left' => MembershipChange.left,
      'removed' => MembershipChange.removed,
      _ => null,
    };
    if (change == null) return null;
    return MembershipActivity(
      id: id,
      familyId: familyId,
      actorUid: actorUid,
      occurredAt: occurredAt,
      change: change,
      targetUid: _nonEmpty(data['targetUid']),
    );
  }

  /// Texto recortado; `null` si no es texto o queda vacío.
  static String? _nonEmpty(Object? value) {
    final text = RemoteJson.string(value)?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
