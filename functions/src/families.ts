import { createHash, randomInt } from 'node:crypto';
import {
  FieldValue,
  Timestamp,
  type Firestore,
  type Transaction,
} from 'firebase-admin/firestore';
import { CODE_ALPHABET, CODE_LENGTH, LIMITS } from './config.js';
import { reject, requireString } from './errors.js';
import { paths } from './paths.js';
import { checkRateLimit } from './rate_limit.js';

export type Role = 'owner' | 'admin' | 'member';

export interface Ctx {
  db: Firestore;
  uid: string;
  now: Date;
}

const newId = (db: Firestore) => db.collection('_').doc().id;

export function hashCode(code: string): string {
  return createHash('sha256').update(code, 'utf8').digest('hex');
}

export function normalizeCode(input: string): string {
  return input.toUpperCase().replace(/[\s-]/g, '');
}

function generateCode(): string {
  let code = '';
  for (let i = 0; i < CODE_LENGTH; i++) code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return code;
}

/** Fecha de borrado para la política TTL de Firestore (campo `expireAt`). */
export function expireAt(now: Date | number, days: number): Timestamp {
  const from = typeof now === 'number' ? now : now.getTime();
  return Timestamp.fromMillis(from + days * 24 * 60 * 60 * 1000);
}

function audit(ctx: Ctx, tx: Transaction, familyId: string, action: string, target?: string) {
  tx.set(ctx.db.collection(paths.audit(familyId)).doc(), {
    action,
    actorUid: ctx.uid,
    ...(target ? { targetUid: target } : {}),
    createdAt: FieldValue.serverTimestamp(),
    expireAt: expireAt(ctx.now, LIMITS.auditTtlDays),
  });
}

function membershipEvent(
  ctx: Ctx,
  tx: Transaction,
  familyId: string,
  change: 'joined' | 'left' | 'removed',
  target?: string,
) {
  tx.set(ctx.db.collection(paths.events(familyId)).doc(), {
    type: 'membership',
    actorUid: ctx.uid,
    change,
    ...(target ? { targetUid: target } : {}),
    createdAt: FieldValue.serverTimestamp(),
    expireAt: expireAt(ctx.now, LIMITS.eventTtlDays),
  });
}

async function displayNameOf(ctx: Ctx, tx: Transaction, uid: string): Promise<string> {
  const profile = await tx.get(ctx.db.doc(paths.user(uid)));
  const name = profile.get('displayName');
  return typeof name === 'string' && name.length > 0 ? name : 'Integrante';
}

export async function createFamily(ctx: Ctx, data: unknown): Promise<{ familyId: string }> {
  const name = requireString(data, 'name', 200).trim();
  // Al menos una letra o un dígito: nada de nombres invisibles.
  if (name.length === 0 || name.length > LIMITS.familyNameMax || !/[\p{L}\p{N}]/u.test(name)) {
    reject('invalid-argument', 'family-name-invalid');
  }
  const familyId = newId(ctx.db);
  await ctx.db.runTransaction(async (tx) => {
    const memberships = await tx.get(ctx.db.collection(paths.memberships(ctx.uid)));
    if (memberships.size >= LIMITS.maxFamiliesPerUser) {
      reject('resource-exhausted', 'too-many-families');
    }
    const displayName = await displayNameOf(ctx, tx, ctx.uid);
    const now = FieldValue.serverTimestamp();
    tx.set(ctx.db.doc(paths.family(familyId)), {
      name,
      createdBy: ctx.uid,
      createdAt: now,
      memberCount: 1,
    });
    tx.set(ctx.db.doc(paths.member(familyId, ctx.uid)), {
      uid: ctx.uid,
      displayName,
      role: 'owner',
      joinedAt: now,
    });
    tx.set(ctx.db.doc(paths.membership(ctx.uid, familyId)), {
      familyId,
      familyName: name,
      role: 'owner',
      joinedAt: now,
    });
    tx.set(ctx.db.doc(paths.consent(familyId, ctx.uid)), {
      state: 'notConfigured',
      precision: 'exact',
      updatedAt: now,
    });
    audit(ctx, tx, familyId, 'createFamily');
  });
  return { familyId };
}

