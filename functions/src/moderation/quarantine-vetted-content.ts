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
  await db.collection(QUARANTINE_COLLECTION).doc(id).set(
    {
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
    },
    { merge: true },
  );

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

export const quarantineTrainerProfileName = onDocumentWritten(
  { document: "trainerPublicProfiles/{uid}", region: REGION },
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
