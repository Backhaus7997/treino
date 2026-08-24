/**
 * linkLoadReconcile — Cloud Function for TREINO (paywall Fase 7, PR4,
 * REQ-PAYWALL-GATE-009).
 *
 * Fires on every write to `trainer_links/{linkId}` and reconciles, IN THIS
 * ORDER, the two pieces of denormalized paywall state that a change in the
 * link set can invalidate:
 *
 *   1. `syncTrainerLoad({promotion: null})` — the denormalized
 *      `users/{trainerId}.weightedLoad`, for DISPLAY only: the paywall gate
 *      (`syncTrainerLoad` with a `promotion` intent) never trusts this field
 *      and always recomputes live from `trainer_links`
 *      (REQ-PAYWALL-GATE-006). This trigger exists so client-side transitions
 *      that don't go through the gate (pause, terminate, decline, cancel —
 *      all still client-writable, design D-4) keep the displayed N/limit
 *      correct without a round-trip.
 *
 *   2. `syncTrainerEntitlements` — the `entitlement` overlay on the trainer's
 *      links. WHY IT HAS TO BE HERE: nothing else reconciles entitlements
 *      when the LINK SET changes. The other trigger,
 *      `syncEntitlementsOnSubscription`, is gated on `subscriptionChanged`,
 *      which compares the `subscription` map ALONE and is therefore blind to
 *      links appearing or disappearing. So before this call the only
 *      reconciler on that path was the 04:00 ART sweep: a window of up to 24
 *      hours of stale entitlement state after every change in the link set.
 *
 * Design (mirrors link-aggregate.ts, same trigger surface):
 *   - Runs in southamerica-east1 (matches the other trainer_links triggers).
 *   - Idempotent: both helpers full-recompute from the live link set on every
 *     event — no increments, no drift on retry. `syncTrainerEntitlements`
 *     additionally emits only DIFFS, so a no-change event writes no links.
 *   - Error-safe: catches ALL exceptions (including a missing
 *     users/{trainerId} profile, surfaced by syncTrainerLoad as a thrown
 *     not-found), logs, and NEVER rethrows — prevents Eventarc retry storms.
 *     Not free, and the catch at the bottom says what it costs.
 *   - Never denies: reconciliation is not a gate. `syncTrainerLoad` with
 *     `promotion: null` never throws resource-exhausted, and an over-limit
 *     trainer gets the excess PARKED as `entitlement: 'blocked'` instead of
 *     rejected. Parking DOES stop the athlete counting toward the limit:
 *     `reconcileEntitlements` decides per ATHLETE and blocks ALL of that
 *     athlete's live links, so a duplicate link can't survive entitled and
 *     keep counting (select-blocked-links.ts, "LA UNIDAD DE DECISION ES EL
 *     ATLETA"). ONE EXCEPTION, deliberate: on a DEGRADED `subscription` map
 *     the valve in sync-entitlements.ts parks nobody, so the trainer stays
 *     over the limit until the document is fixed by hand — that weightedLoad
 *     above the limit IS the signal.
 *   - Terminates: adding call 2 CLOSES a cycle, because it writes the same
 *     `trainer_links` collection this trigger listens on. That's the real
 *     risk of this file — the argument lives at the call site and is pinned
 *     by the hop-counting tests in link-load-reconcile.test.ts. The trigger
 *     additionally SKIPS our own entitlement-only writes, which removes the
 *     fan-out those writes would cause (see `isEntitlementOnlyWrite`).
 *   - Logs `{event: 'link-promoted-observed'}` when a write transitions a
 *     link INTO 'active' — the adoption metric M.4 compares this against
 *     the CFs' own `{event: 'link-promoted-cf'}` log line to measure legacy
 *     client-side accept()/resume() traffic after the CF migration ships.
 */

import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

import { syncTrainerLoad } from "./promote-link";
import { syncTrainerEntitlements } from "./sync-entitlements";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

