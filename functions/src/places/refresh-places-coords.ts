/**
 * refreshPlacesCoords — refresco diario de las coordenadas de Google Places
 * (#1338, design sdd/places-compliance/design).
 *
 * Los términos de Places permiten guardar `place_id` para siempre pero las
 * coordenadas (`location`) solo hasta 30 días. La app guarda `place_id` +
 * `coordsFetchedAt`, y este job vuelve a pedir `location` (y SOLO eso: la field
 * mask es `location`, el SKU barato) antes de que se cumplan los 30 días.
 *
 * Qué refresca:
 *  - `gyms/{placeId}` con `coordsFetchedAt <= hoy-25d` (source google-places).
 *  - `users/{uid}` con `trainerLocationsCoordsFetchedAt <= hoy-25d`: ese campo
 *    de primer nivel es el mínimo de `coordsFetchedAt` entre sus lugares con
 *    `placeId` (Firestore no filtra dentro de un array de maps). Consultas con
 *    índices automáticos de un solo campo: no hace falta ningún índice nuevo.
 *
 * Qué NO hace:
 *  - No borra datos del usuario (nombre, etiqueta, `placeId`). Un lugar que
 *    Google ya no reconoce (NOT_FOUND) se marca; pasados 30 días se le BORRAN
 *    las coordenadas (`lat`, `lng`, `geohash` quedan en `null`: no se puede
 *    seguir cacheándolas) y sale de la búsqueda (gym: sin geohash; lugar de PF:
 *    `stale:true` y afuera de `trainerGeohashes` y del espejo público). La app
 *    le pide al PF que lo vuelva a elegir.
 *  - Lo purgado por un fallo TRANSITORIO (key revocada, cuota, caída) sigue en
 *    la cola: gym con `coordsFetchedAt = 1970`, lugar de PF `stale` con su
 *    `coordsFetchedAt` viejo. Cuando Places vuelve a responder `ok` se
 *    restauran coordenadas, geohash y (con consentimiento) el espejo público.
 *    Lo purgado por NOT_FOUND sale de la cola (`coordsFetchedAt: null`).
 *  - No reintenta en línea: 429/5xx/red => se salta y queda para mañana (hay 5
 *    días de colchón entre los 25 y los 30).
 *  - No pisa ediciones concurrentes: gyms con precondición `lastUpdateTime`,
 *    usuarios dentro de una transacción.
 *
 * El espejo a `trainerPublicProfiles` solo existe si el PF dio consentimiento de
 * ubicación (`trainerLocationConsentAt != null`) y el doc público ya existe: es
 * la misma compuerta que aplica el cliente en user_repository.dart.
 *
 * Cumplimiento (30 días): si un lugar tiene `coordsFetchedAt` de hace MÁS de 30
 * días y el refresco NO dio `ok` (NOT_FOUND, 403 por key revocada, 429, caída),
 * igual se lo saca de la búsqueda. La purga es por EDAD, no por tipo de error:
 * si no, un fallo transitorio largo dejaría coordenadas publicadas fuera de plazo.
 * Si hubo consultas y NINGUNA salió `ok`, se loguea a nivel error (alerta).
 *
 * Equidad: la cola es `orderBy asc + limit`, así que los docs que no se pueden
 * resolver se quedarían al frente para siempre. Por eso se les anota un
 * postergamiento en `placesRefreshBackoff/{gym|user}_{id}` (colección solo de
 * servidor: sin reglas = denegado a clientes, y no toca los docs de usuario) y
 * se pagina saltándolos. El postergamiento nunca pasa del día 28, así que lo
 * cercano al vencimiento vuelve a ser elegible a tiempo. Cada fase (gyms, luego
 * usuarios) tiene su propio presupuesto de tiempo (la mitad; lo que sobra pasa
 * a la siguiente), hay un tope de consultas distintas a Places por corrida y
 * una concurrencia global (los placeIds de un mismo entrenador no la exceden).
 *
 * Migración: un doc SIN `coordsFetchedAt` (gym) o sin
 * `trainerLocationsCoordsFetchedAt` (usuario) es INVISIBLE para este job hasta
 * que la migración lo rellene (con 1970-01-01 si no se sabe la edad: ese valor
 * sí entra, cae en el borde y se refresca o se purga en la primera corrida).
 *
 * La llamada HTTP es inyectable (`fetchLocation`) para testear sin red.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import {
  DocumentData,
  DocumentSnapshot,
  Firestore,
  Query,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { geohash5 } from "./geohash";

/** Secret Manager `PLACES_API_KEY` (ya existe en treino-dev). Nunca se loguea. */
const PLACES_API_KEY = defineSecret("PLACES_API_KEY");

