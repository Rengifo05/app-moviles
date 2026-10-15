/** Límites del contrato (docs/architecture/05-api-backend.md). */
export const LIMITS = {
  maxFamiliesPerUser: 5,
  maxMembersPerFamily: 12,
  maxActiveInvitationsPerFamily: 10,
  invitationTtlMs: 48 * 60 * 60 * 1000,
  invitationMaxUses: 1,
  acceptInvitationPerHour: 10,
  sosPerHour: 5,
  familyNameMax: 40,
  /** Tiempo tras el cual se puede reintentar una notificación SOS a medias. */
  sosNotifyLeaseMs: 60 * 1000,
  eventTtlDays: 30,
  sosTtlDays: 90,
} as const;

/** Alfabeto de códigos de invitación, sin caracteres ambiguos. */
export const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export const CODE_LENGTH = 10;

/** Región de despliegue: cerca de Colombia (São Paulo). */
export const REGION = 'southamerica-east1';
