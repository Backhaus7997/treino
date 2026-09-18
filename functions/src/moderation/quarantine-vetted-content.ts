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
}

/**
 * Handler puro. El wrapper `onDocumentWritten` de abajo es fino a proposito —
 * es el patron que este repo ya usa (`add-alias.ts:7`,
 * `mint-watch-credential.ts:46`, `places-search.ts:17`).
 */
export async function quarantineIfVetted(
  input: QuarantineInput,
): Promise<ModerationVerdict> {
  const { db, path, field, value, kind, authorUid } = input;

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

  await db.doc(path).update({ [field]: REDACTADO });
  logger.warn("contenido vetado redactado por el servidor", { path, field });

  return verdict;
}

/** Igual que arriba, pero el `displayName` vive en DOS documentos. */
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

  // Vaciarlo NO sirve acá: el nombre se renderiza en cada post, cada mensaje y
  // cada tarjeta de descubrimiento, y ademas tiene que seguir siendo unico. Un
  // reemplazo derivado del uid cumple las dos cosas y no le pone a nadie el
  // nombre de otro.
  const reemplazo = `usuario_${uid.slice(0, 6)}`;

  // Los DOS documentos, y en batch. `userPublicProfiles` es el que leen los
  // demas: dejarlo con el nombre vetado mientras `users` queda limpio es
  // redactar la copia que nadie mira.
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
  await batch.commit();

  logger.warn("displayName vetado redactado por el servidor", { uid });
  return verdict;
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
    await quarantineIfVetted({
      db: getFirestore(),
      path: after.ref.path,
      field: "text",
      value: after.get("text"),
      kind: "post",
      authorUid: after.get("authorUid") as string | undefined,
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
