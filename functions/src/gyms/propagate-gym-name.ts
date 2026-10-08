/**
 * Propaga `gyms/{id}.name` a la copia denormalizada
 * `userPublicProfiles.gymName` (politica de Places, #1338).
 *
 * `gymName` lo escribe el cliente al vincular el gym (`UserRepository.update`),
 * y desde la politica de Places es `null` mientras el gym esta marcado
 * `nameNeeded`. Dos eventos dejaban esa copia mintiendo:
 *
 *  - un gym migrado se nombra DESPUES de tener usuarios vinculados: los demas
 *    miembros quedaban con `gymName` null (o el viejo) para siempre, y las
 *    tarjetas de busqueda de gente y de solicitudes lo muestran tal cual;
 *  - la cuarentena revierte un nombre vetado (`nameNeeded: true`): las copias
 *    ya escritas conservaban el texto vetado.
 *
 * Sin bucle: escribe en `userPublicProfiles`, que este trigger no escucha, y
 * antes de escribir compara con lo que ya hay (la segunda pasada no toca nada).
 */
import { App, getApp, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

import { checkText } from "../moderation/vetted_terms_filter";

/**
 * El app de firebase-admin, inicializado si hace falta.
 *
 * `getFirestore()` SIN argumento busca el app por defecto y tira «The default
 * Firebase app does not exist» si nadie lo inicializo. `index.ts` no llama a
 * `initializeApp()`: cada modulo se lo asegura solo (mismo patron que
 * `sync-shared-profile.ts` y el resto del repo). Este modulo no lo hacia, y en
 * produccion fallaba en CADA invocacion desde el primer deploy. Los tests no
 * lo veian porque inicializaban el app por defecto ellos mismos.
 */
function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

const REGION = "southamerica-east1";

/** Tope de un WriteBatch es 500; se deja margen. */
export const PROPAGATE_PAGE_SIZE = 400;

/**
 * Nombre que corresponde mostrar: el del gym, o `null` si no existe o esta
 * marcado `nameNeeded` (su nombre no es de un usuario).
 */
function effectiveName(
  snap: FirebaseFirestore.DocumentSnapshot,
): string | null {
  if (!snap.exists || snap.get("nameNeeded") === true) return null;
  const name = snap.get("name");
  return typeof name === "string" && name.trim() !== "" ? name : null;
}

/**
 * Pone `gymName` en cada `userPublicProfiles` con `gymId == gymId`, en paginas.
 * Relee el gym (no confia en el evento): los eventos de un mismo doc pueden
 * llegar desordenados y lo unico correcto es el estado actual.
 *
 * Devuelve cuantos perfiles escribio.
 */
export async function propagateGymName(input: {
  db: Firestore;
  gymId: string;
  pageSize?: number;
}): Promise<number> {
  const { db, gymId, pageSize = PROPAGATE_PAGE_SIZE } = input;
  const gymSnap = await db.doc(`gyms/${gymId}`).get();
  const target = effectiveName(gymSnap);

  // Un nombre vetado no se copia: la cuarentena lo revierte a `nameNeeded` y
  // ese evento vuelve a pasar por aca con `null`.
  if (target !== null && checkText(target) === "block") {
    logger.info("gymName: nombre vetado, lo propaga la reversion", { gymId });
    return 0;
  }

  let written = 0;
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  for (;;) {
    let q = db
      .collection("userPublicProfiles")
      .where("gymId", "==", gymId)
      .orderBy("__name__")
      .limit(pageSize);
    if (cursor) q = q.startAfter(cursor);
    const page = await q.get();
    if (page.empty) break;

    const batch = db.batch();
    let inBatch = 0;
    for (const doc of page.docs) {
      const current = doc.get("gymName");
      if ((current ?? null) === target) continue;
      batch.update(doc.ref, { gymName: target });
      inBatch++;
    }
    if (inBatch > 0) await batch.commit();
    written += inBatch;

    if (page.size < pageSize) break;
    cursor = page.docs[page.docs.length - 1];
  }

  logger.info("gymName propagado a los perfiles publicos", { gymId, written });
  return written;
}

export const propagateGymNameToProfiles = onDocumentWritten(
  { document: "gyms/{gymId}", region: REGION },
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!before || !after) return;
    // Sólo importa si cambio el nombre que se muestra: el refresh de coords y
    // el resto de las escrituras del gym no tocan a los perfiles.
    if (effectiveName(before) === effectiveName(after)) return;
    await propagateGymName({
      db: getFirestore(ensureApp()),
      gymId: event.params.gymId,
    });
  },
);
