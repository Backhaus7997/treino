/**
 * retry-partial-deletions.ts — completa los borrados de cuenta que terminaron
 * `partial` (#1353).
 *
 * `runDeleteAccount` deja cada paso de la cascada en su propio try/catch: si
 * uno falla por un error transitorio, la cuenta se borra igual (`users/{uid}` y
 * Auth) y `audit_log/{uid}` queda en `status: 'partial'` con la lista de
 * errores. El cliente lo toma como exito, asi que la persona no puede
 * reintentar y esos datos quedaban para siempre. Este barrido diario los
 * termina solo.
 *
 * ─── Que corre, y que NO ────────────────────────────────────────────────────
 *
 *  · Corre SOLO los pasos de datos (`runDataCascade`: Firestore + Storage).
 *    Desde #1341 son idempotentes y no dependen de `users/{uid}`.
 *  · NO toca Mercado Pago: la baja de MP es fail-closed y va primero, asi que
 *    un `partial` ya la paso. Re-cancelar no corresponde.
 *  · NO toca Auth... salvo que el `partial` original haya sido POR Auth (una
 *    entrada `auth: ...` en `errors`): ahi la identidad sigue viva y hay que
 *    darla de baja. `auth/user-not-found` cuenta como exito (idempotente).
 *    OJO, es a proposito: en ese caso la cuenta sigue VIVA y puede haber
 *    creado datos DESPUES del borrado fallido; el barrido los borra antes de
 *    dar de baja Auth. Es lo que la persona pidio (eliminar su cuenta) y lo que
 *    habria hecho el borrado original de haber salido bien: dejar la identidad
 *    sin datos propios seria un borrado a medias, no una cuenta nueva.
 *  · NO vuelve a avisar a nadie. Los avisos son triggers sobre el WRITE
 *    (`notify-link-change`, `notify-appointment`), y los pasos de terminar
 *    vinculos / cancelar turnos filtran lo ya terminado/cancelado: un
 *    reintento no escribe sobre eso. Lo que SI se escribe por primera vez
 *    (porque el paso habia fallado) avisa una sola vez, como habria hecho el
 *    borrado original.
 *
 * ─── Intentos ───────────────────────────────────────────────────────────────
 *
 * `retryCount` / `lastRetryAt` viven en el propio `audit_log/{uid}`. Corrida
 * diaria = un intento por dia; es el backoff. Al intento [MAX_RETRY_ATTEMPTS]
 * sin exito el doc pasa a `failed` y se loguea a nivel error: esa linea es la
 * alerta (hay que revisarlo a mano). Un `failed` no se vuelve a mirar.
 *
 * ─── Carrera con un borrado que se vuelve a correr ──────────────────────────
 *
 * El barrido lee el doc, corre una cascada larga y recien despues escribe. Si
 * en el medio la persona vuelve a pedir el borrado, `writeStarted` hace set()
 * y deja un doc fresco; una escritura ciega con el snapshot viejo lo pisaria
 * con estado y errores obsoletos. Toda escritura derivada del snapshot lleva
 * `lastUpdateTime` como precondicion: si el doc cambio, Firestore la rechaza
 * (FAILED_PRECONDITION) y ese uid se saltea; manda el borrado nuevo.
 *
 * `audit_log` es Admin-only, y la query es de igualdad sobre un solo campo
 * (indice automatico; no hay fieldOverride sobre `audit_log`).
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import {
  DocumentReference,
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { DataCascadeResult, runDataCascade } from "../cascade/run-data-cascade";

/** Intentos del barrido antes de rendirse y marcar `failed`. */
export const MAX_RETRY_ATTEMPTS = 5;

/** Docs `partial` que se procesan por corrida. */
export const RETRY_BATCH_LIMIT = 20;

/**
 * Opciones del schedule. Hasta 20 cascadas secuenciales (varios segundos c/u en cuentas grandes) (cada una recorre
 * Firestore + Storage) exceden el default de 60 s: se pide el maximo de una
 * funcion programada (540 s) y 512 MiB para los listados de Storage.
 */
export const RETRY_SCHEDULE_OPTIONS = {
  // 06:00 ART: despues de `sweepInactiveAccounts` (05:00), asi completa
  // tambien lo que esa baja dejo parcial en la misma noche.
  schedule: "0 6 * * *",
  timeZone: "America/Argentina/Buenos_Aires",
  region: "southamerica-east1",
  timeoutSeconds: 540,
  memory: "512MiB" as const,
};

export interface RetryPartialOptions {
  limit?: number;
  maxAttempts?: number;
  /** Inyectable para tests; por defecto la cascada real de datos. */
  cascade?: (app: App, uid: string) => Promise<DataCascadeResult>;
}

