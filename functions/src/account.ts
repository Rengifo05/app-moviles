import type { Ctx } from './families.js';
import { leaveFamily } from './families.js';
import { paths } from './paths.js';

/** Borra los datos de autenticación (Firebase Auth en producción). */
export interface AuthDeleter {
  deleteUser(uid: string): Promise<void>;
}

/**
 * Elimina la cuenta: sale de todas las familias (con las mismas reglas de
 * herencia y borrado), borra el perfil y sus subcolecciones, y por último el
 * usuario de autenticación.
 */
export async function deleteAccount(ctx: Ctx, auth: AuthDeleter): Promise<Record<string, never>> {
  const memberships = await ctx.db.collection(paths.memberships(ctx.uid)).get();
  for (const membership of memberships.docs) {
    await leaveFamily(ctx, { familyId: membership.id });
  }
  await ctx.db.recursiveDelete(ctx.db.doc(paths.user(ctx.uid)));
  await ctx.db.doc(paths.rateLimit(ctx.uid)).delete();
  await auth.deleteUser(ctx.uid);
  return {};
}
