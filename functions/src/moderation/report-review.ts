/**
 * Cola de revision de reportes — Cloud Functions para TREINO.
 *
 * ## Por que existe
 *
 * En `docs/legal/normas-de-comunidad.md:123` esta escrito, y publicado:
 *
 *   «Nos comprometemos a revisar todo reporte dentro de las 24 horas.»
 *
 * Y no hay donde verlos. Eso no es una feature que falta: es una afirmacion
 * falsa en un documento que el usuario acepta. Se resuelve antes de publicarlo,
 * no despues.
 *
 * ## `reports` no se toca
 *
 * Sigue append-only, cerrada e inmutable: `allow read: if false`, `create` con
 * `hasOnly`, `update, delete: if false`. El Admin SDK ignora las reglas, asi
 * que el servidor lee sin abrir nada.
 *
 * El resultado de la moderacion va a una coleccion APARTE, `report_reviews`.
 * No es un campo nuevo en `reports` por dos motivos, y el segundo es el que
 * importa:
 *
 * 1. El `hasOnly` del `create` no incluye ningun campo de estado, y `update`
 *    esta cerrado. No hay por donde.
 * 2. Mutar una coleccion disenada como inmutable invita a que alguien, en seis
 *    meses, afloje el `update` "solo para el estado" y abra un agujero.
 *    Separarlas hace que esa tentacion no exista.
 *
 * ## El claim de moderador
 *
 * `moderator: true`, custom claim de Firebase Auth, seteado a mano con
 * `node scripts/grant_moderator.js`. Nunca desde el cliente, nunca desde un
 * callable que un usuario pueda invocar: un callable que otorga el permiso de
 * moderar es el permiso de moderar.
 *
 * Antes de esto, `rg 'isAdmin|admin|staff|moderator' firestore.rules` devolvia
 * CERO. No existia noción de admin en el proyecto.
 */

import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError, onCall, type CallableRequest } from
  "firebase-functions/v2/https";

const REGION = "southamerica-east1";

/** Coleccion del resultado de moderacion. Cerrada a todo cliente. */
export const REVIEWS_COLLECTION = "report_reviews";

export type ReportStatus = "pending" | "actioned" | "dismissed";
export type ReportAction =
  | "none"
  | "contentRemoved"
  | "userWarned"
  | "userSuspended";

const ESTADOS: ReportStatus[] = ["pending", "actioned", "dismissed"];
const ACCIONES: ReportAction[] = [
  "none", "contentRemoved", "userWarned", "userSuspended",
];

/** Tope de la nota del moderador, igual que `detail` en `reports`. */
const NOTA_MAX = 1000;

/**
 * Corta la llamada si quien llama no tiene el claim.
 *
 * Se llama PRIMERO en los tres callables. No es defensa en profundidad: es la
 * unica defensa, porque del otro lado hay Admin SDK y las rules no participan.
 */
export function assertModerator(request: CallableRequest<unknown>): string {
  if (request.auth?.token?.moderator !== true) {
    // Mismo mensaje para "no estas logueado" y para "no sos moderador": decir
    // cual de las dos es le confirma a cualquiera que la funcion existe y que
    // el claim es lo que falta.
    throw new HttpsError("permission-denied", "No autorizado.");
  }
  return request.auth.uid;
}

interface PendingReport {
  id: string;
  targetKind: string;
  targetId: string;
  targetOwnerUid: string;
  reason: string;
  detail: string | null;
  reporterUid: string;
  createdAt: string | null;
  firstViewedAt: string | null;
}

/**
 * Los reportes sin resolver, mas viejos primero.
 *
 * Mas viejos primero y no mas nuevos: la promesa es un TECHO de 24 horas, asi
 * que lo que hay que atacar es lo que esta mas cerca de romperla.
 */
export async function listPendingReportsHandler(
  db: Firestore,
  limit = 50,
): Promise<{ reports: PendingReport[] }> {
  const snap = await db
    .collection("reports")
    .orderBy("createdAt", "asc")
    .limit(Math.min(Math.max(limit, 1), 200))
    .get();

  const out: PendingReport[] = [];
  const ahora = new Date();

  for (const doc of snap.docs) {
    const reviewRef = db.collection(REVIEWS_COLLECTION).doc(doc.id);
    const review = await reviewRef.get();
    const status = review.get("status") as ReportStatus | undefined;
    if (status === "actioned" || status === "dismissed") continue;

    // `firstViewedAt` se setea UNA sola vez. Es lo que permite medir cuanto
    // tardamos en MIRAR un reporte, que es la promesa que publicamos — no
    // cuanto tardamos en resolverlo.
    const yaVisto = review.get("firstViewedAt") as
      { toDate(): Date } | undefined;
    if (!yaVisto) {
      await reviewRef.set(
        { status: "pending", firstViewedAt: ahora },
        { merge: true },
      );
    }

    const createdAt = doc.get("createdAt") as { toDate(): Date } | undefined;
    out.push({
      id: doc.id,
      targetKind: String(doc.get("targetKind") ?? ""),
      targetId: String(doc.get("targetId") ?? ""),
      targetOwnerUid: String(doc.get("targetOwnerUid") ?? ""),
      reason: String(doc.get("reason") ?? ""),
      detail: (doc.get("detail") as string | undefined) ?? null,
      reporterUid: String(doc.get("reporterUid") ?? ""),
      createdAt: createdAt ? createdAt.toDate().toISOString() : null,
      firstViewedAt: yaVisto
        ? yaVisto.toDate().toISOString()
        : ahora.toISOString(),
    });
  }

  return { reports: out };
}

