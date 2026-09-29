/**
 * token-un-solo-uso.ts — el link de un solo uso que verifica que quien pide un
 * trámite sin login es el dueño del buzón.
 *
 * Lo usan los dos botones legales que la Disp. 954/2025 obliga a dejar públicos
 * y sin registración previa: el de BAJA (`baja-por-mail.ts`) y el de
 * ARREPENTIMIENTO (`arrepentimiento-por-mail.ts`). Las dos acciones son
 * irreversibles en Mercado Pago, así que el canje del token es la parte que no
 * puede tener dos versiones: un arreglo en una que no llegue a la otra deja un
 * botón de arrepentimiento con el agujero que ya se cerró en el de baja.
 *
 * ── ⚠️ Invariantes que no se negocian ──
 *
 * **1. El token crudo no se guarda.** El id del documento es su SHA-256. Quien
 * lea la colección —un backup, una exportación, un operador— no puede canjear
 * nada.
 *
 * **2. Un solo uso, con reclamo en TRANSACCIÓN.** Dos clicks simultáneos leen
 * `usedAt: null` los dos; la transacción hace que sólo uno escriba.
 *
 * **3. Si la acción no pasó, el link se LIBERA.** Un link quemado sobre una baja
 * que no ocurrió deja a la persona sin salida. El `claimId` evita la carrera
 * mala: si otro request ya reclamó el token, éste no le pisa el reclamo.
 *
 * **4. El uid sale del DOCUMENTO del token, nunca del request.**
 *
 * Cada trámite usa SU colección (`mp_bajas_por_mail`,
 * `mp_arrepentimientos_por_mail`): así un token emitido para uno no se puede
 * canjear en el otro por construcción, sin depender de un campo que alguien
 * podría olvidarse de chequear.
 */

import { createHash } from "crypto";

import { App } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

/**
 * Cuánto vive un link. 72 horas: lo bastante para que quien lo pidió un
 * viernes a la noche lo encuentre el lunes, y lo bastante corto para que un
 * mail viejo olvidado en una casilla compartida no sea un botón permanente.
 */
export const TOKEN_TTL_MS = 72 * 60 * 60 * 1000;

/** 32 bytes en base64url, sin padding: 43 caracteres. */
export const TOKEN_SHAPE = /^[A-Za-z0-9_-]{43}$/;

/** SHA-256 en hex. Es el id del documento: el token crudo nunca se guarda. */
export function hashToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

/** Resultado interno del reclamo del token. */
export type Reclamo =
  | { ok: false; status: "invalido" | "ya-usado" | "vencido" }
  | { ok: true; uid: string; code: string | null; claimId: string };

/**
 * Reclama el token en transacción. Devuelve el uid que dice el DOCUMENTO.
 *
 * @param ref - `<coleccion>/<sha256 del token>`.
 */
export async function reclamarToken(
  app: App,
  ref: FirebaseFirestore.DocumentReference,
  nowMs: number,
  claimId: string,
): Promise<Reclamo> {
  return getFirestore(app).runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return { ok: false, status: "invalido" } as const;
    const d = snap.data() ?? {};
    if (d.usedAt != null) return { ok: false, status: "ya-usado" } as const;
    const vence = (d.expiresAt as { toMillis?: () => number } | undefined)?.toMillis?.();
    if (typeof vence !== "number" || vence <= nowMs) {
      return { ok: false, status: "vencido" } as const;
    }
    if (typeof d.uid !== "string" || d.uid === "") {
      return { ok: false, status: "invalido" } as const;
    }
    tx.update(ref, { usedAt: Timestamp.fromMillis(nowMs), claimId });
    return {
      ok: true,
      uid: d.uid,
      code: typeof d.code === "string" ? d.code : null,
      claimId,
    } as const;
  });
}

/**
 * Devuelve el token a `usedAt: null`, SÓLO si el reclamo sigue siendo el
 * nuestro.
 *
 * Nunca tira. Un reclamo que no se pudo liberar deja el link quemado —la
 * persona cae al canal manual— que es peor que liberarlo, pero no peor que
 * reventar la respuesta.
 */
export async function liberarReclamo(
  app: App,
  ref: FirebaseFirestore.DocumentReference,
  claimId: string,
): Promise<void> {
  try {
    await getFirestore(app).runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.data()?.claimId !== claimId) return;
      tx.update(ref, { usedAt: null, claimId: null });
    });
  } catch (error: unknown) {
    logger.warn("tokenUnSoloUso: no se pudo liberar el reclamo", {
      id: ref.id,
      error: String(error),
    });
  }
}
