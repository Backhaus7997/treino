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
import { toSubscriptionState } from "./subscription-state";
import {
  decideExpiryMail,
  decideSubscriptionMail,
  enqueueSubscriptionMail,
} from "./subscription-mail";

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
    // Un solo reloj para la reconciliacion Y para la decision del mail. Con dos
    // `Date.now()` distintos, un `cancelled` que vence en el medio se
    // reconciliaria con un limite y se anunciaria con el otro.
    const nowMs = Date.now();
    try {
      const r = await syncTrainerEntitlements(getApp(), uid, nowMs);
      logger.info("syncEntitlementsOnSubscription: reconciliado", {
        trainerId: uid,
        limit: r.limit,
        blocked: r.blocked.length,
        unblocked: r.unblocked.length,
      });

      // ── El canal de mail del paywall ────────────────────────────────────
      //
      // Va ACA y no adentro de `syncTrainerEntitlements` por dos motivos, y los
      // dos son load-bearing:
      //
      // 1. A esa funcion la llaman DOS triggers. El otro es `linkLoadReconcile`,
      //    que dispara con cada escritura de `trainer_links` y donde NO hay
      //    ninguna transicion de suscripcion que anunciar. Un enqueue adentro
      //    mandaria mail cada vez que se mueve un vinculo.
      // 2. Es un `runTransaction`, y las transacciones reintentan. Este es el
      //    unico lugar del par que corre exactamente una vez por evento.
      //
      // Y este trigger es el unico que tiene el `before`: la decision es por
      // TRANSICION, nunca por estado. Ver el encabezado de `subscription-mail`.
      const plan = decideSubscriptionMail(
        toSubscriptionState(before, uid),
        toSubscriptionState(after, uid),
        nowMs,
      );
      if (plan) {
        await enqueueSubscriptionMail(
          getApp(),
          uid,
          plan,
          r.blockedAthleteIds.length,
        );
      }
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

  // El reloj se fija UNA vez para todo el barrido: la ventana de vencimiento de
  // `decideExpiryMail` es una comparacion contra `currentPeriodEnd`, y con un
  // reloj por PF el ultimo del lote se evalua contra un instante distinto del
  // primero. Ademas hace la corrida entera reproducible en un test.
  const clock = nowMs ?? Date.now();

  let changed = 0;
  for (const doc of snap.docs) {
    try {
      const r = await syncTrainerEntitlements(app, doc.id, clock);
      if (r.blocked.length || r.unblocked.length) {
        changed++;
        logger.info("sweepEntitlements: cambios", {
          trainerId: doc.id,
          blocked: r.blocked.length,
          unblocked: r.unblocked.length,
        });
      }

      // El vencimiento de un `cancelled` es la UNICA bajada de limite que no
      // escribe ningun documento — no hay trigger que la vea, solo este
      // barrido. Por eso la decision de acá no compara `before`/`after` sino la
      // misma suscripcion contra dos relojes.
      const plan = decideExpiryMail(
        toSubscriptionState(doc.data(), doc.id),
        clock,
      );
      if (plan) {
        await enqueueSubscriptionMail(
          app,
          doc.id,
          plan,
          r.blockedAthleteIds.length,
        );
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
