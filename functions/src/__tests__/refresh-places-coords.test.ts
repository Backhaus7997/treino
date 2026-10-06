/**
 * refresh-places-coords.test.ts — refresco diario de coordenadas de Google
 * Places (#1338). Corre contra el emulador de Firestore; la llamada HTTP a
 * Places se INYECTA (`fetchLocation` / `fetchImpl`), no hay red real.
 *
 * Por qué importa: Google deja cachear `location` hasta 30 días. Si el job se
 * rompe en silencio, la app sigue sirviendo coordenadas vencidas — incumple los
 * términos y nadie lo ve. Las aserciones clave son las que miden QUÉ se escribe
 * y QUÉ NO (no pisar ediciones concurrentes, no borrar datos del usuario, no
 * espejar al perfil público sin consentimiento).
 */

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
const PROJECT = process.env.GCLOUD_PROJECT ?? "demo-places";

import {
  PlaceLookup,
  fetchPlaceLocation,
  refreshPlacesCoordsHandler,
} from "../places/refresh-places-coords";
import { geohash5 } from "../places/geohash";

let app: App;
const db = () => getFirestore(app);

const NOW = new Date("2026-10-06T12:00:00Z");
const daysAgo = (d: number) =>
  Timestamp.fromMillis(NOW.getTime() - d * 24 * 60 * 60 * 1000);

beforeAll(() => {
  app = initializeApp({ projectId: PROJECT }, "refresh-places-test");
});

afterAll(async () => {
  await deleteApp(app);
});

