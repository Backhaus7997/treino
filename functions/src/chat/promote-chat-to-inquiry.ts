/**
 * promoteChatToInquiry — estampa `kind: 'inquiry'` en un chat que YA existe.
 *
 * ## ESTADO ACTUAL (desde 2026-10-21, REQ-FOLLOW-012)
 *
 * Lo que sigue explica POR QUÉ se escribió esta callable, y ese motivo ya no
 * existe. `senderMayPost` dejó de mirar `kind`, `linkId` y el follow: en un
 * chat que ya existe escriben los dos miembros y sólo corta un bloqueo o
 * `closedAt` (ver el bloque de `chats` en `firestore.rules`). `kind` ya no
 * habilita escribir; sólo lo lee `chatCreateOk`, al CREAR el chat.
 *
 * Estampar `kind: 'inquiry'` en un chat existente es hoy un dato que ninguna
 * rule ni función consulta después. La callable sigue desplegada y la llama
 * `TrainerInquiryCta`, pero es candidata a código muerto (#1722): quitarla
 * implica borrar la llamada del cliente, el servicio, esta función y su
 * entrada en el enforcement de App Check, y el borrado de la función en
 * producción lo hace un humano.
 *
 * ## El bug que arreglaba
 *
 * `ChatRepository.getOrCreate` sale temprano si el doc ya existe, y la marca
 * `'kind': 'inquiry'` sólo se estampa al CREAR. Y `firestore.rules` tiene
 * `kind` pineado como inmutable en el `update` (ver el bloque de `chats`,
 * "⚠ `kind` PINEADO").
 *
 * Resultado, hasta el 2026-10-21: si entre un alumno y un PF ya existía un
 * chat social —creado cuando el PF lo seguía, y después dejó de seguirlo—,
 * tocar CONSULTAR no estampaba nada, la marca no se podía agregar NUNCA MÁS
 * desde el cliente, y el alumno quedaba sin poder escribirle a ese PF para
 * siempre. El cartel que veía decía "esta persona tiene que seguirte", que ni
 * siquiera era el motivo.
 *
 * ## Por qué una callable y no relajar la regla
 *
 * El pin de `kind` no era incidental: su comentario en `firestore.rules`
 * documenta el agujero que tapaba —convertir un chat social en consulta con un
 * update de una línea, saltándose el gate de follow y auto-otorgándose
 * escritura permanente que sobrevivía al unfollow—. Relajarlo para la
 * transición `ausente -> 'inquiry'` lo reabría parcialmente. (Hoy la marca ya
 * no da escritura, pero el pin sigue en las rules y no se tocó.)
 *
 * La otra alternativa —darle a `senderMayPost` una cuarta rama que evaluara los
 * hechos en vivo— tenía una asimetría direccional que la rompía: cuando el que
 * escribe es el PF, `other` es el ALUMNO, que no es trainer, así que el PF
 * perdería la respuesta. Y responder es la mitad de la feature.
 *
 * El Admin SDK no pasa por las rules, así que acá se puede validar con toda
 * libertad y recién después escribir. El pin del cliente queda intacto.
 *
 * ## Qué valida
 *
 * Los MISMOS tres hechos que `chatCreateOk` verifica en su rama de consulta al
 * crear, ni uno más ni uno menos: que el destinatario sea un PF real
 * (`users/{id}.role == 'trainer'`, el único hecho no auto-declarable del
 * sistema), que haya PUBLICADO su perfil de discovery
 * (`trainerPublicProfiles/{id}`), y que no haya cerrado la puerta
 * (`acceptsInquiries`). Agregar condiciones que el `create` no tiene haría que
 * dos caminos al mismo estado pidieran cosas distintas.
 *
 * ## Por qué transacción
 *
 * `notifyLinkChange` le estampa `linkId` a un chat que ya existe, también en
 * transacción. Sin transacción acá, un alumno que toca CONSULTAR justo cuando
 * le aceptan el vínculo puede terminar con un doc que tiene `linkId` Y `kind`
 * — el "campo mentiroso" que el comentario de `getOrCreate` existe para
 * evitar, y que la lista de chats mostraría como consulta siendo de Coach.
 *
 * Patrón: handler puro (`runPromoteChatToInquiry`) + wrapper `onCall` fino,
 * igual que `accept-trainer-link.ts` / `add-alias.ts` (ADR-CXP-004).
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/** Espejo de `ChatRepository.chatIdFor`: el id es determinístico por par. */
export function chatIdFor(uidA: string, uidB: string): string {
  return [uidA, uidB].sort().join("_");
}

