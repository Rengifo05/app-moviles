import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';
import { onCall, type CallableRequest } from 'firebase-functions/v2/https';
import * as account from './account.js';
import { REGION } from './config.js';
import { reject } from './errors.js';
import * as dataExport from './export.js';
import * as families from './families.js';
import * as geofences from './geofences.js';
import type { Ctx } from './families.js';
import * as sos from './sos.js';
import type { Notifier } from './sos.js';

initializeApp();
const db = getFirestore();

// maxInstances acota el costo ante un pico o un abuso (03-costos.md); con
// concurrencia de 2.ª generación, 10 instancias atienden de sobra el MVP.
// App Check se activará con el proyecto real (decisión D7).
const options = { region: REGION, cors: false, enforceAppCheck: false, maxInstances: 10 } as const;

function ctxOf(request: CallableRequest): Ctx {
  const uid = request.auth?.uid;
  if (!uid) reject('unauthenticated', 'unauthenticated');
  return { db, uid, now: new Date() };
}

/** Envuelve una función: registra solo el nombre y el código de error. */
function callable<T>(name: string, run: (ctx: Ctx, data: unknown) => Promise<T>) {
  return onCall(options, async (request) => {
    try {
      return await run(ctxOf(request), request.data);
    } catch (error) {
      const code = (error as { code?: string }).code ?? 'internal';
      logger.warn('callable.failed', { operation: name, code });
      throw error;
    }
  });
}

/** Errores de FCM que indican un token que no volverá a funcionar. */
const INVALID_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

const fcmNotifier: Notifier = {
  async notifySos(tokens, data) {
    const response = await getMessaging().sendEachForMulticast({
      tokens,
      // Texto genérico: sin nombres ni ubicación en la pantalla de bloqueo.
      notification: {
        title: 'Alerta SOS',
        body: 'Un integrante de tu familia pidió ayuda. Abre Nexo Familia.',
      },
      data: { type: 'sos', familyId: data.familyId, alertId: data.alertId },
      // Canal propio con importancia alta (MainActivity.kt crea `sos_alerts`).
      android: { priority: 'high', notification: { channelId: 'sos_alerts' } },
      apns: { headers: { 'apns-priority': '10' } },
    });
    return {
      accepted: response.successCount,
      invalidTokens: response.responses.flatMap((r, i) =>
        !r.success && INVALID_TOKEN_CODES.has(r.error?.code ?? '') ? [tokens[i]!] : [],
      ),
    };
  },
};

// Los nombres exportados son los del contrato: la app los invoca así.
export const createFamily = callable('createFamily', families.createFamily);
export const createInvitation = callable('createInvitation', families.createInvitation);
export const acceptInvitation = callable('acceptInvitation', families.acceptInvitation);
export const leaveFamily = callable('leaveFamily', families.leaveFamily);
export const removeMember = callable('removeMember', families.removeMember);
export const createGeofence = callable('createGeofence', geofences.createGeofence);
export const raiseSos = callable('raiseSos', (ctx, data) => sos.raiseSos(ctx, data, fcmNotifier));
export const signOutEverywhere = callable('signOutEverywhere', (ctx) =>
  account.signOutEverywhere(ctx, { revokeRefreshTokens: (uid) => getAuth().revokeRefreshTokens(uid) }),
);
export const exportMyData = callable('exportMyData', (ctx) =>
  dataExport.exportMyData(ctx, {
    async account(uid) {
      const user = await getAuth().getUser(uid);
      return {
        email: user.email ?? null,
        createdAt: user.metadata.creationTime ? new Date(user.metadata.creationTime).toISOString() : null,
      };
    },
  }),
);
export const deleteAccount = callable('deleteAccount', (ctx) =>
  account.deleteAccount(ctx, { deleteUser: (uid) => getAuth().deleteUser(uid) }),
);
