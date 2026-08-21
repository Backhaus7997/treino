/**
 * entitlement-triggers.ts — los DOS disparadores del downgrade
 * (paywall Fase 7). Ninguno alcanza solo.
 *
 * 1. `syncEntitlementsOnSubscription` — trigger sobre `users/{uid}`. Detecta al
 *    instante los cambios de suscripcion (pausa, cancelacion, upgrade,
 *    reactivacion).
 *
 * 2. `sweepEntitlements` — barrido diario. Detecta lo que NINGUN trigger puede
 *    ver: el limite que cae SOLO POR EL PASO DEL TIEMPO. Un `cancelled` con
 *    `currentPeriodEnd` vencido baja de plan1 a Free sin que se escriba un
 *    solo documento — no hay nada que escuchar. Sin el barrido, ese PF
 *    conserva sus 7 alumnos para siempre.
 */

import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";

import { syncTrainerEntitlements } from "./sync-entitlements";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

/**
 * ¿Cambió algo de la suscripcion entre before y after?
 *
 * GUARDA ANTI-LOOP, load-bearing: `syncTrainerEntitlements` ESCRIBE
 * `weightedLoad` en `users/{trainerId}`, que es el mismo documento que dispara
 * este trigger. Sin este chequeo, cada corrida se auto-dispara y el bucle no
 * termina nunca (y factura sin parar). Comparar solo `subscription` corta el
 * ciclo: la escritura de `weightedLoad` no lo toca.
 */
export function subscriptionChanged(
  before: admin.firestore.DocumentData | undefined,
  after: admin.firestore.DocumentData | undefined,
): boolean {
  const b = before?.subscription;
  const a = after?.subscription;
  if (b === undefined && a === undefined) return false;
  return JSON.stringify(b ?? null) !== JSON.stringify(a ?? null);
}

export const syncEntitlementsOnSubscription = onDocumentWritten(
  { document: "users/{uid}", region: "southamerica-east1" },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    if (!subscriptionChanged(before, after)) return;

    const uid = event.params.uid;
    try {
      const r = await syncTrainerEntitlements(getApp(), uid);
      logger.info("syncEntitlementsOnSubscription: reconciliado", {
        trainerId: uid,
        limit: r.limit,
        blocked: r.blocked.length,
        unblocked: r.unblocked.length,
      });
    } catch (err) {
      // Catch-and-log sin relanzar, igual que linkAggregate: un doc malformado
      // no debe provocar una tormenta de reintentos.
      logger.error("syncEntitlementsOnSubscription: error", { uid, err });
    }
  },
);

export interface SweepResult {
  scanned: number;
  changed: number;
}

/**
 * Barrido: reconcilia a todo PF que tenga suscripcion.
 *
 * Recorre por `role == 'trainer'` y no por estado de suscripcion: los PF se
 * crean a mano con el Admin SDK, asi que son POCOS, y filtrar por estado
 * dejaria afuera justo el caso que motiva el barrido (un `cancelled` sigue
 * siendo `cancelled` cuando vence — lo que cambia es el reloj, no el campo).
 */
export async function sweepEntitlementsHandler(
  app: admin.app.App,
  nowMs?: number,
): Promise<SweepResult> {
  const db = admin.firestore(app);
  const snap = await db
    .collection("users")
    .where("role", "==", "trainer")
    .get();

  let changed = 0;
  for (const doc of snap.docs) {
    try {
      const r = await syncTrainerEntitlements(app, doc.id, nowMs);
      if (r.blocked.length || r.unblocked.length) {
        changed++;
        logger.info("sweepEntitlements: cambios", {
          trainerId: doc.id,
          blocked: r.blocked.length,
          unblocked: r.unblocked.length,
        });
      }
    } catch (err) {
      // Un PF con datos raros no puede frenar el barrido de los demas.
      logger.error("sweepEntitlements: error en un PF", {
        trainerId: doc.id,
        err,
      });
    }
  }

  return { scanned: snap.size, changed };
}

export const sweepEntitlements = onSchedule(
  {
    // 04:00 ART: fuera del horario de uso, y despues de que cualquier
    // currentPeriodEnd del dia anterior ya haya vencido.
    schedule: "0 4 * * *",
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
  },
  async () => {
    const r = await sweepEntitlementsHandler(getApp());
    logger.info("sweepEntitlements: corrida diaria", r);
  },
);
