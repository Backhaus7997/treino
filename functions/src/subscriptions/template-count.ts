/**
 * template-count.ts — mantiene `users/{uid}.templateUsage.count` al dia
 * cuando cambia el conjunto de plantillas que cuentan para un PF
 * (limite-plantillas-pf.md, PR1).
 *
 * ─── La guarda: pertenencia, no existencia ──────────────────────────────────
 *
 * Este trigger dispara con CUALQUIER escritura de `routines/{id}`: rutinas
 * propias del alumno, planes asignados, el agregado de ratings que escribe
 * `templateRatingAggregate` sobre el padre, la redaccion de
 * `quarantineRoutine`, el archivado de `archiveAssignedPlansForPair`. Casi
 * ninguna mueve el conteo, asi que la guarda sale antes de leer nada.
 *
 * Un doc «cuenta para X» si existe, `source == 'trainer-template'`,
 * `assignedBy == X` y `status != 'archived'` — exactamente el conjunto que
 * cuenta [recountTemplates] (total menos archivadas). La escritura importa si
 * ese dueño cambio entre `before` y `after`, y entonces se recuenta a CADA
 * dueño afectado: el de antes y el de despues, si difieren.
 *
 * Comparar solo existencia y `status` no alcanza. Las reglas no dejan al
 * cliente cambiar `source` ni `assignedBy`, pero el Admin SDK si: el backfill
 * `scripts/backfill_routines_source_visibility.js` le escribe `source` a los
 * docs viejos que no lo tienen, y una guarda que mirara solo existencia y
 * `status` se saltearia una escritura asi y dejaria el contador viejo hasta el
 * barrido.
 *
 * El ROL lo decide [recountTemplates], que ya lee el doc del usuario adentro
 * de su transaccion: un alumno con un `trainer-template` forjado (el CREATE
 * branch 1 de `routines` no chequea rol) no recibe contador.
 *
 * ─── Anti-loop ──────────────────────────────────────────────────────────────
 *
 * Este trigger escribe UN solo documento: `users/{uid}`, y solo si el conteo
 * cambio. Nunca escribe `routines/*`, asi que no se reactiva a si mismo.
 *
 * Sobre `routines/{routineId}` hay otro `onDocumentWritten`:
 * `quarantineRoutine` (`moderation/quarantine-vetted-content.ts`). Cuando
 * redacta, reescribe `name`/`split`/`summary`/`days` de la rutina, lo que
 * vuelve a disparar ESTE trigger — pero ninguno de esos campos cambia la
 * pertenencia, y la guarda sale sin leer. Y este trigger no escribe rutinas,
 * asi que no le devuelve el disparo.
 *
 * Sobre `users/{uid}` hay SIETE triggers, que ven la escritura de
 * `templateUsage`. Revisado contra el codigo de cada uno el 2026-09-25:
 *
 *   - `syncEntitlementsOnSubscription` (`entitlement-triggers.ts`):
 *     `subscriptionChanged` compara solo `subscription`. Corta en la primera
 *     linea.
 *   - `syncAthletePaywallOnUser` (`athlete-paywall-enforced.ts`):
 *     `athletePaywallInputChanged` compara `athleteSubscription` y `role`.
 *     Corta igual.
 *   - `reassignFcmToken`: `addedFcmTokens` vacio (no se toca `fcmTokens`),
 *     corta.
 *   - `ensureStoreAccountToken`: `necesitaToken` da falso si el token ya esta,
 *     que es el caso salvo en la primera escritura de la vida del usuario.
 *   - `sendFreeLimitMailOnHit` (`free-limit-mail.ts`, #1245): `esToqueNuevo`
 *     compara solo `freePlanLimitHitAt`. Corta sin leer.
 *   - `syncSharedProfile`: lee `profile_shares/{uid}` y compara solo los
 *     campos de `SHARED_FIELDS`; `templateUsage` no esta entre ellos, asi que
 *     no escribe. Es UNA lectura por escritura de este modulo.
 *   - `quarantineDisplayNameOnWrite`: sin guarda de campo, corre un scan en
 *     memoria de `displayName` en cada escritura. Barato, pero es una
 *     invocacion mas.
 *
 * Ninguno vuelve a escribir `routines/*` ni reescribe `users/{uid}` de una
 * forma que reactive este modulo: no hay loop. El costo es un puñado de
 * invocaciones baratas por cada plantilla creada, borrada, archivada o
 * restaurada, que pasa poco.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { DocumentData } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

import { recountTemplates } from "./trainer-plan-limits";

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/**
 * Para quien cuenta este doc como plantilla, o `null` si no cuenta para
 * nadie. Es el mismo conjunto que cuenta [recountTemplates]: una plantilla
 * sin `status` cuenta, porque solo `archived` libera lugar.
 */
export function countsFor(data: DocumentData | undefined): string | null {
  if (!data) return null;
  if (data.source !== "trainer-template") return null;
  if (data.status === "archived") return null;
  const owner = data.assignedBy;
  return typeof owner === "string" && owner.length > 0 ? owner : null;
}

/**
 * A quien hay que recontar por esta escritura. Vacio si la pertenencia no
 * cambio, que es el caso de casi toda escritura de `routines`.
 *
 * Exportada para testear la decision sin emulador, igual que
 * `isCreateOrDelete` en `custom-exercise-count.ts`.
 */
export function ownersToRecount(
  before: DocumentData | undefined,
  after: DocumentData | undefined,
): string[] {
  const antes = countsFor(before);
  const despues = countsFor(after);
  if (antes === despues) return [];
  return [antes, despues].filter((uid): uid is string => uid !== null);
}

/**
 * Handler puro, extraido del wrapper `onDocumentWritten` — mismo patron que
 * `handleCustomExerciseWrite`. `template-count.test.ts` lo llama directo
 * contra el emulador de Firestore, que no dispara triggers v2 solo.
 *
 * Cada dueño va en su propio `try`: si el recuento del de antes falla, el del
 * de despues igual corre. El barrido de las 04:00 cura al que haya fallado.
 */
export async function handleTemplateWrite(
  app: App,
  routineId: string,
  before: DocumentData | undefined,
  after: DocumentData | undefined,
): Promise<void> {
  for (const uid of ownersToRecount(before, after)) {
    try {
      const r = await recountTemplates(app, uid);
      if (r?.changed) {
        logger.info("templateCount: reconciliado", {
          uid,
          routineId,
          count: r.count,
        });
      }
    } catch (err) {
      // Catch-and-log sin relanzar, igual que el resto de los triggers de
      // subscriptions: un doc malformado no debe provocar una tormenta de
      // reintentos.
      logger.error("templateCount: error", { uid, routineId, err });
    }
  }
}

/**
 * Trigger sobre `routines/{routineId}`. Region `southamerica-east1`, la misma
 * que `quarantineRoutine` y que el resto de los triggers de Firestore del
 * repo.
 */
export const maintainTemplateCount = onDocumentWritten(
  { document: "routines/{routineId}", region: "southamerica-east1" },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    // Filtro barato ANTES de tocar el app: casi ninguna escritura de
    // `routines` cambia la pertenencia de una plantilla.
    if (ownersToRecount(before, after).length === 0) return;
    await handleTemplateWrite(ensureApp(), event.params.routineId, before, after);
  },
);
