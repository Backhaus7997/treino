/**
 * custom-exercise-video-quota.ts — el escritor de
 * `users/{uid}.customExerciseVideoUsage`, y la red reactiva del tope de videos.
 *
 * ─── Por que existe este campo ──────────────────────────────────────────────
 *
 * `storage.rules` tiene que saber CUANTOS videos tiene ya un usuario para poder
 * rebotarle el cuarto. Y no puede: las reglas de Storage no tienen agregacion
 * —no listan ni cuentan objetos de un prefijo— igual que las de Firestore no
 * pueden contar documentos de una coleccion (lo mismo que ya bloquea el tope de
 * `kFreeMaxOwnRoutines`).
 *
 * De ahi el contador denormalizado: esta CF cuenta contra el bucket y deja el
 * numero donde la regla lo alcanza con un `firestore.get()`. Es EXACTAMENTE el
 * mismo patron —y por el mismo motivo— que `athletePaywallEnforced` en
 * `athlete-paywall-enforced.ts`: lo que la regla no puede resolver, lo resuelve
 * una CF y la regla lee la conclusion.
 *
 * El campo es CF-write-only: lo pinea `firestore.rules` en el create y en el
 * update de `users/{uid}`. Sin ese pin el alumno se escribe `{count: 0}` y el
 * tope entero es decorativo — el mismo bypass de una sola escritura que el pin
 * de `athletePaywallEnforced` documenta.
 *
 * ─── Por que ademas BORRA, y por que la regla no alcanza sola ───────────────
 *
 * El contador va ATRASADO por construccion: este trigger corre DESPUES de que
 * el objeto aterrizo en el bucket. Un cliente que dispare N subidas en paralelo
 * las evalua todas contra el mismo valor viejo y se pasa del tope por el tamano
 * de la rafaga. La regla no puede cerrar esa ventana —no hay contador fresco
 * que leer— asi que la cierra esta funcion borrando el excedente.
 *
 * El reparto de trabajo entre las dos capas es el punto, y ninguna sirve sola:
 *
 *   • La REGLA es preventiva. Atrapa el caso normal (subida secuencial, que es
 *     lo que hace el editor) ANTES de que los bytes entren, que es la unica
 *     forma de no pagarlos.
 *   • Esta CF es reactiva. Solo ve el objeto cuando ya esta guardado, asi que
 *     como gate unico llegaria tarde siempre — pero es la unica que puede
 *     limpiar lo que se colo por la carrera.
 *
 * ─── Por que RECUENTA en vez de incrementar ────────────────────────────────
 *
 * La entrega de Eventarc es at-least-once. Un `FieldValue.increment()` se
 * aplicaria dos veces en una redelivery y dejaria el contador desviado PARA
 * SIEMPRE — y un contador de cuota desviado hacia abajo es un tope que no
 * existe. Recontar el prefijo y escribir el valor absoluto es idempotente.
 * Mismo criterio y mismo motivo que `maintainReactionCounters`
 * (W-SOCIAL-COUNTERS-01).
 *
 * ─── Guarda anti-loop ──────────────────────────────────────────────────────
 *
 * Esta CF escribe en `users/{uid}`, que es el documento que disparan
 * `syncEntitlementsOnSubscription` y el trigger de `athletePaywallEnforced`.
 * Ninguno de los dos se despierta: el primero compara solo `subscription` y el
 * segundo solo `athleteSubscription` + `role`, y esta escritura no toca ninguno
 * de los tres. Si algun dia se le agrega un campo a este mapa, verifica que
 * siga sin pisar las entradas de esos dos triggers o el bucle factura sin parar.
 *
 * El otro ciclo posible es propio: borrar un objeto dispara `onObjectDeleted`,
 * que vuelve a reconciliar. Termina en una vuelta — la segunda pasada ya esta
 * dentro del tope, no borra nada, y el guard de "escribi solo si cambio" no
 * escribe. Dos redes, igual que en `athlete-paywall-enforced.ts`.
 *
 * Region southamerica-east1 per ADR-PN-005. El bucket vive en la misma region
 * (`docs/roadmap.md`, Fase 1 Etapa 6) — un trigger de Storage DEBE estar donde
 * esta el bucket o el deploy falla.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions";
import {
  onObjectDeleted,
  onObjectFinalized,
} from "firebase-functions/v2/storage";

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/** El prefijo que gobierna esta funcion. */
export const VIDEO_PREFIX = "customExerciseVideos/";

