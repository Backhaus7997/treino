/**
 * deleteAccount — Firebase Callable Cloud Function handler.
 *
 * Full cascade handler (PR#2): handles auth guard, anti-spoofing, audit log,
 * full Firestore/Storage cascade, and Auth user deletion (last).
 *
 * Trainers (role == 'trainer') delete their account like anyone else (#1333,
 * Apple 5.1.1(v)). There is NO role guard: the trainer steps (T1-T5, from
 * `cascade/trainer-data.ts`) run on EVERY call and are no-ops for an athlete.
 *
 * Cascade order (REQ-ACCDEL-CF-012: Auth MUST be last):
 *   1. Validate + anti-spoof (callable wrapper)
 *  2b. Cancel live Mercado Pago subscriptions — FAIL-CLOSED: if MP cannot be
 *      reached the account is NOT touched (see cascade/subscriptions.ts)
 *   3. Audit log: started
 *   4. Sweep follows
 *   5. Delete posts
 *   6. Terminate trainer links (as athlete)            + T1 as trainer
 *   7. Cancel future appointments (as athlete)         + T2 as trainer
 *   8. Delete storage avatar
 *  8b. Athlete storage                                 + T3 trainer storage
 *  8c. Athlete-owned data                              + T4 trainer data
 *  8d. Delete the athlete's routines                   + T5 trainer templates
 *   9. Delete user docs (users + userPublicProfiles + trainerPublicProfiles)
 *  10. Update audit log with cascade results
 *  11. Delete Auth user (LAST — REQ-ACCDEL-CF-012)
 *  12. Update audit log to success/partial
 *
 * ADRs: ACCDEL-001 (CF over client), ACCDEL-003 (callable), ACCDEL-010 (idempotency),
 *       ACCDEL-012 (audit log shape), ACCDEL-013 (storage trust boundary),
 *       ACCDEL-014 (anti-spoofing).
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { writeStarted, writeFinal } from "./cascade/audit-log";
import { sweepFollows } from "./cascade/friendships";
import { deletePosts } from "./cascade/posts";
import { terminateTrainerLinks } from "./cascade/trainer-links";
import { cancelFutureAppointments } from "./cascade/appointments";
import {
  deleteAvatar,
  deleteAthleteStorage,
  deleteTrainerStorage,
} from "./cascade/storage";
import {
  cancelFutureAppointmentsAsTrainer,
  deleteTrainerOwnedData,
  deleteTrainerTemplates,
  terminateLinksAsTrainer,
} from "./cascade/trainer-data";
import { deleteAthleteOwnedData } from "./cascade/athlete-data";
import { deleteAthleteRoutines } from "./cascade/routines";
import { deleteUserDocs } from "./cascade/users";
import {
  CancelarAlEliminarDeps,
  cancelarSuscripcionesAntesDeEliminar,
} from "./cascade/subscriptions";
import { createMpClient } from "./subscriptions/mp/client";
import {
  DeleteAccountRequest,
  DeleteAccountResponse,
} from "./types";

/**
 * Initialize the default Admin SDK app lazily so the module can be imported
 * without an app already existing (e.g. in test environments that set up
 * their own named apps before importing).
 */
function ensureApp(): App {
  try {
    return getApp();
  } catch {
    // No default app yet — initialize one.
    return initializeApp();
  }
}

/**
 * Token de Mercado Pago: solo hace falta para dar de baja la suscripcion de
 * quien elimina la cuenta. Vive aca y no en el callable para que el default de
 * `runDeleteAccount` sea el REAL: olvidarse de pasarlo no puede dejar una cuenta
 * borrada con el cobro vivo.
 */
const MP_ACCESS_TOKEN = defineSecret("MP_ACCESS_TOKEN");

export type DeleteAccountDeps = CancelarAlEliminarDeps;

function depsReales(): DeleteAccountDeps {
  return {
    // Perezoso: `createMpClient` tira con el token vacio, y casi ninguna cuenta
    // tiene planes. Solo se construye si hay algo que cancelar.
    getMpClient: () => createMpClient(MP_ACCESS_TOKEN.value()),
    nowMs: Date.now(),
  };
}