export interface PromoteChatToInquiryResult {
  /** `noop` = no había nada que estampar (ya estaba, o es chat de Coach). */
  status: "ok" | "noop";
}

export async function runPromoteChatToInquiry(
  app: App,
  callerUid: string,
  trainerId: string,
): Promise<PromoteChatToInquiryResult> {
  if (!trainerId) {
    throw new HttpsError("invalid-argument", "trainerId is required.");
  }
  if (trainerId === callerUid) {
    throw new HttpsError("invalid-argument", "Cannot open an inquiry with yourself.");
  }

  const db = getFirestore(app);
  // El chatId se DERIVA acá, no se acepta del cliente: así el llamador sólo
  // puede tocar el chat que le corresponde con ese PF.
  const chatRef = db.collection("chats").doc(chatIdFor(callerUid, trainerId));
  const userRef = db.collection("users").doc(trainerId);
  const pubRef = db.collection("trainerPublicProfiles").doc(trainerId);

  return db.runTransaction<PromoteChatToInquiryResult>(async (tx) => {
    // Firestore exige TODAS las lecturas antes de cualquier escritura.
    const chat = await tx.get(chatRef);
    if (!chat.exists) {
      // No es un error del usuario: sin doc, `getOrCreate` crea uno con la
      // marca puesta y esta callable no hace falta.
      throw new HttpsError("not-found", "No existing chat to promote.");
    }

    const members = chat.get("members");
    if (!Array.isArray(members) || !members.includes(callerUid)) {
      throw new HttpsError("permission-denied", "Not a member of this chat.");
    }

    const linkId = chat.get("linkId");
    if (typeof linkId === "string" && linkId.length > 0) {
      // Chat de Coach: ya es un chat de Coach. Marcarlo sería el campo
      // mentiroso. Y si el alumno abre la consulta con el PF que YA es su
      // entrenador, lo que quiere es su chat de Coach de siempre.
      return { status: "noop" };
    }

    const kind = chat.get("kind");
    if (kind === "inquiry") return { status: "noop" };
    if (kind !== undefined && kind !== null) {
      throw new HttpsError(
        "failed-precondition",
        "Chat already carries a different kind.",
      );
    }

    const [user, pub] = await Promise.all([tx.get(userRef), tx.get(pubRef)]);
    if (user.get("role") !== "trainer") {
      throw new HttpsError("failed-precondition", "Recipient is not a trainer.");
    }
    if (!pub.exists) {
      throw new HttpsError(
        "failed-precondition",
        "Trainer has not published a discovery profile.",
      );
    }
    if (pub.get("acceptsInquiries") === false) {
      throw new HttpsError(
        "failed-precondition",
        "Trainer is not accepting inquiries.",
      );
    }
    // Pausa del PF (`acceptingAthletes`): espeja `pfTomaAlumnos` del create
    // de chats, que lo lee de `users/{uid}` y no del doc público.
    if (user.get("acceptingAthletes") === false) {
      throw new HttpsError(
        "failed-precondition",
        "Trainer is not accepting new athletes.",
      );
    }

    tx.update(chatRef, { kind: "inquiry" });
    logger.info("promoteChatToInquiry: chat stamped", {
      event: "chat-promoted-to-inquiry",
      chatId: chatRef.id,
      trainerId,
    });
    return { status: "ok" };
  });
}

export const promoteChatToInquiry = functions.onCall(
  // SIN enforceAppCheck, y NO por la razón de acceptTrainerLink. Ésta la llama
  // sólo la app mobile del alumno, que sí activa App Check — así que por
  // plataforma el flag correspondería.
  //
  // No va porque la atestación de esta app no funciona. La medición ancha del
  // #961 (24 días, 6 callables, 159 verificaciones) encontró `acceptTrainerLink`
  // y `requestPasswordReset` en CERO atestaciones válidas, y `mintWatchCredential`
  // en 53%. Con el flag puesto, CONSULTAR no fallaría "a veces": fallaría casi
  // siempre. Es la historia de `deleteAccount` (#811), que tuvo el flag un mes y
  // en ese lapso el borrado de cuenta no funcionó nunca.
  //
  // Un flag que convierte un botón en un error permanente no da seguridad, da
  // un botón roto (PR #704). Ver la entrada de este callable en EXEMPTIONS.
  { region: "southamerica-east1" },
  async (request): Promise<PromoteChatToInquiryResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const { trainerId } = request.data as { trainerId?: string };
    if (!trainerId) {
      throw new HttpsError("invalid-argument", "trainerId is required.");
    }

    return runPromoteChatToInquiry(ensureApp(), request.auth.uid, trainerId);
  },
);