const DAY_MS = 24 * 60 * 60 * 1000;
/** Se refresca al pasar este umbral... */
const REFRESH_AFTER_DAYS = 25;
/** ...y a los 30 Google deja de permitir servir las coordenadas. */
const MAX_CACHE_DAYS = 30;

const DEFAULT_LIMIT = 300;
const DEFAULT_CONCURRENCY = 4;
/** El timeout de la función es 540 s: cortamos antes para no morir a medias. */
const DEFAULT_DEADLINE_MS = 480_000;
/** Tope de consultas DISTINTAS a Places por corrida (costo y cuota acotados). */
const DEFAULT_MAX_PLACE_FETCHES = 1000;
/** Páginas máximas al buscar candidatos elegibles saltando los postergados. */
const MAX_PAGES = 5;
/** Un postergamiento nunca pasa de aquí: queda margen para reintentar y purgar. */
const MAX_BACKOFF_UNTIL_DAYS = 28;
const TRANSIENT_BACKOFF_MS = 36 * 60 * 60 * 1000;
const NOT_FOUND_BACKOFF_MS = 3 * DAY_MS;
const BACKOFF_COLLECTION = "placesRefreshBackoff";

export type PlaceLookup =
  | { status: "ok"; lat: number; lng: number }
  | { status: "not_found" }
  | { status: "transient" };

export type FetchLocation = (placeId: string) => Promise<PlaceLookup>;

export interface RefreshOptions {
  now: Date;
  fetchLocation: FetchLocation;
  /** Tope por colección (gyms, users). */
  limit?: number;
  concurrency?: number;
  /** Ms de reloj real tras los cuales no se arranca trabajo nuevo. */
  deadlineMs?: number;
  /** Tope de consultas distintas a Places en la corrida. */
  maxPlaceFetches?: number;
}

export interface RefreshResult {
  gymsRefreshed: number;
  gymsNotFound: number;
  gymsSkipped: number;
  usersUpdated: number;
  usersSkipped: number;
  /** Gyms / usuarios sacados de la búsqueda por pasar de 30 días sin refrescar. */
  gymsPurged: number;
  usersPurged: number;
  placesFetched: number;
  placesOk: number;
  deadlineHit: boolean;
  fetchCapHit: boolean;
}

// ---------------------------------------------------------------------------
// HTTP: Place Details (New), field mask `location` únicamente.
// ---------------------------------------------------------------------------

type FetchImpl = (url: string, init: RequestInit) => Promise<Response>;

/**
 * GET places/{id} con `X-Goog-FieldMask: location`. Nunca tira: cualquier cosa
 * que no sea una respuesta clara de Google es `transient`. El mensaje de error
 * nunca incluye la key.
 *
 * 400 es ambiguo (place id inválido vs key inválida): solo es `not_found` si el
 * mensaje habla del place id y no hay un motivo `API_KEY_*`. Una key rota no
 * puede marcar todo el catálogo como inexistente.
 */
