/**
 * Cuarentena de contenido con terminos vetados — Cloud Functions para TREINO.
 *
 * ## Por que existe, si el cliente ya filtra
 *
 * El filtro del cliente (`lib/core/moderation/`) es el que tecnicamente
 * satisface la App Store Review Guideline 1.2: el contenido no llega a
 * postearse y el usuario ve el error al instante. Pero el cliente se saltea
 * con el SDK de Firestore directo, sin pasar por la app. Esta capa es la que
 * no se puede evadir.
 *
 * ## Que hace la cuarentena, exactamente
 *
 * Dos cosas, y es importante lo que NO hace:
 *
 * 1. **Redacta el campo en el lugar** (`text` -> cadena vacia). No borra el
 *    documento: un falso positivo del filtro le haria perder al usuario algo
 *    que escribio, en silencio y sin vuelta atras. Toda la doctrina de esta
 *    feature es que un falso positivo cuesta mas que un falso negativo.
 * 2. **Escribe el registro en `moderation_quarantine`**, una coleccion aparte
 *    que ningun cliente puede leer ni escribir.
 *
 * ## Por que el registro NO va como campo del documento
 *
 * Porque rompe las rules. `firestore.rules` valida la forma de `posts` con
 * `request.resource.data.keys().hasOnly([...])`, y en un update
 * `request.resource.data` es el doc FINAL mergeado. Un campo `moderation`
 * agregado por el servidor quedaria en ese doc para siempre, y **el autor no
 * podria volver a editar su propio post nunca mas**: permission-denied con
 * cara de bug del cliente.
 *
 * No es hipotetico. `reactionCounts` esta en esa lista de `hasOnly`
 * precisamente porque paso: un campo que el servidor escribia y la regla no
 * conocia rompio la publicacion de posts durante siete semanas, con la suite
 * entera en verde.
 *
 * Redactar un valor, en cambio, no agrega keys. Por eso es seguro.
 *
 * ## Por que no hay bucle infinito
 *
 * La funcion escribe sobre el mismo documento que la disparo, asi que se
 * vuelve a disparar. Termina sola: despues de redactar, el campo es la cadena
 * vacia, `checkText('')` devuelve `ok`, y la segunda pasada no escribe nada.
 * Hay un test que lo fija.
 */

import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

import { checkText, type ModerationVerdict } from "./vetted_terms_filter";

/** Coleccion del registro. `allow read, write: if false` para todo cliente. */
export const QUARANTINE_COLLECTION = "moderation_quarantine";

/**
 * El valor con el que se reemplaza el texto vetado.
 *
 * Cadena vacia y no un cartel tipo "[retirado por moderacion]" por dos
 * motivos. Uno: el servidor no tiene locale del lector, y la app sirve `es_AR`,
 * `es` y `en` — un cartel en castellano apareceria en la sesion de alguien en
 * ingles. Dos: confirmarle al que evadio que lo cazaron le dice exactamente
 * cual intento funciono y cual no.
 */
const REDACTADO = "";

/**
 * Codigo gRPC de `FAILED_PRECONDITION`.
 *
 * Es 9. El 10 es `ABORTED`, y confundirlos hace que la redaccion se propague
 * como error en vez de abandonarse — lo cazo el test de la precondicion, que
 * es exactamente para lo que estaba.
 */
const FAILED_PRECONDITION = 9;