/**
 * Recomputes a trainer's weightedLoad and reconciles their link entitlements.
 * Exported separately for direct unit/integration testability (mirrors
 * recomputeAthleteCount).
 *
 * Each step catches everything — a missing trainer profile, a transient
 * Firestore error, anything — logs, and returns without throwing.
 */
export async function linkLoadReconcileHandler(
  app: admin.app.App,
  trainerId: string,
): Promise<void> {
  // ── 1. weightedLoad ───────────────────────────────────────────────────────
  //
  // EL ORDEN DE LAS DOS LLAMADAS IMPORTA, y este es el motivo: las dos
  // escriben `users/{trainerId}.weightedLoad`, asi que gana la ultima.
  // `syncTrainerLoad` lo calcula sobre el estado PREVIO a reconciliar;
  // `syncTrainerEntitlements` lo recalcula sobre el estado YA reconciliado (su
  // proyeccion `after`), o sea que su numero es el bueno. Con entitlements
  // SEGUNDO el campo queda correcto dentro del mismo evento; al reves quedaria
  // la carga vieja hasta el proximo trigger.
  let loadSynced = false;
  try {
    const result = await syncTrainerLoad(app, { trainerId, promotion: null });
    loadSynced = true;
    logger.info("linkLoadReconcile: recomputed weightedLoad", {
      trainerId,
      weightedLoad: result.weightedLoad,
    });
  } catch (err) {
    logger.warn(`linkLoadReconcile: error recomputing for trainerId=${trainerId}`, {
      trainerId,
      err,
    });
  }

  // ── 2. entitlements, SOLO si la carga se sincronizo ────────────────────────
  //
  // No es prolijidad: el exito de `syncTrainerLoad` es la unica prueba que
  // tenemos de que `users/{trainerId}` EXISTE. Esa llamada tira not-found
  // cuando el perfil falta; `syncTrainerEntitlements` no chequea nada. Leeria
  // `undefined`, y `toSubscriptionState` le devolveria `degraded: FALSE`,
  // porque un mapa `subscription` AUSENTE es el PF free normal y no una
  // anomalia. O sea que resolveria limite 2 y se pondria a bloquear alumnos de
  // un PF cuyo documento desaparecio. La valvula de degradacion NO tapa ese
  // caso, justamente porque el caso no viene marcado como degradado. Y encima
  // su `tx.set(..., {merge: true})` resucitaria el doc como un fantasma.
  //
  // La friccion la come el entrenador, nunca el alumno: sin perfil no se
  // bloquea a nadie. Un error transitorio cae en la misma rama y tambien
  // saltea la reconciliacion de ESTE evento, cediendole el caso al barrido de
  // las 04:00 — que es exactamente lo que pasaba antes de esta llamada, asi que
  // ese peor caso no empeora nada.
  if (!loadSynced) return;

  // ── POR QUE ESTO NO ES UN LOOP ────────────────────────────────────────────
  //
  // `syncTrainerEntitlements` ESCRIBE `trainer_links` (el tx.update de
  // entitlement/blockedAt/blockedReason) y este trigger dispara con TODA
  // escritura de `trainer_links`. El ciclo esta cerrado a proposito, y muere
  // en DOS saltos por dos razones que hacen falta las dos:
  //
  //   1. El conjunto que `reconcileEntitlements` decide CONSERVAR sale de
  //      {id, athleteId, status, acceptedAt} y NO de `entitlement`: los ya
  //      bloqueados siguen siendo candidatos y compiten por el cupo como
  //      todos. Escribir `entitlement` no puede mover esa decision, asi que la
  //      segunda vuelta es un punto fijo POR CONSTRUCCION, no por suerte.
  //   2. Esa misma funcion reporta solo DIFERENCIAS contra el estado en que ya
  //      esta cada vinculo. En la segunda vuelta `block` y `unblock` vienen
  //      vacios, no se escribe ni un `trainer_links`, y la cascada muere ahi.
  //
  // OJO CON UNA DE ESAS ENTRADAS: `acceptedAt` decide la prioridad (mas
  // antiguo primero) y HOY lo puede escribir cualquiera de los dos members —
  // la regla de update de `trainer_links` pinnea trainerId, athleteId,
  // requestedAt, sharedWithTrainer y los tres campos CF-only, pero no
  // `acceptedAt`. No rompe la terminacion (la decision sigue siendo un punto
  // fijo), pero si significa que un alumno puede reordenar la fila y hacer caer
  // a otro — y con este trigger eso se materializa en el acto en vez de esperar
  // al barrido. El pin del campo tiene que ir SI O SI con el slice de
  // enforcement, antes de que `blockedAthleteIds` corte servicio de verdad.
  //
  // MATIZ, porque "por construccion" es una palabra grande: la decision tiene
  // DOS entradas y el punto 1 solo audita una. La otra es el limite, que sale
  // de `effectiveWeightLimit(sub, Date.now())` — este call site no pasa
  // `nowMs`, asi que cada salto usa su propio reloj. Una suscripcion
  // `cancelled` cuyo `currentPeriodEnd` vence ENTRE dos saltos (los separan
  // segundos, no un tick) hace que el segundo resuelva un limite mas chico y
  // vuelva a escribir: tres saltos, no dos. Sigue terminando, porque el
  // tercero ya es punto fijo. La cota honesta es "dos saltos por cada cambio
  // de limite", no "dos saltos y listo".
  //
  // El otro lado del ciclo es la escritura de `users/{trainerId}`. Sobre ese
  // documento hay TRES triggers, no uno, y ninguno lo reabre:
  //   - `syncEntitlementsOnSubscription` corta con `subscriptionChanged`, que
  //     compara UNICAMENTE el mapa `subscription`: esta transaccion toca
  //     campos denormalizados y no ese mapa, asi que devuelve false. Es la
  //     guarda que carga el peso, y la pinnea el test TERMINACION (users) con
  //     el payload real que deja este handler.
  //   - `reassignFcmToken` corta con `addedFcmTokens(...).length === 0`
  //     (notifications/reassign-fcm-token.ts): no agregamos tokens.
  //   - `syncSharedProfile` solo escribe `profile_shares/{uid}`
  //     (profile/sync-shared-profile.ts), asi que no vuelve a `users`.
  // Y no es exposicion nueva: `syncTrainerLoad` ya escribia ese mismo
  // documento desde aca antes de este slice.
  //
  // Del lado de `trainer_links` lo que importa no es el loop —ninguno de los
  // otros cuatro triggers escribe esa coleccion— sino la POLITICA: bloquear un
  // vinculo NO le manda un push al alumno ni le borra las rutinas asignadas,
  // porque `notifyOnLinkChange` y `cleanupAssignedPlansOnUnlink` cortan los dos
  // con `beforeStatus === afterStatus` y una escritura de entitlement no toca
  // `status`. `syncSessionShareOnTrainerLink` es la excepcion y es deliberada:
  // NO corta por status, lee `session_shares` y repara solo si nadie mas lo
  // reclama — su propio comentario explica el robo de share que esa guarda por
  // contenido evita.
  //
  // Los saltos y las guardas estan pinneados por los tests de TERMINACION de
  // link-load-reconcile.test.ts, que CUENTAN los saltos en vez de asumir que la
  // cascada termina.
  try {
    const r = await syncTrainerEntitlements(app, trainerId);
    logger.info("linkLoadReconcile: reconciled entitlements", {
      trainerId,
      limit: r.limit,
      blocked: r.blocked.length,
      unblocked: r.unblocked.length,
    });
  } catch (err) {
    // Mismo contrato que arriba: se logea y se sigue, porque un doc malformado
    // no puede provocar una tormenta de reintentos de Eventarc.
    //
    // PERO va como `error` y no como `warn`, y la diferencia es el punto:
    // salvo contencion o corte de red, lo que cae aca es PERMANENTE y hay UN
    // documento que arreglar a mano. El caso concreto, hoy alcanzable desde el
    // cliente: `acceptedAt` no esta pinneado ni tipado en la regla de update de
    // `trainer_links` (firestore.rules pinnea trainerId, athleteId,
    // requestedAt, sharedWithTrainer y los tres campos CF-only — `acceptedAt`
    // no), asi que un member puede dejar ahi un numero o un string;
    // `syncTrainerEntitlements` lo castea a Timestamp a ciegas y llama
    // `acceptedAt.toMillis()`. Eso tira TypeError y voltea la transaccion
    // ENTERA del PF, no un vinculo — y como es la MISMA funcion que usan el
    // barrido de las 04:00 y `syncEntitlementsOnSubscription`, el mismo dato
    // apaga los tres reconciliadores de ese PF. La ventana de 24h que este
    // archivo vino a cerrar se le vuelve infinita, y este log es lo unico que
    // lo dice.
    //
    // El arreglo de fondo NO vive aca: es una guarda estructural en el mapeo de
    // `acceptedAt` de sync-entitlements.ts (al estilo del `toMillisOrNull` que
    // subscription-state.ts ya tiene para `currentPeriodEnd`) mas el pin del
    // campo en la regla. Lo que si vive aca es no dejarlo pasar en silencio.
    logger.error(`linkLoadReconcile: error reconciling entitlements for trainerId=${trainerId}`, {
      trainerId,
      err,
    });
  }
}

