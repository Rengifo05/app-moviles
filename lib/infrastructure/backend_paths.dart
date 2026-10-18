/// Rutas de documentos del backend (contrato:
/// `docs/architecture/05-api-backend.md`). Centralizadas para que la app,
/// el backend de demostración y las pruebas usen exactamente las mismas.
abstract final class BackendPaths {
  /// Banderas del servicio (solo lectura para la app).
  static const appConfig = 'config/app';

  static String user(String uid) => 'users/$uid';
  static String memberships(String uid) => 'users/$uid/memberships';
  static String devices(String uid) => 'users/$uid/devices';
  static String device(String uid, String deviceId) =>
      'users/$uid/devices/$deviceId';

  static String family(String familyId) => 'families/$familyId';
  static String members(String familyId) => 'families/$familyId/members';
  static String member(String familyId, String uid) =>
      'families/$familyId/members/$uid';
  static String consents(String familyId) => 'families/$familyId/consents';
  static String consent(String familyId, String uid) =>
      'families/$familyId/consents/$uid';
  static String locations(String familyId) => 'families/$familyId/locations';
  static String location(String familyId, String uid) =>
      'families/$familyId/locations/$uid';
  static String geofences(String familyId) => 'families/$familyId/geofences';
  static String geofence(String familyId, String id) =>
      'families/$familyId/geofences/$id';
  static String events(String familyId) => 'families/$familyId/events';
  static String event(String familyId, String id) =>
      'families/$familyId/events/$id';
  static String emergencies(String familyId) =>
      'families/$familyId/emergencies';
  static String emergency(String familyId, String id) =>
      'families/$familyId/emergencies/$id';
}

/// Nombres de las Cloud Functions *callable*.
abstract final class BackendFunctions {
  static const createFamily = 'createFamily';
  static const createInvitation = 'createInvitation';
  static const acceptInvitation = 'acceptInvitation';
  static const leaveFamily = 'leaveFamily';
  static const removeMember = 'removeMember';
  static const raiseSos = 'raiseSos';
  static const deleteAccount = 'deleteAccount';
  static const signOutEverywhere = 'signOutEverywhere';
  static const exportMyData = 'exportMyData';
}