/**
 * Escribe (merge) sobre el registro de cuarentena [id], pero SOLO si
 * [updateTime] no es mas viejo que la version ya escrita ahi.
 *
 * Todo lo que este archivo escribe sobre `redacted` pasa por aca: tanto el
 * registro optimista inicial (`quarantineIfVetted` / `quarantineRoutineIfVetted`,
 * ANTES de intentar el `update()` del documento fuente) como la correccion
 * cuando ese `update()` aborta por precondicion (`marcarRedaccionAbandonada`,
 * mas abajo). Las dos escrituras son async y el trigger que las dispara puede
 * entregar eventos fuera de orden entre invocaciones concurrentes del MISMO
 * documento — sin esta guarda, cualquiera de las dos puede pisar el resultado
 * de una invocacion MAS NUEVA que ya escribio el suyo. Con ella, gana siempre
 * la version mas alta, sin importar en que orden llegaron las escrituras.
 *
 * La transaccion compara contra `sourceUpdateTime`, el `updateTime` del
 * documento fuente que la invocacion GANADORA tenia en el momento de escribir
 * — no contra el `updateTime` actual del documento (que en el momento de la
 * correccion YA esta en una version mas nueva por definicion: es POR ESO que
 * el `update()` abortó). `Timestamp.valueOf()` esta documentado para esto
 * (google-cloud/firestore `timestamp.d.ts`): devuelve un string pensado para
 * compararse con `>`/`<`.
 *
 * Sin `updateTime` no hay con que comparar: se hace el merge sin condicion,
 * igual que antes de este fix — no todos los llamadores lo pasan.
 */
async function escribirRegistroVersionado(
  db: Firestore,
  id: string,
  updateTime: FirebaseFirestore.Timestamp | undefined,
  data: FirebaseFirestore.DocumentData,
): Promise<void> {
  const ref = db.collection(QUARANTINE_COLLECTION).doc(id);
  if (!updateTime) {
    await ref.set(data, { merge: true });
    return;
  }
  await db.runTransaction(async (tx) => {
    const actual = await tx.get(ref);
    const previa = actual.get("sourceUpdateTime") as
      | FirebaseFirestore.Timestamp
      | undefined;
    if (previa && previa.valueOf() > updateTime.valueOf()) {
      // Una invocacion mas nueva ya escribio su resultado aca. Silencio a
      // proposito, mismo criterio que el log de mas abajo: esa escritura
      // nueva disparo SU PROPIO trigger y ya se reviso por su cuenta.
      logger.info("quarantine: se descarta una escritura vieja", { id });
      return;
    }
    tx.set(ref, { ...data, sourceUpdateTime: updateTime }, { merge: true });
  });
}

/**
 * Corrige el registro cuando la redaccion se abandona por precondicion.
 *
 * `redacted` se escribe ANTES de intentar el `update()` (para que el
 * registro exista aunque la funcion se caiga en el medio), pero eso significa
 * que si el `update()` despues aborta por `FAILED_PRECONDITION` el registro
 * queda afirmando `redacted: true` sobre un documento que no se toco. Quien
 * modera filtrando por `redacted: false` para ver que falta atender no ve
 * ese documento — una advertencia falsa (§11.1).
 *
 * A traves de [escribirRegistroVersionado] y NO con un `.set()` directo: una
 * invocacion VIEJA (la de este `catch`, justamente) puede llegar a esta
 * correccion DESPUES de que una invocacion mas nueva ya registro Y redacto
 * bien — sin la guarda de version, este merge incondicional pisaria ese
 * `redacted: true` correcto con un `false`. Misma familia de bug que el que
 * este comentario describe arriba, del otro lado.
 */
async function marcarRedaccionAbandonada(
  db: Firestore,
  id: string,
  updateTime: FirebaseFirestore.Timestamp | undefined,
): Promise<void> {
  await escribirRegistroVersionado(db, id, updateTime, { redacted: false });
}

export interface QuarantineInput {
  db: Firestore;
  /** Ruta completa del documento que disparo el trigger. */
  path: string;
  /** Campo de texto libre a revisar. */
  field: string;
  /** Valor actual del campo. */
  value: unknown;
  /** Para el registro: que tipo de contenido es. */
  kind: "post" | "message" | "review" | "profile";
  /** Autor del contenido, si se puede derivar. Para la cola de moderacion. */
  authorUid?: string;
  /**
   * `updateTime` del snapshot que disparo el trigger.
   *
   * Se usa como PRECONDICION de la redaccion. Entre que el handler mira el
   * valor y escribe, el usuario pudo editar el documento: sin precondicion, el
   * `update()` cae sobre la version NUEVA y borra una edicion limpia que nadie
   * reviso — la funcion termina destruyendo contenido valido.
   *
   * Si el documento cambio, la escritura falla con FAILED_PRECONDITION y se
   * abandona, que es lo correcto: esa escritura nueva disparo SU PROPIO
   * trigger y se revisa por su cuenta.
   */
  updateTime?: FirebaseFirestore.Timestamp;
}