export async function resolveReportHandler(
  db: Firestore,
  moderatorUid: string,
  input: { reportId?: unknown; status?: unknown; action?: unknown; note?: unknown },
): Promise<{ ok: true }> {
  const { reportId, status, action, note } = input;

  if (typeof reportId !== "string" || reportId.trim() === "") {
    throw new HttpsError("invalid-argument", "reportId es requerido.");
  }
  if (typeof status !== "string" || !ESTADOS.includes(status as ReportStatus)) {
    throw new HttpsError(
      "invalid-argument",
      `status debe ser uno de ${ESTADOS.join(", ")}.`,
    );
  }
  if (status === "pending") {
    throw new HttpsError(
      "invalid-argument",
      "resolveReport no puede dejar un reporte en 'pending': para eso no se " +
      "lo resuelve.",
    );
  }
  if (typeof action !== "string" ||
      !ACCIONES.includes(action as ReportAction)) {
    throw new HttpsError(
      "invalid-argument",
      `action debe ser uno de ${ACCIONES.join(", ")}.`,
    );
  }
  if (note !== undefined && note !== null &&
      (typeof note !== "string" || note.length > NOTA_MAX)) {
    throw new HttpsError(
      "invalid-argument",
      `note tiene que ser texto de hasta ${NOTA_MAX} caracteres.`,
    );
  }

  // Que el reporte exista se verifica ANTES de escribir. Sin esto,
  // `report_reviews` se llena de resoluciones de reportes que no existen —
  // por un id mal tipeado o por un cliente viejo— y la cola queda mintiendo
  // sobre cuanto se resolvio.
  const reporte = await db.collection("reports").doc(reportId).get();
  if (!reporte.exists) {
    throw new HttpsError("not-found", "Ese reporte no existe.");
  }

  await db.collection(REVIEWS_COLLECTION).doc(reportId).set(
    {
      status,
      action,
      note: typeof note === "string" ? note : null,
      reviewedBy: moderatorUid,
      resolvedAt: new Date(),
    },
    { merge: true },
  );

  return { ok: true };
}

/**
 * Cuantos pendientes y cual es el mas viejo.
 *
 * Es lo que permite PROBAR que se cumplen las 24 horas, en vez de afirmarlo.
 * Una promesa publica sin forma de medirla es la misma clase de afirmacion sin
 * verificar que AGENTS.md 11.1 trata.
 */
export async function moderationStatsHandler(
  db: Firestore,
): Promise<{
  pending: number;
  oldestPendingAt: string | null;
  oldestPendingHours: number | null;
  breachingSla: number;
}> {
  const snap = await db.collection("reports").orderBy("createdAt", "asc").get();

  let pending = 0;
  let oldest: Date | null = null;
  let breaching = 0;
  const ahora = Date.now();
  const VEINTICUATRO_HS = 24 * 60 * 60 * 1000;

  for (const doc of snap.docs) {
    const review = await db.collection(REVIEWS_COLLECTION).doc(doc.id).get();
    const status = review.get("status") as ReportStatus | undefined;
    if (status === "actioned" || status === "dismissed") continue;

    pending++;
    const createdAt = doc.get("createdAt") as { toDate(): Date } | undefined;
    if (!createdAt) continue;
    const fecha = createdAt.toDate();
    if (oldest === null || fecha < oldest) oldest = fecha;
    if (ahora - fecha.getTime() > VEINTICUATRO_HS) breaching++;
  }

  return {
    pending,
    oldestPendingAt: oldest ? (oldest as Date).toISOString() : null,
    oldestPendingHours: oldest
      ? Math.floor((ahora - (oldest as Date).getTime()) / 3_600_000)
      : null,
    breachingSla: breaching,
  };
}

// ---------------------------------------------------------------------------
// Wrappers finos — el patron que este repo ya usa (`add-alias.ts:7`,
// `mint-watch-credential.ts:46`, `places-search.ts:17`).
// ---------------------------------------------------------------------------

export const listPendingReports = onCall({ region: REGION }, async (req) => {
  assertModerator(req);
  const limit = typeof req.data?.limit === "number" ? req.data.limit : 50;
  return listPendingReportsHandler(getFirestore(), limit);
});

export const resolveReport = onCall({ region: REGION }, async (req) => {
  const uid = assertModerator(req);
  return resolveReportHandler(getFirestore(), uid, req.data ?? {});
});

export const moderationStats = onCall({ region: REGION }, async (req) => {
  assertModerator(req);
  return moderationStatsHandler(getFirestore());
});
