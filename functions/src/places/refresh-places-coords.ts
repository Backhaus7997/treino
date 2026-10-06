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
 *  - No borra datos del usuario. Un lugar que Google ya no reconoce
 *    (NOT_FOUND) se marca; pasados 30 días SOLO se lo saca de la búsqueda
 *    (gym: `geohash:null`; lugar de PF: `stale:true` y afuera de
 *    `trainerGeohashes` y del espejo público) y la app le pide al PF que lo
 *    vuelva a elegir.
 *  - No reintenta en línea: 429/5xx/red => se salta y queda para mañana (hay 5
 *    días de colchón entre los 25 y los 30).
 *  - No pisa ediciones concurrentes: gyms con precondición `lastUpdateTime`,
 *    usuarios dentro de una transacción.
 *
 * El espejo a `trainerPublicProfiles` solo existe si el PF dio consentimiento de
 * ubicación (`trainerLocationConsentAt != null`) y el doc público ya existe: es
 * la misma compuerta que aplica el cliente en user_repository.dart.
 *
 * La llamada HTTP es inyectable (`fetchLocation`) para testear sin red.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import {
  DocumentData,
  DocumentSnapshot,
  Firestore,
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
}

export interface RefreshResult {
  gymsRefreshed: number;
  gymsNotFound: number;
  gymsSkipped: number;
  usersUpdated: number;
  usersSkipped: number;
  placesFetched: number;
  deadlineHit: boolean;
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

interface Ctx {
  db: Firestore;
  now: Date;
  nowTs: Timestamp;
  cutoff: Timestamp;
  fetchLocation: FetchLocation;
  cache: Map<string, Promise<PlaceLookup>>;
  result: RefreshResult;
}

/** Una consulta por placeId en toda la corrida (gyms y entrenadores). */
function lookup(ctx: Ctx, placeId: string): Promise<PlaceLookup> {
  let p = ctx.cache.get(placeId);
  if (!p) {
    ctx.result.placesFetched++;
    p = ctx.fetchLocation(placeId).catch(() => ({
      status: "transient" as const,
    }));
    ctx.cache.set(placeId, p);
  }
  return p;
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
    } else if (r.status === "not_found") {
      const purge = olderThanMaxCache(ctx, data.coordsFetchedAt);
      if (purge) {
        // Fuera de la búsqueda y de la cola; el doc y su nombre se conservan.
        await snap.ref.update(
          { placeStatus: "not_found", geohash: null, coordsFetchedAt: null },
          { lastUpdateTime: snap.updateTime! },
        );
      } else if (data.placeStatus !== "not_found") {
        await snap.ref.update(
          { placeStatus: "not_found" },
          { lastUpdateTime: snap.updateTime! },
        );
      }
      ctx.result.gymsNotFound++;
    } else {
      ctx.result.gymsSkipped++;
    }
  } catch (e) {
    if (!isFailedPrecondition(e)) throw e;
    // Alguien editó el gym mientras esperábamos a Google: mañana se reintenta.
    ctx.result.gymsSkipped++;
  }
}

type Loc = Record<string, unknown>;

function minCoordsFetchedAt(locs: Loc[]): Timestamp | null {
  let min: Timestamp | null = null;
  for (const l of locs) {
    if (!l.placeId || l.stale === true) continue;
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
        .filter(
          (l) =>
            typeof l.placeId === "string" &&
            l.stale !== true &&
            isDue(ctx, l.coordsFetchedAt),
        )
        .map((l) => l.placeId as string),
    ),
  ];
  const results = new Map<string, PlaceLookup>();
  await Promise.all(
    dueIds.map(async (id) => results.set(id, await lookup(ctx, id))),
  );

  let wrote = false;
  await ctx.db.runTransaction(async (tx) => {
    wrote = false;
    const uSnap = await tx.get(userRef);
    const data = uSnap.data();
    if (!data) return;
    const locs = (data.trainerLocations ?? []) as Loc[];
    const consent = data.trainerLocationConsentAt != null;
    const pSnap = consent ? await tx.get(pubRef) : null;

    let changed = false;
    const next = locs.map((l): Loc => {
      if (typeof l.placeId !== "string" || l.stale === true) return l;
      // Re-chequeo contra el doc fresco: el PF pudo volver a elegir el lugar.
      if (!isDue(ctx, l.coordsFetchedAt)) return l;
      const r = results.get(l.placeId);
      if (!r) return l;
      if (r.status === "ok") {
        changed = true;
        return {
          ...l,
          lat: r.lat,
          lng: r.lng,
          geohash: geohash5(r.lat, r.lng),
          coordsFetchedAt: ctx.nowTs,
        };
      }
      if (r.status === "not_found" && olderThanMaxCache(ctx, l.coordsFetchedAt)) {
        changed = true;
        return { ...l, stale: true };
      }
      return l;
    });

    const min = minCoordsFetchedAt(next);
    const storedMin = data.trainerLocationsCoordsFetchedAt as unknown;
    const minChanged =
      (min === null) !== (storedMin == null) ||
      (min !== null && storedMin instanceof Timestamp && !min.isEqual(storedMin));
    if (!changed && !minChanged) return;

    const geohashes = [
      ...new Set(next.filter((l) => l.stale !== true).map((l) => l.geohash)),
    ];
    tx.update(userRef, {
      trainerLocations: next,
      trainerGeohashes: geohashes,
      trainerLocationsCoordsFetchedAt: min,
    });
    if (pSnap?.exists) {
      // Lo vencido no se publica: el espejo público lleva solo lugares vigentes.
      tx.update(pubRef, {
        trainerLocations: next.filter((l) => l.stale !== true),
        trainerGeohashes: geohashes,
      });
    }
    wrote = true;
  });

  if (wrote) ctx.result.usersUpdated++;
  else if ([...results.values()].some((r) => r.status === "transient")) {
    ctx.result.usersSkipped++;
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
    placesFetched: 0,
    deadlineHit: false,
  };
  const ctx: Ctx = {
    db,
    now: opts.now,
    nowTs: Timestamp.fromDate(opts.now),
    cutoff: Timestamp.fromMillis(opts.now.getTime() - REFRESH_AFTER_DAYS * DAY_MS),
    fetchLocation: opts.fetchLocation,
    cache: new Map(),
    result,
  };
  const limit = opts.limit ?? DEFAULT_LIMIT;
  const concurrency = opts.concurrency ?? DEFAULT_CONCURRENCY;
  const deadlineAt = Date.now() + (opts.deadlineMs ?? DEFAULT_DEADLINE_MS);

  const gyms = await db
    .collection("gyms")
    .where("coordsFetchedAt", "<=", ctx.cutoff)
    .orderBy("coordsFetchedAt", "asc")
    .limit(limit)
    .get();
  await forEachLimited(gyms.docs, concurrency, deadlineAt, result, (d) =>
    processGym(ctx, d),
  );

  const users = await db
    .collection("users")
    .where("trainerLocationsCoordsFetchedAt", "<=", ctx.cutoff)
    .orderBy("trainerLocationsCoordsFetchedAt", "asc")
    .limit(limit)
    .get();
  await forEachLimited(users.docs, concurrency, deadlineAt, result, (d) =>
    processTrainer(ctx, d.id),
  );

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