/**
 * Handler puro. El wrapper `onDocumentWritten` de abajo es fino a proposito —
 * es el patron que este repo ya usa (`add-alias.ts:7`,
 * `mint-watch-credential.ts:46`, `places-search.ts:17`).
 */
export async function quarantineIfVetted(
  input: QuarantineInput,
): Promise<ModerationVerdict> {
  const { db, path, field, value, kind, authorUid, updateTime } = input;

  if (typeof value !== "string" || value.trim() === "") return "ok";

  const verdict = checkText(value);
  if (verdict === "ok") return "ok";

  // El registro se escribe para `block` Y para `review`. `review` es
  // justamente "esto amerita que alguien lo mire": si no queda anotado en
  // ningun lado, la severidad no significa nada.
  //
  // Id derivado de la ruta: un mismo documento reescrito vetado dos veces deja
  // UN registro, no dos. La cola de moderacion no necesita el historial de
  // intentos, necesita saber que este documento esta pendiente.
  const id = path.replace(/\//g, "__");
  await escribirRegistroVersionado(db, id, updateTime, {
    path,
    field,
    kind,
    verdict,
    authorUid: authorUid ?? null,
    // El TEXTO NO se guarda. Puede tener datos personales de terceros, y en
    // el chat puede tener datos de salud. Quien modere abre el documento
    // original, autenticado.
    redacted: verdict === "block",
    at: new Date(),
  });

  if (verdict !== "block") return verdict;

  try {
    await db
      .doc(path)
      .update(
        { [field]: REDACTADO },
        updateTime ? { lastUpdateTime: updateTime } : {},
      );
  } catch (err) {
    // FAILED_PRECONDITION (10): el documento cambio despues del evento. No se
    // pisa: la escritura nueva disparo su propio trigger.
    if ((err as { code?: number }).code === FAILED_PRECONDITION) {
      logger.info("quarantine: el documento cambio, lo revisa su propio evento",
        { path, field });
      await marcarRedaccionAbandonada(db, id, updateTime);
      return verdict;
    }
    throw err;
  }
  logger.warn("contenido vetado redactado por el servidor", { path, field });

  return verdict;
}

/**
 * Con que se reemplaza un nombre vetado.
 *
 * Vaciarlo NO sirve: el nombre se renderiza en cada post, cada mensaje y cada
 * tarjeta de descubrimiento, y ademas tiene que seguir siendo unico. Derivarlo
 * del uid cumple las dos cosas y no le pone a nadie el nombre de otro.
 */
export function nombreDeReemplazo(uid: string): string {
  return `usuario_${uid.slice(0, 6)}`;
}

/** Igual que arriba, pero el `displayName` vive en TRES documentos. */
export async function quarantineDisplayName(
  db: Firestore,
  uid: string,
  displayName: unknown,
): Promise<ModerationVerdict> {
  if (typeof displayName !== "string" || displayName.trim() === "") return "ok";

  const verdict = checkText(displayName);
  if (verdict === "ok") return "ok";

  const id = `users__${uid}`;
  await db.collection(QUARANTINE_COLLECTION).doc(id).set(
    {
      path: `users/${uid}`,
      field: "displayName",
      kind: "profile",
      verdict,
      authorUid: uid,
      redacted: verdict === "block",
      at: new Date(),
    },
    { merge: true },
  );

  if (verdict !== "block") return verdict;

  const reemplazo = nombreDeReemplazo(uid);

  // Los TRES documentos donde vive el nombre, no dos.
  //
  // La primera version limpiaba `users` y `userPublicProfiles`. Faltaba
  // `trainerPublicProfiles`, que es el que alimenta el descubrimiento de PFs:
  // un entrenador con nombre vetado quedaba limpio en su perfil y vetado en la
  // tarjeta que ve todo el mundo. Redactar la copia que nadie mira y dejar la
  // publica es no redactar nada.
  const batch = db.batch();
  batch.update(db.doc(`users/${uid}`), { displayName: reemplazo });
  batch.set(
    db.doc(`userPublicProfiles/${uid}`),
    {
      displayName: reemplazo,
      displayNameLowercase: reemplazo.toLowerCase(),
    },
    { merge: true },
  );

  // `trainerPublicProfiles` solo si YA existe: un `set` con merge lo crearia
  // para un atleta, y un doc de entrenador fantasma en la coleccion de
  // descubrimiento es un problema nuevo, no la solucion de este.
  const trainerRef = db.doc(`trainerPublicProfiles/${uid}`);
  if ((await trainerRef.get()).exists) {
    batch.set(
      trainerRef,
      {
        displayName: reemplazo,
        displayNameLowercase: reemplazo.toLowerCase(),
      },
      { merge: true },
    );
  }

  await batch.commit();

  logger.warn("displayName vetado redactado por el servidor", { uid });
  return verdict;
}

/**
 * Redacta el `authorDisplayName` denormalizado de un post.
 *
 * Funcion propia y exportada, no logica adentro del wrapper: lo que vive
 * adentro de un `onDocumentWritten` no se puede testear sin el arnes de
 * triggers, y un test que reimplementa el comportamiento para despues
 * asertarselo a si mismo no prueba nada.
 */
export async function quarantineAuthorName(input: {
  db: Firestore;
  path: string;
  authorUid: string;
  name: unknown;
  updateTime?: FirebaseFirestore.Timestamp;
}): Promise<boolean> {
  const { db, path, authorUid, name, updateTime } = input;
  if (typeof name !== "string" || name.trim() === "") return false;
  if (checkText(name) !== "block") return false;

  try {
    await db
      .doc(path)
      .update(
        { authorDisplayName: nombreDeReemplazo(authorUid) },
        updateTime ? { lastUpdateTime: updateTime } : {},
      );
  } catch (err) {
    if ((err as { code?: number }).code === FAILED_PRECONDITION) {
      return false;
    }
    throw err;
  }
  logger.warn("authorDisplayName vetado redactado", { path });
  return true;
}

/** Un dato en `moderation_quarantine` para UN campo de UNA rutina. */
export interface RoutineQuarantineFinding {
  /**
   * Identifica el campo exacto que fallo — `'name'`, `'split'`, `'summary'`,
   * o la forma indexada `'days[1].slots[3].notes'` para los anidados. Mismo
   * shape que usa `ModerationGuard.ensure` del lado del cliente
   * (`routine_repository.dart`), a proposito: un mismo documento roto deja el
   * MISMO identificador de campo en el log del cliente y en el registro del
   * servidor, y correlacionar los dos no requiere traducir nada.
   */
  field: string;
  verdict: ModerationVerdict;
}

interface RoutineSlotLike {
  notes?: unknown;
}

interface RoutineDayLike {
  name?: unknown;
  slots?: RoutineSlotLike[];
}

export interface QuarantineRoutineInput {
  db: Firestore;
  /** Ruta completa del documento `routines/{routineId}` que disparo el trigger. */
  path: string;
  /** `data()` del snapshot `after`. */
  data: FirebaseFirestore.DocumentData;
  /** Autor del contenido, si se puede derivar. Para la cola de moderacion. */
  authorUid?: string;
  /** Misma precondicion de concurrencia que `quarantineIfVetted` — ver su
   * dartdoc. Aca el riesgo es mayor: lo que se pisaria sin ella no es un
   * campo suelto, es el array `days` ENTERO. */
  updateTime?: FirebaseFirestore.Timestamp;
}

/** Verdict de un texto, o `null` si no amerita ninguno (vacio, o `ok`). */
function verdictFor(value: unknown): ModerationVerdict | null {
  if (typeof value !== "string" || value.trim() === "") return null;
  const verdict = checkText(value);
  return verdict === "ok" ? null : verdict;
}

/**
 * Cuarentena de rutinas.
 *
 * Superficie distinta a `quarantineIfVetted`: una rutina puede tener CINCO
 * campos de texto libre vetables en el mismo write — `name`, `split` y
 * `summary` a nivel documento, y `days[].name` / `days[].slots[].notes`
 * anidados dentro de un array. Por eso esta funcion NO reusa
 * `quarantineIfVetted` (que redacta UN campo top-level con
 * `.update({[field]: valor})`): Firestore no permite actualizar un elemento
 * de array por indice, asi que hay que leer el array COMPLETO, redactar
 * adentro en memoria, y reescribirlo entero en una sola escritura.
 *
 * Un finding por campo vetado, no un solo veredicto: dos campos vetados en el
 * mismo write (p.ej. `name` Y `days[1].slots[3].notes`) dejan DOS registros en
 * `moderation_quarantine`, cada uno con su propio `field` — la cola de
 * moderacion no pierde ninguno de los dos.
 */
export async function quarantineRoutineIfVetted(
  input: QuarantineRoutineInput,
): Promise<RoutineQuarantineFinding[]> {
  const { db, path, data, authorUid, updateTime } = input;

  // Un solo lugar para armar el id del registro de UN campo -- lo usan tanto
  // el loop de registro inicial como la correccion de mas abajo, y las dos
  // tienen que coincidir SIEMPRE para el mismo campo.
  const idFor = (field: string) =>
    `${path.replace(/\//g, "__")}__${field.replace(/[[\].]/g, "_")}`;

  const findings: RoutineQuarantineFinding[] = [];
  const topLevelRedactions: Record<string, string> = {};

  for (const field of ["name", "split", "summary"] as const) {
    const verdict = verdictFor(data[field]);
    if (!verdict) continue;
    findings.push({ field, verdict });
    if (verdict === "block") topLevelRedactions[field] = REDACTADO;
  }

  const days: RoutineDayLike[] = Array.isArray(data.days) ? data.days : [];
  let daysChanged = false;
  const newDays = days.map((day, i) => {
    // Un `day` que no sea un objeto (`null` via SDK directo, por ejemplo) no
    // tiene `.name` ni `.slots` que leer. Saltearlo con seguridad es lo que
    // impide que UN elemento basura tire toda la funcion — sin este guard,
    // `day.name` de mas abajo lanza `TypeError` ANTES de que se escriba
    // ningun finding (ni los top-level, ni los del resto del array), asi que
    // el filtro entero queda desactivado para ese write. El elemento queda
    // tal cual en el array: no es nuestro trabajo "arreglarlo", solo no dejar
    // que apague el resto del documento.
    if (day === null || typeof day !== "object") return day;
    let out = day;

    const nameVerdict = verdictFor(day.name);
    if (nameVerdict) {
      findings.push({ field: `days[${i}].name`, verdict: nameVerdict });
      if (nameVerdict === "block") {
        out = { ...out, name: REDACTADO };
        daysChanged = true;
      }
    }

    const slots: RoutineSlotLike[] = Array.isArray(day.slots) ? day.slots : [];
    let slotsChanged = false;
    const newSlots = slots.map((slot, j) => {
      // Mismo motivo que el guard de `day` de arriba, un nivel mas adentro:
      // un `slots: [null]` no puede apagar el filtro de `day.name` ni del
      // resto de los slots del mismo dia.
      if (slot === null || typeof slot !== "object") return slot;
      const notesVerdict = verdictFor(slot.notes);
      if (!notesVerdict) return slot;
      findings.push({
        field: `days[${i}].slots[${j}].notes`,
        verdict: notesVerdict,
      });
      if (notesVerdict !== "block") return slot;
      slotsChanged = true;
      return { ...slot, notes: REDACTADO };
    });
    if (slotsChanged) {
      out = { ...out, slots: newSlots };
      daysChanged = true;
    }

    return out;
  });

  if (findings.length === 0) return [];

  // El registro se escribe para CADA finding, block o review — mismo criterio
  // que `quarantineIfVetted`: `review` es "que alguien lo mire", y si no
  // queda anotado en ningun lado no significa nada.
  for (const f of findings) {
    await escribirRegistroVersionado(db, idFor(f.field), updateTime, {
      path,
      field: f.field,
      kind: "routine",
      verdict: f.verdict,
      authorUid: authorUid ?? null,
      redacted: f.verdict === "block",
      at: new Date(),
    });
  }

  const hasBlocked = findings.some((f) => f.verdict === "block");
  if (!hasBlocked) return findings;

  const update: Record<string, unknown> = { ...topLevelRedactions };
  if (daysChanged) update.days = newDays;

  try {
    await db
      .doc(path)
      .update(update, updateTime ? { lastUpdateTime: updateTime } : {});
  } catch (err) {
    // FAILED_PRECONDITION: la rutina cambio despues del evento. No se pisa:
    // la escritura nueva disparo su propio trigger y se revisa por su cuenta.
    if ((err as { code?: number }).code === FAILED_PRECONDITION) {
      logger.info("quarantine: la rutina cambio, la revisa su propio evento", {
        path,
      });
      // Un solo `update()` cubre TODOS los findings bloqueados de este write
      // (todo `days` se reescribe entero). Si aborta, ninguno se redacto de
      // verdad: hay que corregir el registro de cada uno, no solo del primero.
      await Promise.all(
        findings
          .filter((f) => f.verdict === "block")
          .map((f) => marcarRedaccionAbandonada(db, idFor(f.field), updateTime)),
      );
      return findings;
    }
    throw err;
  }
  logger.warn("rutina con contenido vetado redactada por el servidor", {
    path,
  });

  return findings;
}

// ---------------------------------------------------------------------------
// Wrappers. `onDocumentWritten` y no `onDocumentCreated`: editar un post
// cambia su texto, y el guard del cliente vive en `PostRepository.update` por
// el mismo motivo. Un trigger solo-create deja abierta la puerta de crear algo
// limpio y editarlo.
// ---------------------------------------------------------------------------

const REGION = "southamerica-east1";

export const quarantinePost = onDocumentWritten(
  { document: "posts/{postId}", region: REGION },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    const db = getFirestore();
    const authorUid = after.get("authorUid") as string | undefined;

    await quarantineIfVetted({
      db,
      path: after.ref.path,
      field: "text",
      value: after.get("text"),
      kind: "post",
      authorUid,
      updateTime: after.updateTime,
    });

    // `authorDisplayName` viaja DENORMALIZADO en el post y lo pone el cliente:
    // la regla de create (`firestore.rules:1388`) lo acepta sin atarlo al
    // perfil. Un llamador por SDK directo puede crear un post con `text`
    // limpio y un nombre vetado en el encabezado, que `PostCard` renderiza tal
    // cual — y mirando solo `text` ese nombre se quedaba ahi para siempre.
    //
    // Se redacta con el mismo reemplazo derivado del uid que usa el perfil,
    // para que el post no quede sin autor visible.
    await quarantineAuthorName({
      db,
      path: after.ref.path,
      authorUid: authorUid ?? "",
      name: after.get("authorDisplayName"),
      updateTime: after.updateTime,
    });
  },
);