export function fetchPlaceLocation(
  apiKey: string,
  fetchImpl: FetchImpl = (u, i) => fetch(u, i),
): FetchLocation {
  return async (placeId) => {
    try {
      const res = await fetchImpl(
        `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`,
        {
          method: "GET",
          headers: {
            "X-Goog-Api-Key": apiKey,
            "X-Goog-FieldMask": "location",
          },
          signal: AbortSignal.timeout(10_000),
        },
      );
      const body = (await res.json().catch(() => ({}))) as {
        location?: { latitude?: unknown; longitude?: unknown };
        error?: {
          status?: string;
          message?: string;
          details?: Array<{ reason?: string }>;
        };
      };
      if (res.status >= 200 && res.status < 300) {
        const lat = body.location?.latitude;
        const lng = body.location?.longitude;
        if (typeof lat === "number" && typeof lng === "number") {
          return { status: "ok", lat, lng };
        }
        return { status: "transient" };
      }
      if (res.status === 404 || body.error?.status === "NOT_FOUND") {
        return { status: "not_found" };
      }
      if (res.status === 400) {
        const keyProblem = (body.error?.details ?? []).some((d) =>
          (d.reason ?? "").startsWith("API_KEY"),
        );
        if (!keyProblem && /place[ _]?id/i.test(body.error?.message ?? "")) {
          return { status: "not_found" };
        }
      }
      return { status: "transient" };
    } catch {
      return { status: "transient" };
    }
  };
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

/** Semáforo con traspaso de cupo: nunca hay más de `max` tareas activas. */
class Semaphore {
  private active = 0;
  private waiters: Array<() => void> = [];
  constructor(private readonly max: number) {}

  async run<T>(fn: () => Promise<T>): Promise<T> {
    if (this.active < this.max) this.active++;
    else await new Promise<void>((resolve) => this.waiters.push(resolve));
    try {
      return await fn();
    } finally {
      const next = this.waiters.shift();
      if (next) next();
      else this.active--;
    }
  }
}

interface Ctx {
  db: Firestore;
  now: Date;
  nowTs: Timestamp;
  cutoff: Timestamp;
  fetchLocation: FetchLocation;
  cache: Map<string, Promise<PlaceLookup>>;
  result: RefreshResult;
  maxFetches: number;
  gate: Semaphore;
  /** Claves de backoff que ya existían al elegir candidatos (para limpiarlas). */
  hadBackoff: Set<string>;
}

/** Una consulta por placeId en toda la corrida (gyms y entrenadores). */
function lookup(ctx: Ctx, placeId: string): Promise<PlaceLookup> {
  let p = ctx.cache.get(placeId);
  if (!p) {
    if (ctx.result.placesFetched >= ctx.maxFetches) {
      // Sobre el tope: no se consulta. Cuenta como transitorio (y la purga por
      // edad igual aplica a lo que ya venció).
      ctx.result.fetchCapHit = true;
      return Promise.resolve({ status: "transient" });
    }
    ctx.result.placesFetched++;
    p = ctx.gate
      .run(() => ctx.fetchLocation(placeId))
      .catch((): PlaceLookup => ({ status: "transient" }))
      .then((r) => {
        if (r.status === "ok") ctx.result.placesOk++;
        return r;
      });
    ctx.cache.set(placeId, p);
  }
  return p;
}

function backoffKey(kind: "gym" | "user", id: string): string {
  return `${kind}_${id}`;
}

/**
 * Posterga el reintento de un doc que no se pudo resolver. Tope: día 28 desde
 * `fetchedAt`, para que lo que se acerca al vencimiento siga siendo elegible.
 * Mejor esfuerzo: un fallo acá no frena el ítem.
 */
async function postpone(
  ctx: Ctx,
  kind: "gym" | "user",
  id: string,
  fetchedAt: unknown,
  backoffMs: number,
): Promise<void> {
  // Pasados los 30 días el ítem ya está purgado y solo espera una recuperación:
  // no hay vencimiento que cuidar, así que el postergamiento no lleva tope (si
  // lo llevara, los purgados quedarían al frente de la cola para siempre).
  const until = olderThanMaxCache(ctx, fetchedAt)
    ? ctx.now.getTime() + backoffMs
    : Math.min(
      ctx.now.getTime() + backoffMs,
      asTimestamp(fetchedAt).toMillis() + MAX_BACKOFF_UNTIL_DAYS * DAY_MS,
    );
  if (until <= ctx.now.getTime()) return; // ya urge: sin postergar
  try {
    await ctx.db
      .collection(BACKOFF_COLLECTION)
      .doc(backoffKey(kind, id))
      .set({ nextAttemptAt: Timestamp.fromMillis(until), kind });
  } catch (e) {
    logger.warn("refreshPlacesCoords: no se pudo postergar un ítem", {
      error: e instanceof Error ? e.message : String(e),
    });
  }
}

async function clearBackoff(ctx: Ctx, kind: "gym" | "user", id: string) {
  const key = backoffKey(kind, id);
  if (!ctx.hadBackoff.has(key)) return;
  try {
    await ctx.db.collection(BACKOFF_COLLECTION).doc(key).delete();
  } catch {
    // inofensivo: ya vencido, no se vuelve a mirar
  }
}

/**
 * Candidatos vencidos, del más viejo al más nuevo, saltando los postergados.
 * Pagina con cursor hasta juntar `limit` elegibles (o `MAX_PAGES`).
 */
async function collectEligible(
  ctx: Ctx,
  base: Query,
  kind: "gym" | "user",
  limit: number,
): Promise<DocumentSnapshot[]> {
  const out: DocumentSnapshot[] = [];
  let last: DocumentSnapshot | undefined;
  for (let page = 0; page < MAX_PAGES && out.length < limit; page++) {
    const snap = await (last ? base.startAfter(last) : base).limit(limit).get();
    if (snap.empty) break;
    const states = await ctx.db.getAll(
      ...snap.docs.map((d) =>
        ctx.db.collection(BACKOFF_COLLECTION).doc(backoffKey(kind, d.id)),
      ),
    );
    snap.docs.forEach((d, i) => {
      const next = states[i].exists ? states[i].get("nextAttemptAt") : null;
      if (states[i].exists) ctx.hadBackoff.add(backoffKey(kind, d.id));
      if (next instanceof Timestamp && next.toMillis() > ctx.now.getTime()) {
        return;
      }
      if (out.length < limit) out.push(d);
    });
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < limit) break;
  }
  return out;
}