/**
 * Core deletion logic, extracted for unit-testability.
 * The caller supplies the firebase-admin App so tests can pass a named
 * emulator-backed app without relying on the default app.
 *
 * Each cascade step is wrapped in try/catch — a single step failure does not
 * abort the overall flow. Errors are accumulated and reported in the final
 * audit log and response.
 */
export async function runDeleteAccount(
  app: App,
  uid: string,
  provider: string,
  deps: DeleteAccountDeps = depsReales()
): Promise<DeleteAccountResponse> {
  // ── Paso 2b: dar de baja las suscripciones de Mercado Pago — FAIL-CLOSED ──
  // A diferencia de todo lo que sigue, NO acumula el error y sigue: si no se
  // pudo cancelar, tira y la cuenta queda intacta. Borrarla con el cobro vivo
  // deja a la persona pagando sin ninguna puerta para darse de baja. Ver
  // `cascade/subscriptions.ts`. Es una BAJA (sin reembolso), no un arrepentimiento.
  const suscripcionesCanceladas = await cancelarSuscripcionesAntesDeEliminar(
    app,
    uid,
    deps
  );

  // ── Audit log: started ─────────────────────────────────────────────────
  await writeStarted(app, uid, provider);

  const errors: string[] = [];
  const deletedCollections: string[] = [];
  if (suscripcionesCanceladas > 0) deletedCollections.push("mp-subscriptions");

  // ── Step 4: Sweep follows ──────────────────────────────────────────────
  try {
    await sweepFollows(app, uid);
    deletedCollections.push("follows");
  } catch (err: unknown) {
    errors.push(`follows: ${(err as Error).message ?? String(err)}`);
  }

  // ── Step 5: Delete posts ────────────────────────────────────────────────
  try {
    await deletePosts(app, uid);
    deletedCollections.push("posts");
  } catch (err: unknown) {
    errors.push(`posts: ${(err as Error).message ?? String(err)}`);
  }

  // ── Step 6: Terminate trainer links ───────────────────────────────────
  try {
    await terminateTrainerLinks(app, uid);
    deletedCollections.push("trainer_links");
  } catch (err: unknown) {
    errors.push(`trainer_links: ${(err as Error).message ?? String(err)}`);
  }

  // ── T1: Terminate the links where this uid is the TRAINER (#1333) ──────
  // Reason `trainer-account-deleted`: notify-link-change tells each athlete.
  try {
    await terminateLinksAsTrainer(app, uid);
    deletedCollections.push("trainer-links");
  } catch (err: unknown) {
    errors.push(`trainer-links: ${(err as Error).message ?? String(err)}`);
  }

  // ── Step 7: Cancel future appointments ────────────────────────────────
  try {
    await cancelFutureAppointments(app, uid);
    deletedCollections.push("appointments");
  } catch (err: unknown) {
    errors.push(`appointments: ${(err as Error).message ?? String(err)}`);
  }

  // ── T2: Cancel the trainer's future appointments + availability ────────
  try {
    await cancelFutureAppointmentsAsTrainer(app, uid);
    deletedCollections.push("trainer-appointments");
  } catch (err: unknown) {
    errors.push(`trainer-appointments: ${(err as Error).message ?? String(err)}`);
  }

  // ── Step 8: Delete storage avatar ─────────────────────────────────────
  // Admin SDK bypasses Storage security rules (ADR-ACCDEL-013).
  try {
    await deleteAvatar(app, uid);
    deletedCollections.push("storage");
  } catch (err: unknown) {
    errors.push(`storage: ${(err as Error).message ?? String(err)}`);
  }

  // ── Step 8b: Delete the athlete's other Storage objects (QA-CMP-002) ───
  // chatMedia / customExerciseVideos / temp uploads / athleteFiles.
  try {
    await deleteAthleteStorage(app, uid);
    deletedCollections.push("storage-athlete");
  } catch (err: unknown) {
    errors.push(`storage-athlete: ${(err as Error).message ?? String(err)}`);
  }

  // ── T3: Delete the files the trainer authored for athletes ─────────────
  try {
    await deleteTrainerStorage(app, uid);
    deletedCollections.push("trainer-storage");
  } catch (err: unknown) {
    errors.push(`trainer-storage: ${(err as Error).message ?? String(err)}`);
  }

  // ── Step 8c: Delete athlete-owned Firestore data (QA-CMP-003) ──────────
  // measurements, performance_tests, profile_shares, session_shares,
  // athlete_billing, athlete_notes, follow_up_entries, nutrition_plans.
  try {
    await deleteAthleteOwnedData(app, uid);
    deletedCollections.push("athlete-data");
  } catch (err: unknown) {
    errors.push(`athlete-data: ${(err as Error).message ?? String(err)}`);
  }

  // ── T4: Delete the data the trainer wrote/was granted about athletes ───
  // payments are RETAINED (fiscal). See cascade/trainer-data.ts.
  try {
    await deleteTrainerOwnedData(app, uid);
    deletedCollections.push("trainer-data");
  } catch (err: unknown) {
    errors.push(`trainer-data: ${(err as Error).message ?? String(err)}`);
  }

  // ── Step 8d: Delete the athlete's routines (QA-CMP-004) ────────────────
  // `routines where assignedTo == uid` (the plans their trainer built for
  // them) + `routines where createdBy == uid` (their own). recursiveDelete,
  // so the `ratings` subcollection goes with the parent. The disposition and
  // the reason `assignedBy` is NOT swept live in cascade/routines.ts.
  try {
    await deleteAthleteRoutines(app, uid);
    deletedCollections.push("routines");
  } catch (err: unknown) {
    errors.push(`routines: ${(err as Error).message ?? String(err)}`);
  }

  // ── T5: Delete the trainer's templates (published too) ─────────────────
  // Plans assigned to athletes stay with them. See cascade/trainer-data.ts.
  try {
    await deleteTrainerTemplates(app, uid);
    deletedCollections.push("trainer-templates");
  } catch (err: unknown) {
    errors.push(`trainer-templates: ${(err as Error).message ?? String(err)}`);
  }

  // ── Step 9: Delete user docs ───────────────────────────────────────────
  try {
    await deleteUserDocs(app, uid);
    deletedCollections.push("users");
    deletedCollections.push("userPublicProfiles");
  } catch (err: unknown) {
    errors.push(`users: ${(err as Error).message ?? String(err)}`);
  }

  // ── Step 10-11: Auth user deletion (REQ-ACCDEL-CF-012) ─────────────────
  // MUST be last — so a retry after a mid-cascade failure still finds the account.
  try {
    await getAuth(app).deleteUser(uid);
    deletedCollections.push("users-auth");
  } catch (authErr: unknown) {
    // Idempotency (REQ-ACCDEL-CF-013): if the user was already deleted
    // in a prior partial run, treat it as a no-op.
    const code = (authErr as { code?: string }).code;
    if (code !== "auth/user-not-found") {
      errors.push(`auth: ${(authErr as Error).message ?? String(authErr)}`);
    } else {
      // Already deleted — still mark as complete for idempotent runs
      if (!deletedCollections.includes("users-auth")) {
        deletedCollections.push("users-auth");
      }
    }
  }

  // ── Audit log: final ───────────────────────────────────────────────────
  const finalStatus = errors.length > 0 ? "partial" : "success";
  try {
    await writeFinal(app, uid, finalStatus, deletedCollections, errors);
  } catch {
    // Swallow audit write failure — cascade results take priority.
  }

  // ── Structured response (REQ-ACCDEL-CF-014) ────────────────────────────
  return {
    status: finalStatus,
    deletedCollections,
    errors,
  };
}