/**
 * Los ESPEJOS publicos del nombre, que el dueno puede escribir directo.
 *
 * `firestore.rules:1568` deja al dueno escribir `userPublicProfiles/{uid}` y
 * `firestore.rules:1864` deja al entrenador escribir
 * `trainerPublicProfiles/{uid}`. Escuchar solo `users/{uid}` dejaba abierto
 * justamente el bypass por SDK directo que esta capa existe para cerrar: los
 * dos documentos son los que alimentan la busqueda de perfiles y el
 * descubrimiento de PFs.
 *
 * Los dos delegan en `quarantineDisplayName`, que limpia los TRES documentos.
 * No hay bucle: el reemplazo es un nombre limpio, asi que la pasada siguiente
 * devuelve `ok`.
 */
export const quarantinePublicProfileName = onDocumentWritten(
  { document: "userPublicProfiles/{uid}", region: REGION },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    await quarantineDisplayName(
      getFirestore(),
      event.params.uid,
      after.get("displayName"),
    );
  },
);

/**
 * El nombre quedó corto: además del `displayName`, este trigger también
 * cuarentena `trainerBio` — no se separó en un segundo `onDocumentWritten`
 * sobre el mismo documento (mismo criterio que `quarantinePost`, que ya
 * corre `quarantineIfVetted` + `quarantineAuthorName` juntos en un solo
 * trigger: un doc, un evento, una sola vuelta).
 *
 * `trainerBio` usa `quarantineIfVetted` directo, NO `quarantineDisplayName`:
 * a diferencia del nombre, el reemplazo es la cadena vacía (no hay que
 * derivar nada del uid) y sólo vive en ESTE documento — `users/{uid}` también
 * guarda una copia, pero esa es owner-only read (`firestore.rules:234`) y
 * nunca la lee otro usuario, así que no entra al criterio de esta capa
 * ("si otro usuario lo va a leer"). Redactar sólo el espejo público es
 * suficiente para Guideline 1.2.
 */