export interface RetryPartialResult {
  scanned: number;
  succeeded: number;
  stillPartial: number;
  failed: number;
  /** Docs que cambiaron durante el reintento (otro borrado en curso). */
  skipped: number;
}

const FAILED_PRECONDITION = 9;

function isPreconditionFailure(err: unknown): boolean {
  const code = (err as { code?: unknown }).code;
  return code === FAILED_PRECONDITION || code === "failed-precondition";
}

/** update() que solo aplica si el doc sigue como lo leyo el barrido. */
function updateIfUnchanged(
  ref: DocumentReference,
  readAt: Timestamp,
  data: Record<string, unknown>
) {
  return ref.update(data, { lastUpdateTime: readAt });
}

async function retryAuthDeletion(app: App, uid: string): Promise<string[]> {
  try {
    await getAuth(app).deleteUser(uid);
  } catch (err: unknown) {
    if ((err as { code?: string }).code !== "auth/user-not-found") {
      return [`auth: ${(err as Error).message ?? String(err)}`];
    }
  }
  return [];
}

export async function retryPartialDeletionsHandler(
  app: App,
  opts: RetryPartialOptions = {}
): Promise<RetryPartialResult> {
  const limit = opts.limit ?? RETRY_BATCH_LIMIT;
  const maxAttempts = opts.maxAttempts ?? MAX_RETRY_ATTEMPTS;
  const cascadeFn = opts.cascade ?? runDataCascade;
  const db = getFirestore(app);
  const r: RetryPartialResult = {
    scanned: 0, succeeded: 0, stillPartial: 0, failed: 0, skipped: 0,
  };

  const snap = await db
    .collection("audit_log")
    .where("status", "==", "partial")
    .limit(limit)
    .get();

  for (const doc of snap.docs) {
    r.scanned++;
    const uid = doc.id;
    const readAt = doc.updateTime;
    const data = doc.data();
    const previous = typeof data.retryCount === "number" ? data.retryCount : 0;
    const previousErrors: string[] = Array.isArray(data.errors) ? data.errors : [];

    try {
      // Ya agoto los intentos (p. ej. se bajo el tope): se cierra sin correr.
      if (previous >= maxAttempts) {
        await updateIfUnchanged(doc.ref, readAt, { status: "failed", lastRetryAt: FieldValue.serverTimestamp() });
        r.failed++;
        logger.error("retryPartialDeletions: borrado parcial sin completar, revisar a mano", {
          uid, attempts: previous, errors: previousErrors,
        });
        continue;
      }

      const cascade = await cascadeFn(app, uid);
      const errors = [...cascade.errors];
      if (previousErrors.some((e) => e.startsWith("auth:"))) {
        errors.push(...(await retryAuthDeletion(app, uid)));
      }
      const attempt = previous + 1;
      const base = {
        retryCount: attempt,
        lastRetryAt: FieldValue.serverTimestamp(),
        errors,
      };

      if (errors.length === 0) {
        await updateIfUnchanged(doc.ref, readAt, {
          ...base,
          status: "success",
          retriedAt: FieldValue.serverTimestamp(),
          deletedCollections: FieldValue.arrayUnion(...cascade.deletedCollections),
        });
        r.succeeded++;
        logger.info("retryPartialDeletions: borrado completado", { uid, attempt });
      } else if (attempt >= maxAttempts) {
        await updateIfUnchanged(doc.ref, readAt, { ...base, status: "failed" });
        r.failed++;
        logger.error("retryPartialDeletions: borrado parcial sin completar, revisar a mano", {
          uid, attempts: attempt, errors,
        });
      } else {
        await updateIfUnchanged(doc.ref, readAt, base);
        r.stillPartial++;
        logger.warn("retryPartialDeletions: el borrado sigue parcial", { uid, attempt, errors });
      }
    } catch (err) {
      if (isPreconditionFailure(err)) {
        // Cambio mientras corria la cascada (p. ej. nuevo deleteAccount):
        // el doc fresco manda, no se pisa con el snapshot viejo.
        r.skipped++;
        logger.info("retryPartialDeletions: el audit log cambio durante el reintento, se saltea", { uid });
        continue;
      }
      // Un doc roto no frena a los demas; sigue `partial` y se reintenta manana.
      logger.error("retryPartialDeletions: error procesando un borrado parcial", { uid, err });
    }
  }
  return r;
}

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

export const retryPartialDeletions = onSchedule(
  RETRY_SCHEDULE_OPTIONS,
  async () => {
    const r = await retryPartialDeletionsHandler(ensureApp());
    logger.info("retryPartialDeletions: corrida diaria", r);
  },
);
