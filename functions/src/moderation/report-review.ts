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
 *
 * ## App Check: exentos, y por que
 *
 * Los tres van SIN `enforceAppCheck`, declarados como exencion `decided` en
 * `__tests__/appcheck-enforcement.test.ts`. Mismo impedimento de PLATAFORMA que
 * `acceptTrainerLink`: los llama el Coach Hub web, que no activa App Check
 * —`main_coach_hub.dart` no tiene una sola referencia a `FirebaseAppCheck`, y
 * `main.dart` lo saltea con `if (!kIsWeb)`—. Con el flag puesto, cada llamada
 * desde la web seria rechazada; es el bug que arreglo el PR #704.
 *
 * `decided` y no `debt` porque no hay condicion de salida posible: no es que la
 * atestacion no funcione todavia, es que en esta superficie no existe. Una
 * deuda sin condicion de salida es una decision disfrazada.
 *
 * Y contra el riesgo real, la atestacion no agregaria nada. El riesgo no es un
 * bot anonimo: es una cuenta autenticada SIN el claim. Contra eso el guard es
 * `assertModerator`, no la firma del dispositivo.
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
  /**
   * Ruta del documento reportado, o `null` si no se puede derivar.
   *
   * Sin esto la cola es inservible para los reportes de MENSAJE: el cliente
   * manda `message.id` pelado (`chat_screen.dart:573`) y el documento vive en
   * `chats/{chatId}/messages/{messageId}`. Un id sin su chat no localiza nada,
   * y la cola se presenta como el lugar autenticado donde se mira el
   * contenido.
   *
   * El chatId NO hace falta pedirlo ni guardarlo: es deterministico
   * (`ChatRepository.chatIdFor` ordena el par y lo une con `_`), y el reporte
   * ya trae las dos puntas — `reporterUid` y `targetOwnerUid`. Derivarlo acá
   * evita tocar la forma de `reports`, que es inmutable y cuyo `hasOnly` es
   * criterio de aceptacion de este cambio.
   */
  contentPath: string | null;
}

/** Donde vive el contenido reportado. Ver `PendingReport.contentPath`. */
export function resolveContentPath(input: {
  targetKind: string;
  targetId: string;
  reporterUid: string;
  targetOwnerUid: string;
}): string | null {
  const { targetKind, targetId, reporterUid, targetOwnerUid } = input;
  if (!targetId) return null;

  switch (targetKind) {
  case "post":
    return `posts/${targetId}`;
  case "review":
    return `reviews/${targetId}`;
  case "profile":
    // El `targetId` de un reporte de perfil ES el uid
    // (`public_profile_screen.dart:89`).
    return `users/${targetId}`;
  case "message": {
    if (!reporterUid || !targetOwnerUid || reporterUid === targetOwnerUid) {
      return null;
    }
    const chatId = [reporterUid, targetOwnerUid].sort().join("_");
    return `chats/${chatId}/messages/${targetId}`;
  }
  default:
    // Un `targetKind` que no conocemos devuelve null en vez de armar una ruta
    // inventada: una ruta que no existe se lee igual que una que si, y manda
    // al moderador a buscar un documento que nunca estuvo ahi.
    return null;
  }
}

/**
 * Los reportes sin resolver, mas viejos primero.
 *
 * Mas viejos primero y no mas nuevos: la promesa es un TECHO de 24 horas, asi
 * que lo que hay que atacar es lo que esta mas cerca de romperla.
 *
 * ## Por que escanea en lotes en vez de un solo `limit`
 *
 * El estado de un reporte NO vive en `reports` —vive en `report_reviews`, que
 * es otra coleccion— asi que "pendiente" no se puede poner en el `where`. La
 * primera version pedia los `limit` mas viejos y filtraba los resueltos
 * DESPUES: el dia que los 50 mas viejos estuvieran resueltos, la cola devolvia
 * vacio para siempre, con pendientes mas nuevos esperando.
 *
 * Una cola que se vacia sola es peor que no tener cola: no dice "no hay nada",
 * dice "no hay nada" mintiendo, y nadie vuelve a mirar.
 *
 * Ahora avanza con cursor hasta juntar los que se pidieron. `escaneados` tiene
 * tope duro y se devuelve: si el escaneo se corto por el tope, quien consume
 * la cola tiene que poder saber que la respuesta esta incompleta en vez de
 * leerla como "esto es todo".
 */