export const quarantineTrainerProfileName = onDocumentWritten(
  { document: "trainerPublicProfiles/{uid}", region: REGION },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    const db = getFirestore();
    await quarantineDisplayName(db, event.params.uid, after.get("displayName"));

    // `quarantineDisplayName` pudo haber escrito sobre ESTE MISMO documento:
    // si el displayName estaba vetado, su batch toca `trainerPublicProfiles`.
    // Usar `after.updateTime` (el snapshot ANTERIOR a ese batch) como
    // precondicion de abajo la deja vieja, el `update()` de `trainerBio`
    // aborta con FAILED_PRECONDITION, y la bio no se redacta en esta pasada
    // aunque este vetada. Releer el doc antes de usarlo es lo que hace que
    // la primera pasada redacte las DOS cosas y no dependa de que el batch
    // vuelva a disparar este mismo trigger para autocurarse.
    const fresh = await db.doc(after.ref.path).get();
    if (!fresh.exists) return;

    await quarantineIfVetted({
      db,
      path: after.ref.path,
      field: "trainerBio",
      value: fresh.get("trainerBio"),
      kind: "profile",
      authorUid: event.params.uid,
      updateTime: fresh.updateTime,
    });
  },
);

export const quarantineChatMessage = onDocumentWritten(
  { document: "chats/{chatId}/messages/{messageId}", region: REGION },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    await quarantineIfVetted({
      db: getFirestore(),
      path: after.ref.path,
      field: "text",
      value: after.get("text"),
      kind: "message",
      authorUid: after.get("senderId") as string | undefined,
      updateTime: after.updateTime,
    });
  },
);

