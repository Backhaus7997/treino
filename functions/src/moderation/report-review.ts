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

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions";
import { HttpsError, onCall, type CallableRequest } from
  "firebase-functions/v2/https";

import { dedupeKey } from "../mail/enqueue-mail";
import { MAIL_QUEUE_COLLECTION, type MailKind } from "../mail/types";

const REGION = "southamerica-east1";

/** Mismo patron que `notify-appointment.ts:37` y el resto del repo. */
function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

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
 * Campo de texto a redactar por superficie, para `contentRemoved`.
 *
 * `profile` no tiene entrada: un reporte de perfil no se resuelve borrando
 * texto, se resuelve dando de baja la cuenta. Ver el guard en
 * `resolveReportHandler`.
 */
const REDACTABLE_FIELD: Record<string, string | undefined> = {
  post: "text",
  review: "comment",
  message: "text",
};

/**
 * Campo de MEDIA a limpiar por superficie, para `contentRemoved`.
 *
 * Sin esto, "Contenido retirado" redacta el texto y deja la foto/video
 * publicados: un post o mensaje de solo imagen ya tiene `text` vacio
 * (`post_card.dart:198-200`, `chat_screen.dart:490-511`), asi que la
 * redaccion "tenia exito" sin haber retirado nada visible — el mismo bug
 * que este cambio vino a arreglar, visto del otro lado.
 *
 * `review` no tiene entrada: una resena (`review.dart`) no tiene campo de
 * media.
 */
const REDACTABLE_MEDIA_FIELD: Record<string, string | undefined> = {
  post: "photoUrl",
  message: "mediaUrl",
};

/**
 * Campo de AUTOR real por superficie — de donde se deriva el dueno del
 * contenido en `deriveContentOwnerUid`. Nunca `targetOwnerUid`: lo declara
 * el denunciante y `firestore.rules:4622-4623` solo valida que sea un
 * string no vacio, nunca lo ata al autor real.
 *
 * `post.authorUid` (`post.dart`), `review.athleteId` (`review.dart` — quien
 * ESCRIBIO el comentario, no `trainerId`, que es sobre quien es la resena),
 * `message.senderId` (`message.dart`).
 *
 * `profile` no tiene entrada: el dueno de un reporte de perfil ES
 * `targetId` (mismo criterio que documenta `resolveContentPath`), no un
 * campo a leer de un documento.
 */
const OWNER_FIELD: Record<string, string | undefined> = {
  post: "authorUid",
  review: "athleteId",
  message: "senderId",
};

/**
 * Codigo gRPC de `FAILED_PRECONDITION`.
 *
 * Es 9. El 10 es `ABORTED` — confundirlos hace que una carrera perdida se
 * propague como error inesperado en vez de tratarse. Mismo valor que usa
 * `quarantine-vetted-content.ts`.
 */
const FAILED_PRECONDITION = 9;

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
 * El dueno REAL del contenido reportado, segun el documento — nunca segun
 * `targetOwnerUid`, que lo declara el denunciante.
 *
 * Sin esto: alguien reporta un post genuinamente reportable de Juan pero
 * escribe el uid de Pedro; el moderador ve contenido que si viola las
 * normas, aprieta "Dar de baja", y se deshabilita a Pedro en vez de a Juan.
 *
 * Devuelve `null` cuando el contenido no existe o no se puede derivar el
 * autor — NUNCA cae de vuelta a `targetOwnerUid`. Quien llama decide que
 * hacer con un `null` (ver `resolveReportHandler`, PASO 1).
 */