/** El campo que escribe este modulo, y nadie mas. */
export const USAGE_FIELD = "customExerciseVideoUsage";

/**
 * Los cuatro topes. DEBEN espejar `athlete_entitlement.dart`
 * (`kFreeMaxCustomExerciseVideos`, `kFreeMaxCustomExerciseVideoBytes`,
 * `kMaxCustomExerciseVideos`, `kMaxCustomExerciseVideoBytes`) y los literales
 * de `storage.rules`. Los tres se mantienen a mano y no hay nada que los
 * sincronice.
 *
 * Si esta copia fuera MAS PERMISIVA que la regla, la CF no borraria lo que la
 * regla ya reboto y no pasaria nada. Si fuera MAS ESTRICTA, borraria videos que
 * la regla acepto — el usuario ve la subida exitosa y el archivo desaparece
 * solo. Ese es el modo de falla caro, y es mudo.
 */
export const FREE_MAX_VIDEOS = 3;
export const FREE_MAX_VIDEO_BYTES = 25 * 1024 * 1024;
export const MAX_VIDEOS = 50;
export const MAX_VIDEO_BYTES = 100 * 1024 * 1024;

export interface VideoCaps {
  maxCount: number;
  maxBytes: number;
}

/**
 * Los topes que le corresponden a un usuario.
 *
 * `enforced` sale de `users/{uid}.athletePaywallEnforced`, que ya cruza
 * suscripcion, vinculo activo Y ROL — `resolveAthletePaywallEnforced` corta en
 * `if (userData?.role !== "athlete") return false`, asi que un PF nunca cae en
 * el tope free. Eso importa porque el editor de ejercicios custom es superficie
 * COMPARTIDA entre el alumno y el PF.
 */
export function capsFor(enforced: boolean): VideoCaps {
  return enforced
    ? { maxCount: FREE_MAX_VIDEOS, maxBytes: FREE_MAX_VIDEO_BYTES }
    : { maxCount: MAX_VIDEOS, maxBytes: MAX_VIDEO_BYTES };
}

/**
 * El uid dueno de un objeto, o null si el path no es de este prefijo.
 *
 * El match de la regla es `{userId}/{file=**}`, o sea que el video puede estar
 * anidado a cualquier profundidad. Solo importa el segmento que sigue al
 * prefijo, y tiene que haber ALGO despues de el: `customExerciseVideos/uid/`
 * a secas es el marcador de carpeta que crea la consola, no un video.
 */
export function uidFromObjectName(name: string | undefined): string | null {
  if (!name || !name.startsWith(VIDEO_PREFIX)) return null;
  const rest = name.slice(VIDEO_PREFIX.length);
  const slash = rest.indexOf("/");
  if (slash <= 0 || slash === rest.length - 1) return null;
  return rest.slice(0, slash);
}

export interface StoredVideo {
  name: string;
  size: number;
  createdAt: number;
}

export interface QuotaDecision {
  keep: StoredVideo[];
  remove: StoredVideo[];
}

/**
 * Que se conserva y que sobra, dados los topes.
 *
 * Pura y exportada para poder testear la decision sin emulador ni bucket.
 *
 * **Se conservan los MAS VIEJOS.** Los viejos son los que los documentos
 * `customExercises` del usuario ya referencian por `videoUrl`; los nuevos son
 * los que se colaron por la carrera. Borrar por el otro lado le romperia los
 * ejercicios que ya tenia armados para quedarse con los que nunca llego a usar.
 *
 * El filtro por TAMANO va primero y es independiente del de cantidad: un
 * archivo que excede `maxBytes` sobra aunque sea el unico que tenga.
 *
 * El corte es `>=` y no `>` para espejar exactamente la regla, que autoriza con
 * `request.resource.size < maxBytes`. Un `>` aca dejaria vivo el archivo de
 * exactamente `maxBytes` que la regla rechaza, y las dos capas discreparian en
 * el unico punto donde tienen que coincidir.
 */