export const quarantineReview = onDocumentWritten(
  { document: "reviews/{reviewId}", region: REGION },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    await quarantineIfVetted({
      db: getFirestore(),
      path: after.ref.path,
      field: "comment",
      value: after.get("comment"),
      kind: "review",
      authorUid: after.get("athleteId") as string | undefined,
      updateTime: after.updateTime,
    });
  },
);

/**
 * Cuarentena de rutinas — wrapper fino, mismo patron que los de arriba.
 * Ver el dartdoc de [quarantineRoutineIfVetted] para el porque de la logica
 * de adentro.
 *
 * `authorUid` sale de `createdBy` (rutina propia del atleta) o, si no esta,
 * de `assignedBy` (plan asignado o plantilla del PF) — quien haya escrito el
 * texto. `assignedTo` NUNCA es el autor: es el alumno al que se la comparte,
 * no quien la redacto.
 */
export const quarantineRoutine = onDocumentWritten(
  { document: "routines/{routineId}", region: REGION },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    const data = after.data() ?? {};
    await quarantineRoutineIfVetted({
      db: getFirestore(),
      path: after.ref.path,
      data,
      authorUid:
        (data.createdBy as string | undefined) ??
        (data.assignedBy as string | undefined),
      updateTime: after.updateTime,
    });
  },
);

export const quarantineDisplayNameOnWrite = onDocumentWritten(
  { document: "users/{uid}", region: REGION },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    await quarantineDisplayName(
      getFirestore(),
      event.params.uid,
      after.get("displayName"),
    );
  },
);