/**
 * The v2 callable exported as the Firebase Function.
 * Named export so firebase-functions-test can wrap it directly.
 */
export const deleteAccountHandler = functions.onCall(
  // Region aligned with the existing parsePlan CF for latency
  // consistency for LATAM users.
  //
  // SIN enforceAppCheck (2026-08-25). Lo tuvo desde el 2026-07-20 (commit
  // 2bb8d1c7, QA-SEC-006) y en ese lapso el borrado de cuenta NO FUNCIONO
  // NUNCA.
  //
  // MEDIDO, no deducido. Cloud Logging de treino-dev, todo el historico
  // retenido (desde 2026-05-01):
  //
  //   service_name="deleteaccount" AND httpRequest.status=200  ->  0 entradas
  //
  // Los unicos tres intentos autenticados que existen fueron rechazados:
  //
  //   2026-08-11T13:12:37Z  401  {"verifications":{"auth":"VALID","app":"INVALID"}}
  //   2026-08-11T13:12:51Z  401  "AppCheck token was rejected."
  //   2026-08-11T13:13:05Z  401  Decoding App Check token failed
  //
  // Tres toques en 28 segundos: alguien apreto ELIMINAR, no paso nada y
  // reintento. El handler de abajo nunca corrio — App Check corta en la capa
  // de transporte, antes.
  //
  // POR QUE SE SACA: Apple Guideline 5.1.1(v) exige que el borrado de cuenta
  // funcione, y una parte real de los clientes no puede atestar hoy. Contado
  // sobre los logs de mintWatchCredential, que recibe trafico real y no tiene
  // el flag: iPhone fisico 8 VALID / 2 INVALID, Android 1 VALID / 8 INVALID
  // (ultimo rechazo 2026-08-24). Cualquiera de esos clientes come 401 aca.
  //
  // Mismo criterio que el PR #704 aplico a acceptTrainerLink/resumeTrainerLink:
  // un flag que convierte un boton en un error permanente no da seguridad, da
  // un boton roto.
  //
  // LO QUE SIGUE PROTEGIENDO, y es lo que importa: `request.auth` es
  // obligatorio, y el guard anti-spoofing de abajo exige
  // `callerUid === data.uid`. O sea que un llamador solo puede borrar SU
  // propia cuenta. App Check era defensa en profundidad contra abuso
  // automatizado, no la cerradura — y con el enforcement por API en UNENFORCED
  // (firestore e identitytoolkit, re-verificado 2026-08-25) no estaba cerrando
  // una puerta que estuviera cerrada en otro lado.
  //
  // PARA RESTAURARLO: volver a `enforceAppCheck: true` cuando el cliente emita
  // atestacion valida en las DOS plataformas. No hace falta instrumentar nada:
  // firebase-functions v2 ya loguea la verificacion de cada llamada. Contar
  // sobre `jsonPayload.verifications.app` filtrando por
  // `jsonPayload.message:"Callable request verification"` y pedir cero INVALID
  // por plataforma. Hasta entonces esto es deuda, no decision de diseno, y
  // figura como tal en el registry de appcheck-enforcement.test.ts.
  { region: "southamerica-east1", secrets: [MP_ACCESS_TOKEN] },
  async (request): Promise<DeleteAccountResponse> => {
    // ── Guard: caller must be authenticated ─────────────────────────────────
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Caller is not authenticated.");
    }

    const callerUid = request.auth.uid;
    const data = request.data as DeleteAccountRequest;

    // ── Guard: anti-spoofing (REQ-ACCDEL-CF-002, ADR-ACCDEL-014) ───────────
    if (callerUid !== data.uid) {
      throw new HttpsError("permission-denied", "uid mismatch");
    }

    // ── Resolve sign-in provider from auth token ────────────────────────────
    // DecodedIdToken.firebase.sign_in_provider is present on real tokens.
    // In test contexts the field may be absent — fall back to "unknown".
    const tokenFirebase = request.auth.token.firebase as
      | { sign_in_provider?: string }
      | undefined;
    const provider = tokenFirebase?.sign_in_provider ?? "unknown";

    const app = ensureApp();
    return runDeleteAccount(app, data.uid, provider);
  }
);