const EPOCH = Timestamp.fromMillis(0);

function asTimestamp(v: unknown): Timestamp {
  return v instanceof Timestamp ? v : EPOCH;
}

function olderThanMaxCache(ctx: Ctx, fetchedAt: unknown): boolean {
  return (
    ctx.now.getTime() - asTimestamp(fetchedAt).toMillis() > MAX_CACHE_DAYS * DAY_MS
  );
}

function isDue(ctx: Ctx, fetchedAt: unknown): boolean {
  return asTimestamp(fetchedAt).toMillis() <= ctx.cutoff.toMillis();
}

function isFailedPrecondition(e: unknown): boolean {
  const code = (e as { code?: unknown })?.code;
  return code === 9 || code === "failed-precondition" || code === 5;
}

async function processGym(ctx: Ctx, snap: DocumentSnapshot): Promise<void> {
  const data = snap.data() as DocumentData;
  // Solo los gyms que vienen de Places tienen un place_id como id.
  if (data.source !== "google-places") {
    ctx.result.gymsSkipped++;
    return;
  }
  const r = await lookup(ctx, snap.id);
  try {
    if (r.status === "ok") {
      await snap.ref.update(
        {
          lat: r.lat,
          lng: r.lng,
          geohash: geohash5(r.lat, r.lng),
          coordsFetchedAt: ctx.nowTs,
          placeStatus: "ok",
        },
        { lastUpdateTime: snap.updateTime! },
      );
      ctx.result.gymsRefreshed++;
      await clearBackoff(ctx, "gym", snap.id);
      return;
    }
    // No ok. Pasados 30 días no se pueden seguir cacheando las coordenadas,
    // sea cual sea el motivo: se BORRAN (no solo se esconden) y el gym sale de
    // la búsqueda.
    if (olderThanMaxCache(ctx, data.coordsFetchedAt)) {
      const notFound = r.status === "not_found";
      const yaPurgado = data.lat == null && data.lng == null;
      if (notFound || !yaPurgado) {
        await snap.ref.update(
          {
            ...(notFound ? { placeStatus: "not_found" } : {}),
            lat: null,
            lng: null,
            geohash: null,
            // not_found sale de la cola. Un fallo transitorio la conserva
            // (1970 también es lo que usa la migración): cuando Places vuelva,
            // el próximo `ok` restaura las coordenadas.
            coordsFetchedAt: notFound ? null : EPOCH,
          },
          { lastUpdateTime: snap.updateTime! },
        );
        if (!yaPurgado) ctx.result.gymsPurged++;
      }
      if (notFound) {
        ctx.result.gymsNotFound++;
        await clearBackoff(ctx, "gym", snap.id);
      } else {
        ctx.result.gymsSkipped++;
        await postpone(ctx, "gym", snap.id, EPOCH, TRANSIENT_BACKOFF_MS);
      }
      return;
    }
    if (r.status === "not_found") {
      if (data.placeStatus !== "not_found") {
        await snap.ref.update(
          { placeStatus: "not_found" },
          { lastUpdateTime: snap.updateTime! },
        );
      }
      ctx.result.gymsNotFound++;
      await postpone(ctx, "gym", snap.id, data.coordsFetchedAt, NOT_FOUND_BACKOFF_MS);
    } else {
      ctx.result.gymsSkipped++;
      await postpone(ctx, "gym", snap.id, data.coordsFetchedAt, TRANSIENT_BACKOFF_MS);
    }
  } catch (e) {
    if (!isFailedPrecondition(e)) throw e;
    // Alguien editó el gym mientras esperábamos a Google: mañana se reintenta.
    ctx.result.gymsSkipped++;
  }
}