/**
 * `trainer_links` fields only a Cloud Function can write. firestore.rules pins
 * the three of them equal-to-existing on every client update (the
 * `request.resource.data.get('entitlement', null) == resource.data.get(...)`
 * clauses), and in production the single writer is `syncTrainerEntitlements`.
 */
const CF_ONLY_LINK_FIELDS = new Set(["entitlement", "blockedAt", "blockedReason"]);

/**
 * Compares two versions of the SAME field BY VALUE.
 *
 * `before` and `after` are deserialized independently, so an UNCHANGED
 * Timestamp arrives as two different objects and `===` would report a change.
 * Normalizes Timestamps to millis and sorts map keys so neither identity nor
 * key order can pass for a difference.
 *
 * Cada modo de fallo cae del mismo lado: un valor que no se puede serializar
 * (una DocumentReference ciclica, por ejemplo) cuenta como DISTINTO en vez de
 * tirar. Equivocarse asi cuesta una reconciliacion de mas; tirar aca seria una
 * excepcion en el trigger, o sea la tormenta de reintentos que todo este
 * archivo se cuida de no provocar.
 */
function sameFieldValue(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  try {
    return stableValue(a) === stableValue(b);
  } catch {
    return false;
  }
}

function stableValue(value: unknown): string {
  return (
    JSON.stringify(value, (_key, v) => {
      if (v !== null && typeof v === "object") {
        const maybeTs = v as { toMillis?: () => number };
        if (typeof maybeTs.toMillis === "function") return { __ms: maybeTs.toMillis() };
        if (!Array.isArray(v)) {
          const entries = Object.entries(v as Record<string, unknown>);
          return Object.fromEntries(entries.sort(([a], [b]) => a.localeCompare(b)));
        }
      }
      return v;
    }) ?? "__undefined__"
  );
}

