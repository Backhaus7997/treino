/**
 * cancelAppointmentsOnUnlink — Cloud Function for TREINO (#1833, sigue a #1792).
 *
 * Fires on writes to `trainer_links/{linkId}`. Cuando un vínculo VIVO (`active|paused`)
 * pasa a `terminated`, cancela los turnos FUTUROS del par: dejan de ocupar horario.
 *
 * Por qué en el servidor: el cliente del PF ya cancela ANTES de terminar (#1809 / #1822),
 * pero el vínculo que termina el ALUMNO no tiene quién lo haga: el Path 1 de `appointments`
 * le exige >24 h, así que los turnos de las próximas 24 h quedaban `confirmed`.
 *
 * Cancela los `confirmed` o `requested` del par (el conjunto de `cascade/trainer-data.ts`) con
 * `startsAt` por venir, con la forma de `AppointmentRepository.cancelFutureForPair`; no borra.
 * «Por venir» se mide en el marco de `startsAt`, wall-clock ART etiquetado UTC (ADR-7): contra
 * `Timestamp.now()` un turno que empieza en 2 h figuraba «ya pasó», y justo esos son los que el
 * alumno no puede cancelar. `cancelledBy` sale de `terminationReason` (el PF, o el alumno;
 * sin motivo conocido, el alumno con texto neutro): es rastro, nadie lo lee.
 *
 * NOTIFICACIONES: SE SILENCIAN. `notifyOnAppointment` manda un push por turno (una serie son
 * ~36) y los dos lados ya reciben UN aviso por el vínculo. Como en las cascadas de borrado de
 * cuenta, la escritura lleva `reason: LINK_TERMINATED_REASON` y el notificador la saltea:
 * `reason` y no el `cancellationLog` porque es la única clave que el cliente no puede escribir
 * (pineada en `firestore.rules`, #846), así que no se puede forjar.
 *
 * NO actúa en una solicitud (`pending → terminated`), en `account-deleted` /
 * `trainer-account-deleted` (lo cubre la cascada) ni con OTRO vínculo vivo en el par.
 *
 * RECONCILIA, NO ESPEJA: cada transacción relee los vínculos del par y cada turno, así que un
 * re-vínculo en el medio no pierde turnos y uno ya cancelado no se duplica. `retry: true`: es
 * idempotente. Sin índice nuevo: igualdad pura (como `listFutureConfirmedForPair`).
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { DocumentReference, FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { TRAINER_ACCOUNT_DELETED_REASON } from "./cascade/trainer-data";
import { LIVE_LINK_STATUSES } from "./chat/sync-chat-on-trainer-link";
import { toArgentina } from "./notifications/weekly-streak";

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/**
 * `reason` de primer nivel con el que se cancelan los turnos de un vínculo terminado.
 * CONTRATO CF→CF: `notify-appointment.ts` lo importa y lo usa de guard, como
 * `ATHLETE_ACCOUNT_DELETED_REASON` y `TRAINER_ACCOUNT_DELETED_REASON`.
 */
export const LINK_TERMINATED_REASON = "link-terminated";

/** Los estados de un turno que todavía ocupan horario. */
const OPEN_STATUSES: readonly string[] = ["confirmed", "requested"];
const TX_CHUNK = 400; // escrituras por transacción: bajo el tope de 500 de Firestore

type LinkData = Record<string, unknown>;

/** Qué hizo el handler; lo devuelve para que los tests no dependan de los logs. */
export type CancelOnUnlinkOutcome = "skipped" | "cascade" | "invalid" | "nothing" | "live-link" | "cancelled";

const isLive = (status: unknown): boolean => (LIVE_LINK_STATUSES as readonly string[]).includes(status as string);

/** ¿El write es un vínculo VIVO que termina? Barato y sin leer nada. Un create no es transición. */
export function isLiveLinkTerminated(before: LinkData | undefined, after: LinkData | undefined): boolean {
  return after?.status === "terminated" && isLive(before?.status);
}

/** Quién cortó el vínculo y qué texto queda en el rastro. */
function terminatedBy(link: LinkData, trainerId: string, athleteId: string): { byUid: string; motivo: string } {
  const r = link.terminationReason;
  if (r === "trainer-terminated") return { byUid: trainerId, motivo: "Vínculo terminado por el entrenador." };
  const alumno = r === "athlete-terminated" || r === "switched_trainer";
  return { byUid: athleteId, motivo: alumno ? "Vínculo terminado por el alumno." : "Vínculo terminado." };
}