type Loc = Record<string, unknown>;

/**
 * ¿El job debe (re)consultar este lugar? Tiene `placeId` y, si está `stale`,
 * conserva un `coordsFetchedAt` (purga por fallo transitorio: reintentable).
 * Un stale sin fecha es NOT_FOUND o dato viejo: no se consulta.
 */
function isRetryable(l: Loc): boolean {
  if (typeof l.placeId !== "string" || l.placeId === "") return false;
  return l.stale !== true || l.coordsFetchedAt instanceof Timestamp;
}

function minCoordsFetchedAt(locs: Loc[]): Timestamp | null {
  let min: Timestamp | null = null;
  for (const l of locs) {
    if (!isRetryable(l)) continue;
    const t = asTimestamp(l.coordsFetchedAt);
    if (min === null || t.toMillis() < min.toMillis()) min = t;
  }
  return min;
}

async function processTrainer(ctx: Ctx, uid: string): Promise<void> {
  const userRef = ctx.db.collection("users").doc(uid);
  const pubRef = ctx.db.collection("trainerPublicProfiles").doc(uid);

  const first = (await userRef.get()).data();
  const firstLocs = (first?.trainerLocations ?? []) as Loc[];
  const dueIds = [
    ...new Set(
      firstLocs
        .filter((l) => isRetryable(l) && isDue(ctx, l.coordsFetchedAt))
        .map((l) => l.placeId as string),
    ),
  ];
  const results = new Map<string, PlaceLookup>();
  await Promise.all(
    dueIds.map(async (id) => results.set(id, await lookup(ctx, id))),
  );

  let wrote = false;
  let purged = false;
  let minAfter: Timestamp | null = null;
  await ctx.db.runTransaction(async (tx) => {
    wrote = false;
    purged = false;
    minAfter = null;
    const uSnap = await tx.get(userRef);
    const data = uSnap.data();
    if (!data) return;
    const locs = (data.trainerLocations ?? []) as Loc[];
    const consent = data.trainerLocationConsentAt != null;
    const pSnap = consent ? await tx.get(pubRef) : null;

    let changed = false;
    const next = locs.map((l): Loc => {
      if (!isRetryable(l)) return l;
      // Re-chequeo contra el doc fresco: el PF pudo volver a elegir el lugar.
      if (!isDue(ctx, l.coordsFetchedAt)) return l;
      const r = results.get(l.placeId as string);
      if (!r) return l;
      if (r.status === "ok") {
        // También restaura un lugar purgado por un fallo transitorio.
        changed = true;
        return {
          ...l,
          lat: r.lat,
          lng: r.lng,
          geohash: geohash5(r.lat, r.lng),
          coordsFetchedAt: ctx.nowTs,
          stale: null,
        };
      }
      if (l.stale === true) {
        // Ya purgado. Si Google ahora dice NOT_FOUND se deja de reintentar;
        // si sigue fallando, no hay nada que escribir.
        if (r.status !== "not_found") return l;
        changed = true;
        return { ...l, coordsFetchedAt: null };
      }
      // No ok y pasado de 30 días: se retira, sea cual sea el motivo del fallo.
      // Se borran las coordenadas (no se pueden cachear más) y se marca `stale`.
      if (olderThanMaxCache(ctx, l.coordsFetchedAt)) {
        changed = true;
        purged = true;
        return {
          ...l,
          lat: null,
          lng: null,
          geohash: null,
          stale: true,
          // not_found sale de la cola; un fallo transitorio conserva la fecha
          // vieja para que el usuario siga siendo candidato.
          coordsFetchedAt: r.status === "not_found" ? null : l.coordsFetchedAt,
        };
      }
      return l;
    });

    const min = minCoordsFetchedAt(next);
    minAfter = min;
    const storedMin = data.trainerLocationsCoordsFetchedAt as unknown;
    const minChanged =
      (min === null) !== (storedMin == null) ||
      (min !== null && storedMin instanceof Timestamp && !min.isEqual(storedMin));
    if (!changed && !minChanged) return;

    const geohashes = [
      ...new Set(
        next
          .filter((l) => l.stale !== true)
          .map((l) => l.geohash)
          .filter((g): g is string => typeof g === "string"),
      ),
    ];
    tx.update(userRef, {
      trainerLocations: next,
      trainerGeohashes: geohashes,
      trainerLocationsCoordsFetchedAt: min,
    });
    if (pSnap?.exists) {
      // Lo vencido no se publica: el espejo público lleva solo lugares vigentes.
      tx.update(pubRef, {
        trainerLocations: next.filter(
          (l) => l.stale !== true && l.lat != null && l.lng != null,
        ),
        trainerGeohashes: geohashes,
      });
    }
    wrote = true;
  });

  if (wrote) ctx.result.usersUpdated++;
  if (purged) ctx.result.usersPurged++;
  const unresolved = [...results.values()].some((r) => r.status !== "ok");
  if (!wrote && [...results.values()].some((r) => r.status === "transient")) {
    ctx.result.usersSkipped++;
  }
  if (unresolved && (minAfter as Timestamp | null) !== null && isDue(ctx, minAfter as unknown)) {
    await postpone(ctx, "user", uid, minAfter as unknown, TRANSIENT_BACKOFF_MS);
  } else if (!unresolved || (minAfter as Timestamp | null) === null) {
    await clearBackoff(ctx, "user", uid);
  }
}