export async function roleOf(ctx: Ctx, tx: Transaction, familyId: string, uid: string): Promise<Role | null> {
  const member = await tx.get(ctx.db.doc(paths.member(familyId, uid)));
  return member.exists ? (member.get('role') as Role) : null;
}

export async function createInvitation(
  ctx: Ctx,
  data: unknown,
): Promise<{ invitationId: string; code: string; expiresAt: number; maxUses: number }> {
  const familyId = requireString(data, 'familyId');
  const code = generateCode();
  const tokenHash = hashCode(code);
  const expiresAt = ctx.now.getTime() + LIMITS.invitationTtlMs;
  await ctx.db.runTransaction(async (tx) => {
    const role = await roleOf(ctx, tx, familyId, ctx.uid);
    if (role !== 'owner' && role !== 'admin') reject('permission-denied', 'not-allowed');
    const active = await tx.get(
      ctx.db
        .collection('invitations')
        .where('familyId', '==', familyId)
        .where('status', '==', 'active')
        .where('expiresAt', '>', Timestamp.fromDate(ctx.now)),
    );
    if (active.size >= LIMITS.maxActiveInvitationsPerFamily) {
      reject('resource-exhausted', 'too-many-invitations');
    }
    // Solo se guarda el hash: el código en claro solo lo recibe el creador.
    tx.set(ctx.db.doc(paths.invitation(tokenHash)), {
      familyId,
      createdBy: ctx.uid,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(expiresAt),
      expireAt: expireAt(expiresAt, LIMITS.invitationRetentionDays),
      maxUses: LIMITS.invitationMaxUses,
      uses: 0,
      status: 'active',
    });
    audit(ctx, tx, familyId, 'createInvitation');
  });
  return {
    invitationId: tokenHash.slice(0, 12),
    code,
    expiresAt,
    maxUses: LIMITS.invitationMaxUses,
  };
}

export async function acceptInvitation(ctx: Ctx, data: unknown): Promise<{ familyId: string }> {
  const code = normalizeCode(requireString(data, 'code', 64));
  // La transacción devuelve null si el código no sirve: así se CONFIRMA el
  // contador de intentos (lanzar dentro abortaría la transacción y un
  // atacante podría probar códigos sin límite).
  const familyId = await ctx.db.runTransaction(async (tx): Promise<string | null> => {
    const commitRateLimit = await checkRateLimit(
      ctx.db,
      tx,
      ctx.uid,
      'acceptInvitation',
      LIMITS.acceptInvitationPerHour,
      ctx.now,
    );
    const invitationRef = ctx.db.doc(paths.invitation(hashCode(code)));
    const invitation = await tx.get(invitationRef);
    const inv = invitation.data();
    const valid =
      inv !== undefined &&
      inv.status === 'active' &&
      (inv.expiresAt as Timestamp).toMillis() > ctx.now.getTime() &&
      (inv.uses as number) < (inv.maxUses as number);
    if (!valid) {
      commitRateLimit();
      return null;
    }
    const familyId = inv.familyId as string;
    const familyRef = ctx.db.doc(paths.family(familyId));
    const family = await tx.get(familyRef);
    if (!family.exists) {
      commitRateLimit();
      return null;
    }
    if ((await tx.get(ctx.db.doc(paths.member(familyId, ctx.uid)))).exists) {
      reject('already-exists', 'already-member');
    }
    const memberCount = family.get('memberCount') as number;
    if (memberCount >= LIMITS.maxMembersPerFamily) reject('resource-exhausted', 'family-full');
    const displayName = await displayNameOf(ctx, tx, ctx.uid);

    commitRateLimit();
    const uses = (inv.uses as number) + 1;
    tx.update(invitationRef, {
      uses,
      status: uses >= (inv.maxUses as number) ? 'exhausted' : 'active',
    });
    tx.update(familyRef, { memberCount: memberCount + 1 });
    const now = FieldValue.serverTimestamp();
    tx.set(ctx.db.doc(paths.member(familyId, ctx.uid)), {
      uid: ctx.uid,
      displayName,
      role: 'member',
      joinedAt: now,
    });
    tx.set(ctx.db.doc(paths.membership(ctx.uid, familyId)), {
      familyId,
      familyName: family.get('name'),
      role: 'member',
      joinedAt: now,
    });
    tx.set(ctx.db.doc(paths.consent(familyId, ctx.uid)), {
      state: 'notConfigured',
      precision: 'exact',
      updatedAt: now,
    });
    membershipEvent(ctx, tx, familyId, 'joined');
    audit(ctx, tx, familyId, 'acceptInvitation');
    return familyId;
  });
  // Mismo error para código inexistente, vencido, agotado o revocado: no se
  // confirma si un código existe.
  if (familyId === null) reject('not-found', 'invitation-invalid');
  return { familyId };
}