/**
 * Pure handler extracted for jest testability (el emulador no dispara los triggers v2
 * solo). `linkId` es sólo para los logs; `now` es inyectable.
 */
export async function cancelAppointmentsOnUnlinkHandler(
  app: App,
  linkId: string,
  before: LinkData | undefined,
  after: LinkData | undefined,
  now: Date = new Date(),
): Promise<{ outcome: CancelOnUnlinkOutcome; count: number }> {
  if (!after || !isLiveLinkTerminated(before, after)) return { outcome: "skipped", count: 0 };

  if (after.reason === "account-deleted" || after.reason === TRAINER_ACCOUNT_DELETED_REASON) {
    logger.info("cancelAppointmentsOnUnlink: lo cubre la cascada de borrado de cuenta", { linkId });
    return { outcome: "cascade", count: 0 };
  }
  const { trainerId, athleteId } = after;
  if (typeof trainerId !== "string" || trainerId === "" || typeof athleteId !== "string" || athleteId === "") {
    logger.warn("cancelAppointmentsOnUnlink: falta trainerId o athleteId", { linkId });
    return { outcome: "invalid", count: 0 };
  }

  const db = getFirestore(app);

  // 1. Candidatos: los turnos abiertos del par que todavía no empezaron.
  const wallNowMs = toArgentina(now.getTime());
  const pair = db.collection("appointments").where("trainerId", "==", trainerId).where("athleteId", "==", athleteId);
  const snaps = await Promise.all(OPEN_STATUSES.map((s) => pair.where("status", "==", s).get()));
  const candidates: DocumentReference[] = snaps
    .flatMap((s) => s.docs)
    .filter((d) => {
      const startsAt = d.get("startsAt");
      return startsAt instanceof Timestamp && startsAt.toMillis() > wallNowMs;
    })
    .map((d) => d.ref);
  if (candidates.length === 0) return { outcome: "nothing", count: 0 };

  // 2. Reconciliar: cada transacción relee los vínculos del par Y cada turno.
  const { byUid, motivo } = terminatedBy(after, trainerId, athleteId);
  const atMs = now.getTime(); // un instante REAL, como `cancel()` del cliente
  const pairLinks = db
    .collection("trainer_links")
    .where("trainerId", "==", trainerId)
    .where("athleteId", "==", athleteId);

  let count = 0;
  for (let i = 0; i < candidates.length; i += TX_CHUNK) {
    const chunk = candidates.slice(i, i + TX_CHUNK);
    const step = await db.runTransaction(async (tx) => {
      // Todas las lecturas antes de la primera escritura.
      const [links, appts] = await Promise.all([tx.get(pairLinks), tx.getAll(...chunk)]);
      if (links.docs.some((l) => isLive(l.get("status")))) return { live: true, done: 0 };

      let done = 0;
      for (const appt of appts) {
        // Ya cancelado (el PF desde el cliente, #1809) o borrado: no se toca.
        if (!appt.exists || !OPEN_STATUSES.includes(appt.get("status"))) continue;
        tx.update(appt.ref, {
          status: "cancelled",
          reason: LINK_TERMINATED_REASON, // la SEÑAL que lee `notify-appointment`
          cancelledAt: FieldValue.serverTimestamp(),
          cancelledBy: byUid,
          cancellationLog: FieldValue.arrayUnion({ byUid, atMs, reason: motivo }),
        });
        done++;
      }
      return { live: false, done };
    });
    if (step.live) return { outcome: "live-link", count };
    count += step.done;
  }

  logger.info("cancelAppointmentsOnUnlink: turnos futuros cancelados", { linkId, trainerId, athleteId, count });
  return { outcome: count > 0 ? "cancelled" : "nothing", count };
}

/** Cloud Function trigger. Region `southamerica-east1`, la de los demás de `trainer_links`. */
export const cancelAppointmentsOnUnlink = onDocumentWritten(
  { document: "trainer_links/{linkId}", region: "southamerica-east1", retry: true },
  async (event) => {
    const before = event.data?.before?.data() as LinkData | undefined;
    const after = event.data?.after?.data() as LinkData | undefined;
    if (!isLiveLinkTerminated(before, after)) return; // filtro barato ANTES de tocar el app
    await cancelAppointmentsOnUnlinkHandler(ensureApp(), event.params.linkId, before, after);
  },
);