export async function listPendingReportsHandler(
  db: Firestore,
  limit = 50,
): Promise<{
  reports: PendingReport[];
  scanned: number;
  reachedScanCap: boolean;
}> {
  const objetivo = Math.min(Math.max(limit, 1), 200);
  const LOTE = 100;
  const TOPE_ESCANEO = 2000;

  const out: PendingReport[] = [];
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  let escaneados = 0;

  while (out.length < objetivo && escaneados < TOPE_ESCANEO) {
    let q = db
      .collection("reports")
      .orderBy("createdAt", "asc")
      .limit(LOTE);
    if (cursor) q = q.startAfter(cursor);

    const snap = await q.get();
    if (snap.empty) break;
    escaneados += snap.size;
    cursor = snap.docs[snap.docs.length - 1];

    for (const doc of snap.docs) {
      if (out.length >= objetivo) break;

      // LISTAR NO ES MIRAR. Este handler solo LEE el review; `firstViewedAt`
      // lo estampa `markReportViewed`, cuando el moderador tiene el reporte
      // de verdad delante.
      //
      // La primera version lo estampaba aca, y eso rompia la unica metrica que
      // prueba la promesa publicada: abrir la pantalla una vez marcaba los 50
      // reportes de la pagina como revisados —incluidos los que ni se
      // renderizaron, porque el ListView es perezoso— y `moderationStats` los
      // contaba dentro del plazo PARA SIEMPRE. El tablero podia declarar
      // cumplimiento sin que nadie hubiera leido nada.
      //
      // Una metrica que se puede satisfacer abriendo una pantalla no mide
      // nada: es la misma clase de afirmacion sin verificar que AGENTS.md 11.1
      // trata, y de la peor especie, porque tranquiliza sobre un compromiso
      // legal.
      const rev = await db.collection(REVIEWS_COLLECTION).doc(doc.id).get();
      const status = rev.get("status") as ReportStatus | undefined;
      if (status === "actioned" || status === "dismissed") continue;
      const visto = rev.get("firstViewedAt") as { toDate(): Date } | undefined;

      const createdAt = doc.get("createdAt") as { toDate(): Date } | undefined;
      const reporterUid = String(doc.get("reporterUid") ?? "");
      const targetKind = String(doc.get("targetKind") ?? "");
      const targetId = String(doc.get("targetId") ?? "");
      const targetOwnerUid = String(doc.get("targetOwnerUid") ?? "");

      out.push({
        id: doc.id,
        targetKind,
        targetId,
        targetOwnerUid,
        reason: String(doc.get("reason") ?? ""),
        detail: (doc.get("detail") as string | undefined) ?? null,
        reporterUid,
        createdAt: createdAt ? createdAt.toDate().toISOString() : null,
        firstViewedAt: visto ? visto.toDate().toISOString() : null,
        contentPath: resolveContentPath({
          targetKind,
          targetId,
          reporterUid,
          targetOwnerUid,
        }),
      });
    }

    if (snap.size < LOTE) break;
  }

  return {
    reports: out,
    scanned: escaneados,
    reachedScanCap: escaneados >= TOPE_ESCANEO && out.length < objetivo,
  };
}

/**
 * Estampa `firstViewedAt` — UNA sola vez — sobre un reporte que el moderador
 * tiene delante.
 *
 * Separado de `listPendingReports` a proposito: listar no es mirar. Ver el
 * comentario largo en el loop de aquel handler.
 *
 * Transaccional y no read-then-set: entre leer el review y escribir, OTRO
 * moderador puede resolver el reporte. Un `set` con merge sobre esa carrera
 * escribiria `status: "pending"` encima del estado resuelto —conservando
 * `resolvedAt`, que quedaria mintiendo— y el reporte REAPARECERIA en la cola.
 * Marcar algo como visto no puede reabrirlo.
 */
export async function markReportViewedHandler(
  db: Firestore,
  reportId: unknown,
): Promise<{ firstViewedAt: string | null }> {
  if (typeof reportId !== "string" || reportId.trim() === "") {
    throw new HttpsError("invalid-argument", "reportId es requerido.");
  }

  const ref = db.collection(REVIEWS_COLLECTION).doc(reportId);
  const ahora = new Date();

  return db.runTransaction(async (tx) => {
    const rev = await tx.get(ref);
    const status = rev.get("status") as ReportStatus | undefined;
    if (status === "actioned" || status === "dismissed") {
      return { firstViewedAt: null };
    }
    const ya = rev.get("firstViewedAt") as { toDate(): Date } | undefined;
    if (ya) return { firstViewedAt: ya.toDate().toISOString() };

    tx.set(ref, { status: "pending", firstViewedAt: ahora }, { merge: true });
    return { firstViewedAt: ahora.toISOString() };
  });
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
 * Cuantos pendientes, cual es el mas viejo, y cuantos rompieron la promesa.
 *
 * Es lo que permite PROBAR que se cumplen las 24 horas en vez de afirmarlo. Una
 * promesa publica sin forma de medirla es la misma clase de afirmacion sin
 * verificar que AGENTS.md 11.1 trata.
 *
 * ## Que cuenta como incumplimiento
 *
 * Lo que `docs/legal/normas-de-comunidad.md:123` promete es REVISAR dentro de
 * las 24 horas, no resolver. `firstViewedAt` es exactamente esa medida, y por
 * eso existe.
 *
 * La primera version contaba como incumplimiento todo pendiente con
 * `createdAt` de mas de 24 horas, mirado o no. Eso contradice la distincion que
 * el resto del modulo sostiene y rompe la metrica por los dos lados: un reporte
 * que se miro a las dos horas y sigue abierto —porque resolverlo requiere
 * decidir algo— aparecia como promesa rota, y el numero dejaba de poder probar
 * nada.
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
    const creado = createdAt.toDate();
    if (oldest === null || creado < oldest) oldest = creado;

    const vencimiento = creado.getTime() + VEINTICUATRO_HS;
    const visto = review.get("firstViewedAt") as { toDate(): Date } | undefined;

    if (!visto) {
      // Nunca se miro. Rompe la promesa solo una vez pasado el plazo; antes de
      // eso todavia esta en tiempo.
      if (ahora > vencimiento) breaching++;
    } else if (visto.toDate().getTime() > vencimiento) {
      // Se miro, pero tarde. Queda contado para siempre: mirarlo despues no
      // deshace el incumplimiento.
      breaching++;
    }
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

export const markReportViewed = onCall({ region: REGION }, async (req) => {
  assertModerator(req);
  return markReportViewedHandler(getFirestore(), req.data?.reportId);
});

export const resolveReport = onCall({ region: REGION }, async (req) => {
  const uid = assertModerator(req);
  return resolveReportHandler(getFirestore(), uid, req.data ?? {});
});

export const moderationStats = onCall({ region: REGION }, async (req) => {
  assertModerator(req);
  return moderationStatsHandler(getFirestore());
});