/**
 * Elimina a `target` de la familia: membresía, ubicación y consentimiento en
 * una transacción. Si sale el owner, hereda el integrante más antiguo; si
 * sale el último, se borra la familia completa.
 */
async function removeFromFamily(
  ctx: Ctx,
  familyId: string,
  target: string,
  change: 'left' | 'removed',
  authorize: (callerRole: Role | null, targetRole: Role | null) => boolean,
): Promise<void> {
  let deleteFamily = false;
  await ctx.db.runTransaction(async (tx) => {
    const callerRole = await roleOf(ctx, tx, familyId, ctx.uid);
    const targetRole = await roleOf(ctx, tx, familyId, target);
    if (targetRole === null) reject('not-found', 'not-member');
    if (!authorize(callerRole, targetRole)) reject('permission-denied', 'not-allowed');
    const familyRef = ctx.db.doc(paths.family(familyId));
    const family = await tx.get(familyRef);
    const members = await tx.get(ctx.db.collection(paths.members(familyId)));
    const remaining = members.docs
      .filter((d) => d.id !== target)
      .sort((a, b) => (a.get('joinedAt') as Timestamp).toMillis() - (b.get('joinedAt') as Timestamp).toMillis());

    tx.delete(ctx.db.doc(paths.member(familyId, target)));
    tx.delete(ctx.db.doc(paths.membership(target, familyId)));
    tx.delete(ctx.db.doc(paths.location(familyId, target)));
    tx.delete(ctx.db.doc(paths.consent(familyId, target)));

    if (remaining.length === 0) {
      deleteFamily = true;
      return;
    }
    const heir = remaining[0];
    if (targetRole === 'owner' && heir !== undefined) {
      tx.update(heir.ref, { role: 'owner' });
      tx.set(ctx.db.doc(paths.membership(heir.id, familyId)), { role: 'owner' }, { merge: true });
    }
    tx.update(familyRef, { memberCount: remaining.length });
    if (family.exists) {
      membershipEvent(ctx, tx, familyId, change, change === 'removed' ? target : undefined);
      audit(ctx, tx, familyId, change === 'removed' ? 'removeMember' : 'leaveFamily', target);
    }
  });
  if (deleteFamily) {
    await ctx.db.recursiveDelete(ctx.db.doc(paths.family(familyId)));
  }
}

export async function leaveFamily(ctx: Ctx, data: unknown): Promise<Record<string, never>> {
  const familyId = requireString(data, 'familyId');
  await removeFromFamily(ctx, familyId, ctx.uid, 'left', () => true);
  return {};
}

export async function removeMember(ctx: Ctx, data: unknown): Promise<Record<string, never>> {
  const familyId = requireString(data, 'familyId');
  const target = requireString(data, 'uid');
  if (target === ctx.uid) reject('permission-denied', 'not-allowed');
  await removeFromFamily(ctx, familyId, target, 'removed', (caller, targetRole) =>
    caller === 'owner' || (caller === 'admin' && targetRole === 'member'),
  );
  return {};
}