async function forEachLimited<T>(
  items: T[],
  concurrency: number,
  deadlineAt: number,
  result: RefreshResult,
  fn: (item: T) => Promise<void>,
): Promise<void> {
  let i = 0;
  const worker = async () => {
    while (i < items.length) {
      if (Date.now() >= deadlineAt) {
        result.deadlineHit = true;
        return;
      }
      const item = items[i++];
      try {
        await fn(item);
      } catch (e) {
        // Un doc roto no puede frenar al resto del lote.
        logger.error("refreshPlacesCoords: falló un ítem", {
          error: e instanceof Error ? e.message : String(e),
        });
      }
    }
  };
  await Promise.all(
    Array.from({ length: Math.max(1, concurrency) }, () => worker()),
  );
}

export async function refreshPlacesCoordsHandler(
  app: App,
  opts: RefreshOptions,
): Promise<RefreshResult> {
  const db = getFirestore(app);
  const result: RefreshResult = {
    gymsRefreshed: 0,
    gymsNotFound: 0,
    gymsSkipped: 0,
    usersUpdated: 0,
    usersSkipped: 0,
    gymsPurged: 0,
    usersPurged: 0,
    placesFetched: 0,
    placesOk: 0,
    deadlineHit: false,
    fetchCapHit: false,
  };
  const limit = opts.limit ?? DEFAULT_LIMIT;
  const concurrency = Math.max(1, opts.concurrency ?? DEFAULT_CONCURRENCY);
  const ctx: Ctx = {
    db,
    now: opts.now,
    nowTs: Timestamp.fromDate(opts.now),
    cutoff: Timestamp.fromMillis(opts.now.getTime() - REFRESH_AFTER_DAYS * DAY_MS),
    fetchLocation: opts.fetchLocation,
    cache: new Map(),
    result,
    maxFetches: opts.maxPlaceFetches ?? DEFAULT_MAX_PLACE_FETCHES,
    gate: new Semaphore(concurrency),
    hadBackoff: new Set(),
  };
  const startedAt = Date.now();
  const totalMs = opts.deadlineMs ?? DEFAULT_DEADLINE_MS;
  // Presupuesto por fase: los gyms usan hasta la mitad; lo que no usen pasa a
  // los usuarios (que tienen hasta el final). Así los gyms no los dejan sin tiempo.
  const gymDeadlineAt = startedAt + totalMs / 2;
  const userDeadlineAt = startedAt + totalMs;

  const gyms = await collectEligible(
    ctx,
    db
      .collection("gyms")
      .where("coordsFetchedAt", "<=", ctx.cutoff)
      .orderBy("coordsFetchedAt", "asc"),
    "gym",
    limit,
  );
  await forEachLimited(gyms, concurrency, gymDeadlineAt, result, (d) =>
    processGym(ctx, d),
  );

  const users = await collectEligible(
    ctx,
    db
      .collection("users")
      .where("trainerLocationsCoordsFetchedAt", "<=", ctx.cutoff)
      .orderBy("trainerLocationsCoordsFetchedAt", "asc"),
    "user",
    limit,
  );
  await forEachLimited(users, concurrency, userDeadlineAt, result, (d) =>
    processTrainer(ctx, d.id),
  );

  if (result.placesFetched > 0 && result.placesOk === 0) {
    // Ni una consulta salió ok: key revocada, cuota o caída. Las coordenadas
    // seguirán venciendo; esto tiene que verse en las alertas.
    logger.error("refreshPlacesCoords: ninguna consulta a Places resultó ok", {
      placesFetched: result.placesFetched,
    });
  }
  return result;
}

// ---------------------------------------------------------------------------
// onSchedule wrapper
// ---------------------------------------------------------------------------

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

export const refreshPlacesCoords = onSchedule(
  {
    // 05:30 ART: libre entre `sweepInactiveAccounts` (05:00, que puede borrar
    // cuentas) y `retryPartialDeletions` (06:00); así no corren juntos.
    schedule: "30 5 * * *",
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
    // Explícitos: el default de 60 s mató a otro job con lotes (#1355).
    timeoutSeconds: 540,
    memory: "256MiB",
    secrets: [PLACES_API_KEY],
  },
  async () => {
    const r = await refreshPlacesCoordsHandler(ensureApp(), {
      now: new Date(),
      fetchLocation: fetchPlaceLocation(PLACES_API_KEY.value()),
    });
    logger.info("refreshPlacesCoords: corrida diaria", r);
  },
);