beforeEach(async () => {
  for (const col of ["gyms", "users", "trainerPublicProfiles"]) {
    const snap = await db().collection(col).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
});

type Fetch = jest.Mock<Promise<PlaceLookup>, [string]>;
const fetcher = (
  by: Record<string, PlaceLookup>,
  fallback: PlaceLookup = { status: "transient" },
): Fetch =>
  jest.fn(async (placeId: string) => by[placeId] ?? fallback) as Fetch;

const ok = (lat: number, lng: number): PlaceLookup => ({
  status: "ok",
  lat,
  lng,
});

async function seedGym(
  id: string,
  coordsAgeDays: number | null,
  extra: Record<string, unknown> = {},
) {
  await db()
    .collection("gyms")
    .doc(id)
    .set({
      name: `Gym ${id}`,
      lat: -34.6,
      lng: -58.4,
      geohash: geohash5(-34.6, -58.4),
      source: "google-places",
      placeStatus: "ok",
      coordsFetchedAt: coordsAgeDays == null ? null : daysAgo(coordsAgeDays),
      ...extra,
    });
}

const loc = (
  id: string,
  placeId: string | null,
  ageDays: number,
  extra: Record<string, unknown> = {},
) => ({
  id,
  type: "custom",
  gymId: null,
  customLabel: `Label ${id}`,
  lat: -34.6,
  lng: -58.4,
  geohash: geohash5(-34.6, -58.4),
  placeId,
  coordsFetchedAt: placeId == null ? null : daysAgo(ageDays),
  stale: null,
  ...extra,
});

async function seedTrainer(
  uid: string,
  locations: Array<Record<string, unknown>>,
  opts: { consent: boolean; minAge: number | null; publicDoc?: boolean },
) {
  await db()
    .collection("users")
    .doc(uid)
    .set({
      uid,
      trainerLocations: locations,
      trainerGeohashes: [...new Set(locations.map((l) => l.geohash))],
      trainerLocationsCoordsFetchedAt:
        opts.minAge == null ? null : daysAgo(opts.minAge),
      trainerLocationConsentAt: opts.consent ? daysAgo(60) : null,
    });
  if (opts.publicDoc !== false) {
    await db()
      .collection("trainerPublicProfiles")
      .doc(uid)
      .set({
        uid,
        trainerLocations: locations,
        trainerGeohashes: [...new Set(locations.map((l) => l.geohash))],
      });
  }
}

const run = (fetchLocation: Fetch, extra: Record<string, unknown> = {}) =>
  refreshPlacesCoordsHandler(app, { now: NOW, fetchLocation, ...extra });

describe("gyms", () => {
  it("refresca lat/lng/geohash/coordsFetchedAt de un gym vencido (>25d)", async () => {
    await seedGym("p1", 26);
    const f = fetcher({ p1: ok(-31.4, -64.2) });

    const r = await run(f);

    const g = (await db().collection("gyms").doc("p1").get()).data()!;
    expect(g.lat).toBe(-31.4);
    expect(g.lng).toBe(-64.2);
    expect(g.geohash).toBe(geohash5(-31.4, -64.2));
    expect(g.placeStatus).toBe("ok");
    expect((g.coordsFetchedAt as Timestamp).toMillis()).toBe(NOW.getTime());
    expect(g.name).toBe("Gym p1");
    expect(r.gymsRefreshed).toBe(1);
  });

  it("no toca un gym fresco (<=25d)", async () => {
    await seedGym("p1", 10);
    const f = fetcher({ p1: ok(0, 0) });

    await run(f);

    expect(f).not.toHaveBeenCalled();
    expect((await db().collection("gyms").doc("p1").get()).data()!.lat).toBe(
      -34.6,
    );
  });

  it("NOT_FOUND antes de 30d: marca not_found y conserva coords", async () => {
    await seedGym("p1", 27);
    await run(fetcher({ p1: { status: "not_found" } }));

    const g = (await db().collection("gyms").doc("p1").get()).data()!;
    expect(g.placeStatus).toBe("not_found");
    expect(g.geohash).toBe(geohash5(-34.6, -58.4));
    expect(g.lat).toBe(-34.6);
  });

  it("NOT_FOUND pasados 30d: quita el geohash de la búsqueda y no vuelve a ser candidato", async () => {
    await seedGym("p1", 31);
    await run(fetcher({ p1: { status: "not_found" } }));

    const g = (await db().collection("gyms").doc("p1").get()).data()!;
    expect(g.placeStatus).toBe("not_found");
    expect(g.geohash).toBeNull();
    expect(g.coordsFetchedAt).toBeNull();
    expect(g.name).toBe("Gym p1"); // nunca se borra el dato

    const f2 = fetcher({});
    await run(f2);
    expect(f2).not.toHaveBeenCalled();
  });

  it("error transitorio / 429: no escribe nada, queda para mañana", async () => {
    await seedGym("p1", 26);
    const before = (await db().collection("gyms").doc("p1").get()).data();

    const r = await run(fetcher({ p1: { status: "transient" } }));

    expect((await db().collection("gyms").doc("p1").get()).data()).toEqual(
      before,
    );
    expect(r.gymsSkipped).toBe(1);
  });

  it("no pisa una edición concurrente (precondición lastUpdateTime)", async () => {
    await seedGym("p1", 26);
    const f = jest.fn<Promise<PlaceLookup>, [string]>(async () => {
      // El cliente edita el gym mientras el job espera a Google.
      await db().collection("gyms").doc("p1").update({ name: "Editado" });
      return ok(-31.4, -64.2);
    });

    const r = await run(f);

    const g = (await db().collection("gyms").doc("p1").get()).data()!;
    expect(g.name).toBe("Editado");
    expect(g.lat).toBe(-34.6); // no se escribieron las coords nuevas
    expect(r.gymsSkipped).toBe(1);
  });

  it("acota el lote y procesa primero los más viejos", async () => {
    await seedGym("a", 40);
    await seedGym("b", 30);
    await seedGym("c", 26);
    const f = fetcher({ a: ok(1, 1), b: ok(1, 1), c: ok(1, 1) });

    await run(f, { limit: 2 });

    expect(f.mock.calls.map((c) => c[0]).sort()).toEqual(["a", "b"]);
  });

  it("corta cuando se acaba el tiempo (deadline) sin romper", async () => {
    await seedGym("a", 40);
    await seedGym("b", 30);
    const f = fetcher({ a: ok(1, 1), b: ok(1, 1) });

    const r = await run(f, { concurrency: 1, deadlineMs: 0 });

    expect(f).not.toHaveBeenCalled();
    expect(r.deadlineHit).toBe(true);
  });
});

describe("entrenadores", () => {
  it("refresca el lugar con placeId, no toca el de GPS, recalcula geohashes y mínimo, y espeja al perfil público con consentimiento", async () => {
    await seedTrainer(
      "t1",
      [
        loc("l1", "p1", 26),
        loc("l2", null, 0, { lat: -34.7, lng: -58.5, geohash: "gpsgh" }),
      ],
      { consent: true, minAge: 26 },
    );

    await run(fetcher({ p1: ok(-31.4, -64.2) }));

    const u = (await db().collection("users").doc("t1").get()).data()!;
    const l1 = u.trainerLocations.find((l: any) => l.id === "l1");
    const l2 = u.trainerLocations.find((l: any) => l.id === "l2");
    expect(l1.lat).toBe(-31.4);
    expect(l1.geohash).toBe(geohash5(-31.4, -64.2));
    expect(l1.customLabel).toBe("Label l1");
    expect(l1.coordsFetchedAt.toMillis()).toBe(NOW.getTime());
    expect(l2.geohash).toBe("gpsgh");
    expect(l2.lat).toBe(-34.7);
    expect([...u.trainerGeohashes].sort()).toEqual(
      [geohash5(-31.4, -64.2), "gpsgh"].sort(),
    );
    expect(u.trainerLocationsCoordsFetchedAt.toMillis()).toBe(NOW.getTime());

    const p = (
      await db().collection("trainerPublicProfiles").doc("t1").get()
    ).data()!;
    expect(p.trainerLocations).toEqual(u.trainerLocations);
    expect(p.trainerGeohashes).toEqual(u.trainerGeohashes);
  });

  it("sin consentimiento de ubicación NO espeja al perfil público", async () => {
    await seedTrainer("t1", [loc("l1", "p1", 26)], {
      consent: false,
      minAge: 26,
    });
    const before = (
      await db().collection("trainerPublicProfiles").doc("t1").get()
    ).data();

    await run(fetcher({ p1: ok(-31.4, -64.2) }));

    expect(
      (await db().collection("users").doc("t1").get()).data()!
        .trainerLocations[0].lat,
    ).toBe(-31.4);
    expect(
      (await db().collection("trainerPublicProfiles").doc("t1").get()).data(),
    ).toEqual(before);
  });

  it("no crea el perfil público si no existe", async () => {
    await seedTrainer("t1", [loc("l1", "p1", 26)], {
      consent: true,
      minAge: 26,
      publicDoc: false,
    });

    await run(fetcher({ p1: ok(-31.4, -64.2) }));

    expect(
      (await db().collection("trainerPublicProfiles").doc("t1").get()).exists,
    ).toBe(false);
  });

  it("NOT_FOUND pasados 30d: marca stale, lo saca de trainerGeohashes y del espejo público, y conserva el dato del usuario", async () => {
    await seedTrainer(
      "t1",
      [
        loc("l1", "p1", 31, { geohash: "oldgh" }),
        loc("l2", null, 0, { geohash: "gpsgh" }),
      ],
      { consent: true, minAge: 31 },
    );

    await run(fetcher({ p1: { status: "not_found" } }));

    const u = (await db().collection("users").doc("t1").get()).data()!;
    const l1 = u.trainerLocations.find((l: any) => l.id === "l1");
    expect(l1.stale).toBe(true);
    expect(l1.customLabel).toBe("Label l1");
    expect(u.trainerGeohashes).toEqual(["gpsgh"]);
    expect(u.trainerLocationsCoordsFetchedAt).toBeNull();

    const p = (
      await db().collection("trainerPublicProfiles").doc("t1").get()
    ).data()!;
    expect(p.trainerGeohashes).toEqual(["gpsgh"]);
    expect(p.trainerLocations.map((l: any) => l.id)).toEqual(["l2"]);
  });

  it("NOT_FOUND antes de 30d: no cambia nada del lugar (se reintenta mañana)", async () => {
    await seedTrainer("t1", [loc("l1", "p1", 27)], {
      consent: true,
      minAge: 27,
    });
    const before = (await db().collection("users").doc("t1").get()).data();

    await run(fetcher({ p1: { status: "not_found" } }));

    expect((await db().collection("users").doc("t1").get()).data()).toEqual(
      before,
    );
  });

  it("transitorio: no escribe", async () => {
    await seedTrainer("t1", [loc("l1", "p1", 26)], {
      consent: true,
      minAge: 26,
    });
    const before = (await db().collection("users").doc("t1").get()).data();

    const r = await run(fetcher({ p1: { status: "transient" } }));

    expect((await db().collection("users").doc("t1").get()).data()).toEqual(
      before,
    );
    expect(r.usersSkipped).toBe(1);
  });

  it("un lugar ya stale no se vuelve a consultar y no deja al usuario pegado en la cola", async () => {
    await seedTrainer("t1", [loc("l1", "p1", 40, { stale: true })], {
      consent: true,
      minAge: 40,
    });
    const f = fetcher({});

    await run(f);

    expect(f).not.toHaveBeenCalled();
    expect(
      (await db().collection("users").doc("t1").get()).data()!
        .trainerLocationsCoordsFetchedAt,
    ).toBeNull();
  });
});

describe("dedupe dentro de la corrida", () => {
  it("un mismo placeId en un gym y en dos entrenadores se pide UNA sola vez", async () => {
    await seedGym("p1", 26);
    await seedTrainer("t1", [loc("l1", "p1", 26)], {
      consent: true,
      minAge: 26,
    });
    await seedTrainer("t2", [loc("l1", "p1", 27)], {
      consent: true,
      minAge: 27,
    });
    const f = fetcher({ p1: ok(-31.4, -64.2) });

    await run(f);

    expect(f).toHaveBeenCalledTimes(1);
    for (const t of ["t1", "t2"]) {
      expect(
        (await db().collection("users").doc(t).get()).data()!
          .trainerLocations[0].lat,
      ).toBe(-31.4);
    }
  });
});

describe("fetchPlaceLocation (HTTP)", () => {
  const res = (status: number, body: unknown) =>
    ({
      status,
      ok: status >= 200 && status < 300,
      json: async () => body,
    }) as unknown as Response;

  it("pide GET places/{id} con field mask `location` y SIN sessionToken", async () => {
    const fetchImpl = jest.fn(async () =>
      res(200, { location: { latitude: -31.4, longitude: -64.2 } }),
    );

    const out = await fetchPlaceLocation("KEY", fetchImpl)("ChIJabc");

    expect(out).toEqual({ status: "ok", lat: -31.4, lng: -64.2 });
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [
      string,
      RequestInit,
    ];
    expect(url).toBe("https://places.googleapis.com/v1/places/ChIJabc");
    expect(init.method).toBe("GET");
    const h = init.headers as Record<string, string>;
    expect(h["X-Goog-FieldMask"]).toBe("location");
    expect(h["X-Goog-Api-Key"]).toBe("KEY");
  });

  it.each([
    [404, { error: { status: "NOT_FOUND" } }, "not_found"],
    [
      400,
      { error: { status: "INVALID_ARGUMENT", message: "Invalid place ID" } },
      "not_found",
    ],
    [
      400,
      {
        error: {
          status: "INVALID_ARGUMENT",
          message: "API key not valid",
          details: [{ reason: "API_KEY_INVALID" }],
        },
      },
      "transient",
    ],
    [429, { error: { status: "RESOURCE_EXHAUSTED" } }, "transient"],
    [500, {}, "transient"],
    [403, { error: { status: "PERMISSION_DENIED" } }, "transient"],
  ])("HTTP %s -> %s", async (status, body, expected) => {
    const out = await fetchPlaceLocation(
      "KEY",
      jest.fn(async () => res(status, body)),
    )("x");
    expect(out.status).toBe(expected);
  });

  it("200 sin location, o una excepción de red -> transient", async () => {
    expect(
      (await fetchPlaceLocation("K", jest.fn(async () => res(200, {})))("x"))
        .status,
    ).toBe("transient");
    expect(
      (
        await fetchPlaceLocation(
          "K",
          jest.fn(async () => {
            throw new Error("boom KEY");
          }),
        )("x")
      ).status,
    ).toBe("transient");
  });
});

describe("geohash5", () => {
  it("coincide con el de Dart (lib/core/utils/geohash.dart)", () => {
    // Vector conocido: Buenos Aires Obelisco -> "69y7p".
    expect(geohash5(-34.6037, -58.3816)).toBe("69y7p");
  });
});