/**
 * True when this event is one of OUR OWN entitlement writes: the document
 * existed before and after, and every field that changed is CF-write-only.
 *
 * Exported for direct testing — the mistake it can make is asymmetric, so it is
 * worth pinning: a false positive skips a reconciliation that was needed.
 */
export function isEntitlementOnlyWrite(
  before: admin.firestore.DocumentData | undefined,
  after: admin.firestore.DocumentData | undefined,
): boolean {
  // Un create o un delete nunca son nuestros: `syncTrainerEntitlements` solo
  // hace tx.update sobre vinculos que ya existen.
  if (!before || !after) return false;

  let changed = 0;
  for (const key of new Set([...Object.keys(before), ...Object.keys(after)])) {
    if (sameFieldValue(before[key], after[key])) continue;
    // Cualquier otro campo distinto y se reconcilia como siempre. La guarda es
    // conservadora en el sentido barato: equivocarse hacia "no es nuestra"
    // cuesta una transaccion de mas, equivocarse al reves cuesta correccion.
    if (!CF_ONLY_LINK_FIELDS.has(key)) return false;
    changed++;
  }
  return changed > 0;
}

/**
 * Cloud Function trigger. Deployed to southamerica-east1, matching the other
 * `trainer_links` triggers (linkAggregate, notifyOnLinkChange,
 * cleanupAssignedPlansOnUnlink, syncSessionShare).
 */