export function decideQuota(
  videos: readonly StoredVideo[],
  caps: VideoCaps,
): QuotaDecision {
  const remove: StoredVideo[] = [];
  const withinSize: StoredVideo[] = [];
  for (const v of videos) {
    if (v.size >= caps.maxBytes) remove.push(v);
    else withinSize.push(v);
  }

  withinSize.sort(
    (a, b) => a.createdAt - b.createdAt || a.name.localeCompare(b.name),
  );
  return {
    keep: withinSize.slice(0, caps.maxCount),
    remove: [...remove, ...withinSize.slice(caps.maxCount)],
  };
}

export interface ReconcileResult {
  uid: string;
  count: number;
  bytes: number;
  removed: string[];
  changed: boolean;
}

/**
 * Recuenta el prefijo de UN usuario, borra el excedente y deja el contador al
 * dia. Escribe solo si el valor cambia — segunda red contra el bucle, y lo que
 * hace barata la redelivery.
 */
export async function reconcileVideoQuota(
  app: App,
  uid: string,
): Promise<ReconcileResult> {
  const db = getFirestore(app);
  const userRef = db.collection("users").doc(uid);
  const bucket = getStorage(app).bucket();

  const [snap, [files]] = await Promise.all([
    userRef.get(),
    bucket.getFiles({ prefix: `${VIDEO_PREFIX}${uid}/` }),
  ]);

  // Sin doc de perfil ⇒ no enforced, mismo default seguro que el fail-open de
  // `storage.rules` y de `paywallEnforcedFor` en `firestore.rules`. El techo
  // estructural sigue aplicando.
  const enforced = snap.exists && snap.get("athletePaywallEnforced") === true;

  const videos: StoredVideo[] = files
    .filter((f) => uidFromObjectName(f.name) === uid)
    .map((f) => ({
      name: f.name,
      size: Number(f.metadata?.size ?? 0),
      createdAt: Date.parse(String(f.metadata?.timeCreated ?? "")) || 0,
    }));

  const { keep, remove } = decideQuota(videos, capsFor(enforced));

  for (const v of remove) {
    try {
      await bucket.file(v.name).delete();
      logger.warn(
        "customExerciseVideoQuota: objeto borrado por exceder el tope",
        { uid, object: v.name, size: v.size, enforced },
      );
    } catch (e) {
      // Borrado best-effort: un objeto que ya no esta (redelivery, o borrado
      // por el usuario en el medio) no es un error. Lo que NO se hace es
      // abortar la reconciliacion — el contador tiene que quedar al dia igual.
      logger.warn("customExerciseVideoQuota: no se pudo borrar", {
        uid,
        object: v.name,
        error: String(e),
      });
    }
  }

  const usage = {
    count: keep.length,
    bytes: keep.reduce((s, v) => s + v.size, 0),
    updatedAt: Date.now(),
  };

  const prev = snap.get(USAGE_FIELD) as
    | { count?: number; bytes?: number }
    | undefined;
  // `updatedAt` se excluye de la comparacion a proposito: si entrara, cada
  // redelivery seria una escritura distinta y el guard no guardaria nada.
  const changed = prev?.count !== usage.count || prev?.bytes !== usage.bytes;

  // Sin doc de perfil no hay donde escribir, y crearlo desde aca seria acunar
  // un `users/{uid}` sin `role` ni `email` que despues nadie sabe de donde
  // salio. El contador aparece con el primer update real del perfil.
  if (changed && snap.exists) {
    await userRef.update({ [USAGE_FIELD]: usage });
  }

  return {
    uid,
    count: usage.count,
    bytes: usage.bytes,
    removed: remove.map((v) => v.name),
    changed,
  };
}

/** Handler compartido por los dos triggers. */
async function onVideoObjectEvent(
  objectName: string | undefined,
): Promise<void> {
  const uid = uidFromObjectName(objectName);
  if (uid === null) return; // otro prefijo, o el marcador de carpeta
  const r = await reconcileVideoQuota(ensureApp(), uid);
  logger.info("customExerciseVideoQuota: reconciliado", r);
}

export const maintainCustomExerciseVideoQuotaOnFinalize = onObjectFinalized(
  { region: "southamerica-east1" },
  async (event) => {
    await onVideoObjectEvent(event.data.name);
  },
);

export const maintainCustomExerciseVideoQuotaOnDelete = onObjectDeleted(
  { region: "southamerica-east1" },
  async (event) => {
    await onVideoObjectEvent(event.data.name);
  },
);
