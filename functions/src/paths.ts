/** Rutas del contrato. Mismo esquema que lib/infrastructure/backend_paths.dart. */
export const paths = {
  user: (uid: string) => `users/${uid}`,
  membership: (uid: string, familyId: string) => `users/${uid}/memberships/${familyId}`,
  memberships: (uid: string) => `users/${uid}/memberships`,
  devices: (uid: string) => `users/${uid}/devices`,
  family: (familyId: string) => `families/${familyId}`,
  members: (familyId: string) => `families/${familyId}/members`,
  member: (familyId: string, uid: string) => `families/${familyId}/members/${uid}`,
  consent: (familyId: string, uid: string) => `families/${familyId}/consents/${uid}`,
  location: (familyId: string, uid: string) => `families/${familyId}/locations/${uid}`,
  events: (familyId: string) => `families/${familyId}/events`,
  emergency: (familyId: string, alertId: string) => `families/${familyId}/emergencies/${alertId}`,
  audit: (familyId: string) => `families/${familyId}/audit`,
  invitation: (tokenHash: string) => `invitations/${tokenHash}`,
  rateLimit: (uid: string) => `rateLimits/${uid}`,
};