async function deriveContentOwnerUid(
  db: Firestore,
  input: {
    targetKind: string;
    targetId: string;
    reporterUid: string;
    targetOwnerUid: string;
  },
): Promise<string | null> {
  const { targetKind, targetId } = input;

  if (targetKind === "profile") {
    // El `targetId` de un reporte de perfil ES el uid (mismo criterio que
    // `resolveContentPath`), no un campo a leer de un documento.
    return targetId || null;
  }

  const path = resolveContentPath(input);
  const field = OWNER_FIELD[targetKind];
  if (!path || !field) return null;

  const snap = await db.doc(path).get();
  if (!snap.exists) return null;

  const uid = snap.get(field);
  return typeof uid === "string" && uid.length > 0 ? uid : null;
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

/** Codigo gRPC de `ALREADY_EXISTS`. Mismo valor que usa `enqueue-mail.ts`. */
const ALREADY_EXISTS = 6;

/**
 * Encola el mail de aviso DIRECTO contra `db`, sin pasar por `enqueueMail`.
 *
 * `enqueueMail` nunca tira (por diseno: no puede volar un trigger que
 * comparte evento con FCM, ver su docstring) y devuelve `null` TANTO cuando
 * el mail YA esta encolado (dedupe, esperado) COMO cuando la ESCRITURA A
 * FIRESTORE FALLA (no esperado) — con esa API no hay forma de distinguir
 * los dos casos desde el valor de retorno.
 *
 * Para `resolveReportHandler` eso es inaceptable: un fallo de escritura real
 * tiene que abortar la resolucion, no marcarla resuelta con el aviso perdido
 * para siempre. Mismo patron que `notify-report-created.ts:50-75`:
 * `.create()` con id deterministico, y solo ALREADY_EXISTS (6) se traga —
 * cualquier otro error se propaga.
 *
 * Contra `db` (el parametro del handler) y no contra `getFirestore(app)`:
 * asi un test puede interceptar esta escritura puntual, igual que
 * `dbConCarrera` intercepta `audit_log`.
 */
async function enqueueWarningMailOrThrow(
  db: Firestore,
  reportId: string,
  toUid: string,
): Promise<void> {
  const kind: MailKind = "moderation-user-warned";
  const id = dedupeKey(kind, reportId, toUid);

  await db
    .collection(MAIL_QUEUE_COLLECTION)
    .doc(id)
    .create({
      toUid,
      kind,
      params: {},
      status: "pending",
      attempts: 0,
      createdAt: new Date(),
    })
    .catch((err: { code?: number }) => {
      if (err?.code === ALREADY_EXISTS) {
        logger.info("resolveReport: mail de aviso ya encolado", {
          reportId,
          toUid,
        });
        return;
      }
      throw err;
    });
}

/**
 * Deriva el path de Storage (relativo al bucket) de una URL de descarga de
 * Firebase Storage.
 *
 * Mismo algoritmo que `ChatMediaUploadService.extractStoragePath` del
 * cliente (`chat_media_upload_service.dart:131-145`), portado a Node: el
 * path del objeto viaja como UN solo segmento, urlencodeado, despues de
 * `/o/` (`https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{path}`).
 *
 * Devuelve `null` para cualquier URL que no tenga exactamente esa forma —
 * nunca inventa un path a partir de otra cosa. `photoUrl` y `mediaUrl` en
 * este repo siempre vienen de `getDownloadURL()` (`post_photo_upload_service`,
 * `chat_media_upload_service`), asi que en el caso real esto deriva; el
 * `null` es para lo inesperado.
 *
 * ## Dos debilidades que tenia la primera version
 *
 * 1. `hostname.includes(...)` — lo marco CodeQL (alerta 29, "Incomplete URL
 *    substring sanitization"). Un host atacante puede llevar ese dominio
 *    adentro: `firebasestorage.googleapis.com.evil.com` pasaba el chequeo.
 *    Ahora la comparacion es EXACTA.
 * 2. El docstring prometia "exactamente esa forma" y el codigo se quedaba
 *    con el ULTIMO segmento, sin mirar el `/o/`: `.../cualquier/cosa`
 *    devolvia `cosa` como si fuera un path de objeto. Esa es la §11.1 —
 *    un comentario que tranquiliza sobre algo que el codigo de al lado no
 *    hace. Ahora la forma se valida de verdad.
 *
 * El mismo par de debilidades estaba en el original Dart del que se porto
 * esto; van corregidas juntas, porque son el mismo bug en dos lenguajes.
 */
export function extractStoragePath(url: string): string | null {
  try {
    const parsed = new URL(url);
    // Comparacion EXACTA, no `includes`: ver la debilidad 1 del docstring.
    if (parsed.hostname !== "firebasestorage.googleapis.com") {
      return null;
    }
    // La forma es `/v0/b/{bucket}/o/{path}`: el path es UN segmento
    // urlencodeado y va inmediatamente despues de `o`. Cualquier otra cosa
    // no es una URL de descarga y devuelve null.
    const segments = parsed.pathname.split("/").filter((s) => s.length > 0);
    if (segments.length !== 5) return null;
    const [v0, b, , o, encoded] = segments;
    if (v0 !== "v0" || b !== "b" || o !== "o" || !encoded) return null;
    return decodeURIComponent(encoded);
  } catch {
    return null;
  }
}

/**
 * Resuelve un reporte Y EJECUTA la accion elegida.
 *
 * Hasta ahora esto escribia solo la ETIQUETA en `report_reviews` — el boton
 * "Contenido retirado" no retiraba nada, "Usuario advertido" no avisaba a
 * nadie. Un reporte marcado como resuelto sobre una accion que no paso es
 * exactamente la afirmacion falsa que AGENTS.md 11.1 prohibe, asi que el
 * orden de este handler no es incidental:
 *
 * 1. Se valida y se resuelve QUE hay que hacer (puede tirar sin escribir
 *    nada: perfil con `contentRemoved`, contenido que ya no existe,
 *    autosuspension, suspender a otro moderador).
 * 2. Se escribe `audit_log` ANTES de mutar nada irreversible. Si se redacta
 *    primero y el audit_log falla despues, el texto original se pierde para
 *    siempre — no hay apelacion posible. Si es al reves y lo que falla es la
 *    mutacion, el peor caso es una entrada de audit de mas sobre un reporte
 *    que sigue sin resolver, que es recuperable.
 * 3. Se ejecuta la mutacion de verdad (redactar, deshabilitar, encolar mail).
 * 4. Recien ACA se marca `report_reviews` como resuelto. Si cualquier paso
 *    anterior tira, la ejecucion corta y este paso nunca se alcanza: el
 *    reporte queda sin resolver en vez de mentir sobre una accion que fallo.
 */
export async function resolveReportHandler(
  db: Firestore,
  app: App,
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

  // -------------------------------------------------------------------
  // PASO 0 — reclamar el reporte ATOMICAMENTE antes de escribir el audit o
  // ejecutar nada. Mismo patron transaccional que `markReportViewedHandler`.
  //
  // Sin esto, dos moderadores con la cola vieja podian resolver el MISMO
  // reporte dos veces: el segundo `contentRemoved` leia el campo ya vacio
  // (por la primera resolucion) y escribia `removedContent: ""` encima del
  // original —destruyendo la unica evidencia—, y una accion distinta podia
  // suspender a alguien despues de que otro moderador ya habia descartado
  // el reporte.
  //
  // Esto cierra con certeza el caso descrito: alguien resuelve DESPUES de
  // que otro ya termino (secuencial, aunque sea segundos despues). Una
  // doble resolucion verdaderamente simultanea —la misma ventana de
  // milisegundos— haria falta envolver TODO el handler en una transaccion
  // (incluidas las llamadas a Auth y al mail queue), y eso no es lo que se
  // pidio ni lo que este chequeo garantiza.
  // -------------------------------------------------------------------
  await db.runTransaction(async (tx) => {
    const rev = await tx.get(db.collection(REVIEWS_COLLECTION).doc(reportId));
    const yaResuelto = rev.get("status") as ReportStatus | undefined;
    if (yaResuelto === "actioned" || yaResuelto === "dismissed") {
      throw new HttpsError(
        "failed-precondition",
        "Otro moderador ya resolvio este reporte.",
      );
    }
  });

  // Que el reporte exista se verifica ANTES de escribir. Sin esto,
  // `report_reviews` se llena de resoluciones de reportes que no existen —
  // por un id mal tipeado o por un cliente viejo— y la cola queda mintiendo
  // sobre cuanto se resolvio.
  const reporteSnap = await db.collection("reports").doc(reportId).get();
  if (!reporteSnap.exists) {
    throw new HttpsError("not-found", "Ese reporte no existe.");
  }

  const reporteData = reporteSnap.data() ?? {};
  const targetKind = String(reporteData.targetKind ?? "");
  const targetId = String(reporteData.targetId ?? "");
  const targetOwnerUid = String(reporteData.targetOwnerUid ?? "");
  const reporterUid = String(reporteData.reporterUid ?? "");

  // -------------------------------------------------------------------
  // PASO 1 — resolver que hay que hacer. Puede tirar; si tira, no se
  // escribio nada todavia.
  // -------------------------------------------------------------------
  let removedContent: string | null = null;
  let removedMediaUrl: string | null = null;
  let redactPath: string | null = null;
  let redactUpdates: Record<string, string> | null = null;
  let redactUpdateTime: FirebaseFirestore.Timestamp | null = null;
  // El dueno REAL del contenido, derivado del documento — nunca de
  // `targetOwnerUid`. Ver `deriveContentOwnerUid`.
  let derivedOwnerUid: string | null = null;
  // Uid efectivamente usado para userSuspended/userWarned. Es
  // `derivedOwnerUid`, nunca `targetOwnerUid` — separado en su propia
  // variable solo para dejar explicito, en el PASO 3, que esas dos acciones
  // NUNCA leen `targetOwnerUid` directamente.
  let ownerUidForMutation: string | null = null;

  if (action === "contentRemoved") {
    // "Retirar contenido" no aplica a una persona: para eso esta
    // userSuspended. Redactar el displayName de alguien en silencio es peor
    // que fallar ruidoso.
    if (targetKind === "profile") {
      throw new HttpsError(
        "invalid-argument",
        "contentRemoved no aplica a un reporte de perfil: usa userSuspended " +
        "para dar de baja la cuenta.",
      );
    }

    const path = resolveContentPath({
      targetKind, targetId, reporterUid, targetOwnerUid,
    });
    const textField = REDACTABLE_FIELD[targetKind];
    if (!path || !textField) {
      throw new HttpsError(
        "failed-precondition",
        "No se pudo ubicar el contenido de este reporte (targetKind: " +
        `${targetKind || "desconocido"}).`,
      );
    }

    const contenido = await db.doc(path).get();
    if (!contenido.exists) {
      throw new HttpsError(
        "failed-precondition",
        `El contenido reportado ya no existe (${path}).`,
      );
    }

    const mediaField = REDACTABLE_MEDIA_FIELD[targetKind];
    const textVal = String(contenido.get(textField) ?? "");
    const mediaVal = mediaField ? String(contenido.get(mediaField) ?? "") : "";

    // Ni texto ni media: no hay nada que retirar. Antes esto "tenia exito"
    // en silencio sobre un mensaje de solo imagen (text vacio, sin campo de
    // media mapeado) sin tocar la foto — el mismo bug que este cambio
    // arregla, visto del otro lado: mejor fallar ruidoso que mentir que se
    // retiro algo.
    if (!textVal && !mediaVal) {
      throw new HttpsError(
        "failed-precondition",
        "Este reporte no tiene texto ni contenido multimedia para retirar.",
      );
    }

    removedContent = textVal;
    removedMediaUrl = mediaVal || null;
    redactPath = path;
    const updates: Record<string, string> = { [textField]: "" };
    if (mediaField && mediaVal) updates[mediaField] = "";
    redactUpdates = updates;
    // Precondicion para el PASO 3. Entre este `get` y la redaccion el autor
    // puede editar su propio contenido —`firestore.rules:4366` deja
    // actualizar una resena— y entonces `removedContent` guardaria un texto
    // mientras se redacta otro. El audit_log es lo que se mira en una
    // apelacion: si miente, miente exactamente donde importa.
    redactUpdateTime = contenido.updateTime ?? null;

    const ownerField = OWNER_FIELD[targetKind];
    const contentOwner = ownerField ? contenido.get(ownerField) : undefined;
    derivedOwnerUid = typeof contentOwner === "string" && contentOwner.length > 0
      ? contentOwner : null;
  } else if (action === "userSuspended" || action === "userWarned") {
    // El uid SALE DEL CONTENIDO, nunca de `targetOwnerUid`: lo declara el
    // denunciante y `firestore.rules:4622-4623` solo valida que sea un
    // string no vacio, nunca lo ata al autor real del post/resena/mensaje.
    derivedOwnerUid = await deriveContentOwnerUid(db, {
      targetKind, targetId, reporterUid, targetOwnerUid,
    });
    if (derivedOwnerUid === null) {
      // Dar de baja (o avisar) a partir de un uid no verificable es
      // exactamente lo que este arreglo existe para impedir.
      throw new HttpsError(
        "failed-precondition",
        "No se pudo verificar el autor de este contenido (targetKind: " +
        `${targetKind || "desconocido"}); no se puede ejecutar ${action} a ` +
        "partir de un uid no verificable.",
      );
    }
    ownerUidForMutation = derivedOwnerUid;

    if (action === "userSuspended") {
      if (ownerUidForMutation === moderatorUid) {
        throw new HttpsError(
          "invalid-argument",
          "No te podes dar de baja a vos mismo.",
        );
      }

      const target = await getAuth(app).getUser(ownerUidForMutation).catch(
        (err: { code?: string }) => {
          if (err?.code === "auth/user-not-found" ||
              err?.code === "auth/invalid-uid") {
            return null;
          }
          throw err;
        },
      );
      if (!target) {
        throw new HttpsError(
          "failed-precondition",
          "El usuario de este reporte ya no existe.",
        );
      }
      // Sin este guard, el primer moderador que se enoje desarma al equipo.
      if (target.customClaims?.moderator === true) {
        throw new HttpsError(
          "permission-denied",
          "No podes dar de baja a otro moderador.",
        );
      }
    }
  }

  // Un mismatch entre lo declarado y lo derivado es señal de un reporte
  // malicioso — el denunciante escribio un `targetOwnerUid` que no es el
  // autor real del contenido. No aborta la operacion: el contenido
  // reportado es real y hay que poder actuar sobre el. Pero tiene que
  // quedar visible para quien opera (el log) y en la evidencia (el audit).
  if (derivedOwnerUid !== null && derivedOwnerUid !== targetOwnerUid) {
    logger.warn(
      "resolveReport: targetOwnerUid declarado no coincide con el autor " +
      "real del contenido — posible reporte malicioso",
      {
        reportId, targetKind, action,
        declaredOwnerUid: targetOwnerUid, derivedOwnerUid,
      },
    );
  }

  // -------------------------------------------------------------------
  // PASO 2 — audit_log ANTES de mutar. Ver el docstring de arriba.
  // -------------------------------------------------------------------
  if (action !== "none") {
    await db.collection("audit_log").doc(`moderation__${reportId}`).set({
      kind: "moderation",
      reportId,
      moderatorUid,
      action,
      status,
      targetKind,
      // Declarado por el denunciante Y derivado del contenido — evidencia
      // de un posible mismatch (ver el `logger.warn` de arriba).
      targetOwnerUid,
      derivedOwnerUid,
      // El original, SOLO cuando `contentRemoved` lo redacta. Sin esto no
      // hay apelacion posible y la redaccion es irreversible.
      removedContent,
      removedMediaUrl,
      at: new Date(),
    });
  }

  // -------------------------------------------------------------------
  // PASO 3 — ejecutar de verdad.
  // -------------------------------------------------------------------
  if (action === "contentRemoved" && redactPath && redactUpdates) {
    try {
      await db.doc(redactPath).update(
        redactUpdates,
        redactUpdateTime ? { lastUpdateTime: redactUpdateTime } : {},
      );
    } catch (err) {
      if ((err as { code?: number }).code === FAILED_PRECONDITION) {
        // El autor edito el contenido entre el PASO 1 y ahora. No se redacta:
        // el moderador decidio sobre un texto que ya no esta, y el
        // `removedContent` que quedo en audit_log es el de esa version vieja.
        //
        // El reporte NO se marca resuelto —el PASO 4 no llega a correr— asi
        // que vuelve a la cola con el contenido nuevo a la vista. La entrada
        // de audit_log tiene id deterministico (`moderation__{reportId}`), de
        // modo que el reintento la pisa en vez de dejar dos versiones del
        // mismo hecho.
        throw new HttpsError(
          "aborted",
          "El contenido cambio mientras lo revisabas. Volve a mirarlo: el " +
          "reporte sigue en la cola.",
        );
      }
      throw err;
    }

    // Storage: BEST-EFFORT. La UI ya deja de mostrar el media apenas se
    // limpia el campo de arriba —eso es lo que resuelve "la imagen sigue
    // visible"—, asi que esto es defensa en profundidad (la URL vieja, con
    // su token, nunca evalua storage.rules) y su fallo NUNCA aborta la
    // resolucion.
    if (removedMediaUrl) {
      const storagePath = extractStoragePath(removedMediaUrl);
      if (!storagePath) {
        logger.warn(
          "resolveReport: no se pudo derivar el path de Storage de la URL " +
          "— solo se limpio la referencia en Firestore, el objeto puede " +
          "seguir en el bucket",
          { reportId, mediaUrl: removedMediaUrl },
        );
      } else {
        try {
          await getStorage(app).bucket().file(storagePath).delete();
          logger.info("resolveReport: objeto de Storage borrado", {
            reportId, storagePath,
          });
        } catch (err) {
          const code = (err as { code?: number }).code;
          if (code === 404) {
            logger.info(
              "resolveReport: el objeto de Storage ya no existia",
              { reportId, storagePath },
            );
          } else {
            logger.warn(
              "resolveReport: no se pudo borrar el objeto de Storage — " +
              "solo se limpio la referencia en Firestore",
              { reportId, storagePath, error: err },
            );
          }
        }
      }
    }
  } else if (action === "userSuspended" && ownerUidForMutation) {
    await getAuth(app).updateUser(ownerUidForMutation, { disabled: true });
  } else if (action === "userWarned" && ownerUidForMutation) {
    // Sin el contenido reportado, sin el motivo textual del denunciante y
    // sin nada que identifique a quien reporto — mismo criterio que
    // `notify-report-created.ts:9-17`. Un fallo real ACA tira (ver
    // `enqueueWarningMailOrThrow`) y aborta la resolucion.
    await enqueueWarningMailOrThrow(db, reportId, ownerUidForMutation);
  }

  // -------------------------------------------------------------------
  // PASO 4 — recien aca se marca resuelto.
  // -------------------------------------------------------------------
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
  const app = ensureApp();
  return resolveReportHandler(getFirestore(app), app, uid, req.data ?? {});
});

export const moderationStats = onCall({ region: REGION }, async (req) => {
  assertModerator(req);
  return moderationStatsHandler(getFirestore());
});