export const linkLoadReconcile = onDocumentWritten(
  { document: "trainer_links/{linkId}", region: "southamerica-east1" },
  async (event) => {
    const after = event.data?.after?.data();
    const before = event.data?.before?.data();

    const trainerId =
      (after?.trainerId as string | undefined) ?? (before?.trainerId as string | undefined);

    if (!trainerId) {
      logger.warn("linkLoadReconcile: trainerId not found in document", {
        linkId: event.params.linkId,
      });
      return;
    }

    // Adoption metric (M.4) — a legacy client-side write can still promote a
    // link to 'active' until the CFs ship and firestore.rules locks it down
    // (slice 4). No new instrumentation beyond this one log line, reused by
    // acceptTrainerLink/resumeTrainerLink's own `link-promoted-cf` line.
    const beforeStatus = before?.status as string | undefined;
    const afterStatus = after?.status as string | undefined;
    if (beforeStatus !== "active" && afterStatus === "active") {
      logger.info("linkLoadReconcile: link promoted", {
        event: "link-promoted-observed",
        linkId: event.params.linkId,
        trainerId,
      });
    }

    // ── CORTE DE LA ESTAMPIDA ─────────────────────────────────────────────
    //
    // Eventarc entrega UN EVENTO POR DOCUMENTO, no por transaccion. Un PF que
    // cae de plan2 (15) a free (2) se reconcilia en UNA transaccion que escribe
    // ~13 vinculos, y eso son ~13 invocaciones concurrentes de este trigger,
    // cada una con DOS transacciones sobre el MISMO `users/{trainerId}`.
    // Firestore aborta las contendidas, el abort cae en el catch de arriba, y
    // la reconciliacion de ese evento no pasa. O sea: la rafaga que este
    // archivo existe para cubrir es justo la que lo puede apagar, y la
    // estampida es autoinfligida — la produce nuestra propia escritura.
    //
    // Saltearla no pierde nada, por dos razones verificadas:
    //   1. Es un no-op PROBADO. Una escritura que solo toca
    //      entitlement/blockedAt/blockedReason no puede mover la decision de
    //      `reconcileEntitlements` (ver el bloque del handler), asi que la
    //      pasada que nos ahorramos es exactamente el salto 2 que los tests de
    //      TERMINACION miden en cero escrituras de vinculos.
    //   2. La carga ya quedo bien. Los tres campos son CF-write-only por
    //      reglas y hoy los escribe UNICAMENTE `syncTrainerEntitlements`, que
    //      en la MISMA transaccion escribe `weightedLoad` y `blockedAthleteIds`
    //      sobre el estado ya reconciliado.
    //
    // Si algun dia aparece otro escritor de esos campos que no actualice la
    // carga, esa carga queda vieja hasta el proximo evento o hasta el barrido
    // de las 04:00. Por eso cualquier otro campo que difiera —status,
    // acceptedAt, sharedWithTrainer, lo que sea— corre la reconciliacion como
    // siempre. Y el handler NO lleva esta guarda a proposito: la terminacion
    // del ciclo se sigue demostrando ahi, sin depender de este atajo.
    if (isEntitlementOnlyWrite(before, after)) {
      logger.debug("linkLoadReconcile: skipping own entitlement write", {
        linkId: event.params.linkId,
        trainerId,
      });
      return;
    }

    await linkLoadReconcileHandler(getApp(), trainerId);
  },
);
