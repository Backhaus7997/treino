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
import { logger } from "firebase-functions";

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
  // La alerta de «ninguna consulta ok» es ruido en los tests que no la miden.
  jest.spyOn(logger, "error").mockImplementation(() => {});
  for (const col of [
    "gyms",
    "users",
    "trainerPublicProfiles",
    "placesRefreshBackoff",
  ]) {
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
      trainerGeohashes: [
        ...new Set(locations.map((l) => l.geohash).filter((g) => g)),
      ],
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
        trainerGeohashes: [
          ...new Set(locations.map((l) => l.geohash).filter((g) => g)),
        ],
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

  it("NOT_FOUND pasados 30d: borra lat/lng/geohash (no se cachean coords vencidas) y no vuelve a ser candidato", async () => {
    await seedGym("p1", 31);
    await run(fetcher({ p1: { status: "not_found" } }));

    const g = (await db().collection("gyms").doc("p1").get()).data()!;
    expect(g.placeStatus).toBe("not_found");
    expect(g.lat).toBeNull();
    expect(g.lng).toBeNull();
    expect(g.geohash).toBeNull();
    expect(g.coordsFetchedAt).toBeNull();
    expect(g.name).toBe("Gym p1"); // nunca se borra el dato

    // Ni días después: not_found sale de la cola para siempre.
    const f2 = fetcher({ p1: ok(-31.4, -64.2) });
    await refreshPlacesCoordsHandler(app, {
      now: new Date(NOW.getTime() + 5 * 24 * 60 * 60 * 1000),
      fetchLocation: f2,
    });
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
    expect(l1.lat).toBeNull();
    expect(l1.lng).toBeNull();
    expect(l1.geohash).toBeNull();
    expect(l1.placeId).toBe("p1");
    expect(l1.coordsFetchedAt).toBeNull(); // not_found: no se reintenta
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

  it("un lugar stale por NOT_FOUND (sin coordsFetchedAt) no se vuelve a consultar y no deja al usuario pegado en la cola", async () => {
    await seedTrainer(
      "t1",
      [
        loc("l1", "p1", 40, {
          stale: true,
          lat: null,
          lng: null,
          geohash: null,
          coordsFetchedAt: null,
        }),
      ],
      {
        consent: true,
        minAge: 40,
      },
    );
    const f = fetcher({});

    await run(f);

    expect(f).not.toHaveBeenCalled();
    expect(
      (await db().collection("users").doc("t1").get()).data()!
        .trainerLocationsCoordsFetchedAt,
    ).toBeNull();
  });
});

describe("purga por EDAD (cumplimiento de los 30 días)", () => {
  it("gym de 31d + error transitorio: borra lat/lng/geohash pero SIGUE en la cola", async () => {
    await seedGym("p1", 31);

    const r = await run(fetcher({ p1: { status: "transient" } }));

    const g = (await db().collection("gyms").doc("p1").get()).data()!;
    expect(g.lat).toBeNull();
    expect(g.lng).toBeNull();
    expect(g.geohash).toBeNull();
    expect(g.placeStatus).toBe("ok"); // no es not_found
    expect((g.coordsFetchedAt as Timestamp).toMillis()).toBe(0);
    expect(g.name).toBe("Gym p1");
    expect(r.gymsPurged).toBe(1);
  });

  it("gym purgado por un fallo transitorio: cuando la key vuelve a andar se restauran lat/lng/geohash/coordsFetchedAt", async () => {
    await seedGym("p1", 31);
    await run(fetcher({ p1: { status: "transient" } }));

    const later = new Date(NOW.getTime() + 2 * 24 * 60 * 60 * 1000);
    const r = await refreshPlacesCoordsHandler(app, {
      now: later,
      fetchLocation: fetcher({ p1: ok(-31.4, -64.2) }),
    });

    const g = (await db().collection("gyms").doc("p1").get()).data()!;
    expect(g.lat).toBe(-31.4);
    expect(g.lng).toBe(-64.2);
    expect(g.geohash).toBe(geohash5(-31.4, -64.2));
    expect(g.placeStatus).toBe("ok");
    expect((g.coordsFetchedAt as Timestamp).toMillis()).toBe(later.getTime());
    expect(r.gymsRefreshed).toBe(1);
  });

  it("gym ya purgado + otro fallo transitorio: no se vuelve a escribir ni a contar, y se posterga para no frenar la cola", async () => {
    await seedGym("p1", 31);
    await run(fetcher({ p1: { status: "transient" } }));
    const before = (await db().collection("gyms").doc("p1").get()).data();

    const later = new Date(NOW.getTime() + 2 * 24 * 60 * 60 * 1000);
    const r = await refreshPlacesCoordsHandler(app, {
      now: later,
      fetchLocation: fetcher({ p1: { status: "transient" } }),
    });

    expect((await db().collection("gyms").doc("p1").get()).data()).toEqual(
      before,
    );
    expect(r.gymsPurged).toBe(0);
    const b = (
      await db().collection("placesRefreshBackoff").doc("gym_p1").get()
    ).data()!;
    expect((b.nextAttemptAt as Timestamp).toMillis()).toBeGreaterThan(
      later.getTime(),
    );
  });

  it("gym de 26d + error transitorio: se conserva y se salta", async () => {
    await seedGym("p1", 26);
    const before = (await db().collection("gyms").doc("p1").get()).data();

    const r = await run(fetcher({ p1: { status: "transient" } }));

    expect((await db().collection("gyms").doc("p1").get()).data()).toEqual(
      before,
    );
    expect(r.gymsSkipped).toBe(1);
    expect(r.gymsPurged).toBe(0);
  });

  it("lugar de PF de 31d + error transitorio: stale sin coords, afuera de geohashes y del espejo público, pero reintentable", async () => {
    await seedTrainer(
      "t1",
      [
        loc("l1", "p1", 31, { geohash: "oldgh" }),
        loc("l2", null, 0, { geohash: "gpsgh" }),
      ],
      { consent: true, minAge: 31 },
    );

    const r = await run(fetcher({ p1: { status: "transient" } }));

    const u = (await db().collection("users").doc("t1").get()).data()!;
    const l1 = u.trainerLocations.find((l: any) => l.id === "l1");
    expect(l1.stale).toBe(true);
    expect(l1.lat).toBeNull();
    expect(l1.lng).toBeNull();
    expect(l1.geohash).toBeNull();
    expect(l1.placeId).toBe("p1");
    // Se conserva la fecha vieja: el usuario sigue en la cola de reintento.
    expect((l1.coordsFetchedAt as Timestamp).toMillis()).toBe(
      daysAgo(31).toMillis(),
    );
    expect(
      (u.trainerLocationsCoordsFetchedAt as Timestamp).toMillis(),
    ).toBe(daysAgo(31).toMillis());
    expect(u.trainerGeohashes).toEqual(["gpsgh"]);
    const p = (
      await db().collection("trainerPublicProfiles").doc("t1").get()
    ).data()!;
    expect(p.trainerLocations.map((l: any) => l.id)).toEqual(["l2"]);
    expect(r.usersPurged).toBe(1);
  });

  it("lugar de PF stale por fallo transitorio: cuando Places vuelve, se limpia stale y se restauran coords, geohash y espejo público", async () => {
    await seedTrainer(
      "t1",
      [loc("l1", "p1", 31), loc("l2", null, 0, { geohash: "gpsgh" })],
      { consent: true, minAge: 31 },
    );
    await run(fetcher({ p1: { status: "transient" } }));

    const later = new Date(NOW.getTime() + 2 * 24 * 60 * 60 * 1000);
    const r = await refreshPlacesCoordsHandler(app, {
      now: later,
      fetchLocation: fetcher({ p1: ok(-31.4, -64.2) }),
    });

    const u = (await db().collection("users").doc("t1").get()).data()!;
    const l1 = u.trainerLocations.find((l: any) => l.id === "l1");
    expect(l1.stale).toBeNull();
    expect(l1.lat).toBe(-31.4);
    expect(l1.lng).toBe(-64.2);
    expect(l1.geohash).toBe(geohash5(-31.4, -64.2));
    expect((l1.coordsFetchedAt as Timestamp).toMillis()).toBe(later.getTime());
    expect(new Set(u.trainerGeohashes)).toEqual(
      new Set(["gpsgh", geohash5(-31.4, -64.2)]),
    );
    expect(
      (u.trainerLocationsCoordsFetchedAt as Timestamp).toMillis(),
    ).toBe(later.getTime());
    const p = (
      await db().collection("trainerPublicProfiles").doc("t1").get()
    ).data()!;
    expect(p.trainerLocations.map((l: any) => l.id).sort()).toEqual([
      "l1",
      "l2",
    ]);
    expect(r.usersUpdated).toBe(1);
  });

  it("restaurar un lugar stale SIN consentimiento no lo espeja al perfil público", async () => {
    await seedTrainer("t1", [loc("l1", "p1", 31)], {
      consent: false,
      minAge: 31,
    });
    await run(fetcher({ p1: { status: "transient" } }));
    const pubBefore = (
      await db().collection("trainerPublicProfiles").doc("t1").get()
    ).data();

    const later = new Date(NOW.getTime() + 2 * 24 * 60 * 60 * 1000);
    await refreshPlacesCoordsHandler(app, {
      now: later,
      fetchLocation: fetcher({ p1: ok(-31.4, -64.2) }),
    });

    const u = (await db().collection("users").doc("t1").get()).data()!;
    expect(u.trainerLocations[0].lat).toBe(-31.4);
    expect(
      (await db().collection("trainerPublicProfiles").doc("t1").get()).data(),
    ).toEqual(pubBefore);
  });

  it("lugar stale por fallo transitorio que ahora da NOT_FOUND: deja de reintentarse", async () => {
    await seedTrainer("t1", [loc("l1", "p1", 31)], {
      consent: true,
      minAge: 31,
    });
    await run(fetcher({ p1: { status: "transient" } }));

    const later = new Date(NOW.getTime() + 2 * 24 * 60 * 60 * 1000);
    await refreshPlacesCoordsHandler(app, {
      now: later,
      fetchLocation: fetcher({ p1: { status: "not_found" } }),
    });
    const u = (await db().collection("users").doc("t1").get()).data()!;
    expect(u.trainerLocations[0].stale).toBe(true);
    expect(u.trainerLocations[0].coordsFetchedAt).toBeNull();
    expect(u.trainerLocationsCoordsFetchedAt).toBeNull();
  });

  it("lugar de PF de 26d + error transitorio: se conserva", async () => {
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
    expect(r.usersPurged).toBe(0);
  });

  it("una corrida donde TODAS las consultas fallan loguea a nivel error", async () => {
    await seedGym("p1", 26);
    const err = logger.error as jest.Mock;
    err.mockClear();

    await run(fetcher({}, { status: "transient" }));

    expect(err).toHaveBeenCalledWith(
      expect.stringContaining("ninguna consulta"),
      expect.anything(),
    );
  });

  it("si al menos una consulta sale ok NO loguea la alerta", async () => {
    await seedGym("p1", 26);
    const err = logger.error as jest.Mock;
    err.mockClear();

    await run(fetcher({ p1: ok(-31.4, -64.2) }));

    expect(err).not.toHaveBeenCalled();
  });
});

describe("equidad y topes", () => {
  it("los docs irresolubles no bloquean la ventana: se posterga y el límite avanza a los siguientes", async () => {
    await seedGym("a", 26.5);
    await seedGym("b", 26.2);
    await seedGym("c", 25.5);
    const f1 = fetcher({ c: ok(1, 1) });

    await run(f1, { limit: 2 }); // a y b: transitorios -> postergados
    expect(f1.mock.calls.map((c) => c[0]).sort()).toEqual(["a", "b"]);

    const f2 = fetcher({ c: ok(1, 1) });
    await run(f2, { limit: 2 });
    expect(f2.mock.calls.map((c) => c[0])).toEqual(["c"]);
    expect((await db().collection("gyms").doc("c").get()).data()!.lat).toBe(1);
  });

  it("el postergamiento no pasa del día 28: un gym viejo no queda oculto hasta vencer", async () => {
    await seedGym("a", 27.5); // tope = día 28 => mañana ya es elegible
    await run(fetcher({}));
    const st = (
      await db().collection("placesRefreshBackoff").doc("gym_a").get()
    ).data()!;
    const max = NOW.getTime() + 0.5 * 24 * 60 * 60 * 1000;
    expect((st.nextAttemptAt as Timestamp).toMillis()).toBeLessThanOrEqual(max);
  });

  it("NOT_FOUND antes de 30d también posterga", async () => {
    await seedGym("a", 26);
    await run(fetcher({ a: { status: "not_found" } }));
    const f2 = fetcher({});
    await run(f2);
    expect(f2).not.toHaveBeenCalled();
  });

  it("los gyms no dejan sin tiempo a los entrenadores (presupuesto por fase)", async () => {
    await seedGym("g1", 30);
    await seedGym("g2", 29);
    await seedGym("g3", 28);
    await seedTrainer("t1", [loc("l1", "pu", 26)], {
      consent: true,
      minAge: 26,
    });
    const f = jest.fn(async (id: string): Promise<PlaceLookup> => {
      if (id.startsWith("g")) {
        await new Promise((r) => setTimeout(r, 300));
        return ok(1, 1);
      }
      return ok(-31.4, -64.2);
    }) as Fetch;

    const r = await run(f, { concurrency: 1, deadlineMs: 400 });

    expect(r.deadlineHit).toBe(true);
    expect(
      f.mock.calls.filter((c) => c[0].startsWith("g")).length,
    ).toBeLessThan(3);
    expect(
      (await db().collection("users").doc("t1").get()).data()!
        .trainerLocations[0].lat,
    ).toBe(-31.4);
  });

  it("tope de consultas distintas a Places por corrida", async () => {
    await seedGym("a", 40);
    await seedGym("b", 39);
    await seedGym("c", 38);
    const f = fetcher({ a: ok(1, 1), b: ok(1, 1), c: ok(1, 1) });

    const r = await run(f, { maxPlaceFetches: 2 });

    expect(f).toHaveBeenCalledTimes(2);
    expect(r.fetchCapHit).toBe(true);
  });

  it("los placeIds de un entrenador no exceden la concurrencia global", async () => {
    const locs = ["p1", "p2", "p3", "p4", "p5", "p6"].map((p, i) =>
      loc(`l${i}`, p, 26),
    );
    await seedTrainer("t1", locs, { consent: true, minAge: 26 });
    let inFlight = 0;
    let max = 0;
    const f = jest.fn(async (): Promise<PlaceLookup> => {
      inFlight++;
      max = Math.max(max, inFlight);
      await new Promise((r) => setTimeout(r, 20));
      inFlight--;
      return ok(-31.4, -64.2);
    }) as unknown as Fetch;

    await run(f, { concurrency: 2 });

    expect(f).toHaveBeenCalledTimes(6);
    expect(max).toBeLessThanOrEqual(2);
  });
});

describe("bordes de datos", () => {
  it("coordsFetchedAt = 1970-01-01 (lo que pone la migración) se recoge y se refresca", async () => {
    await seedGym("p1", null, { coordsFetchedAt: Timestamp.fromMillis(0) });
    await seedTrainer(
      "t1",
      [{ ...loc("l1", "p2", 0), coordsFetchedAt: Timestamp.fromMillis(0) }],
      { consent: true, minAge: null },
    );
    await db()
      .collection("users")
      .doc("t1")
      .update({ trainerLocationsCoordsFetchedAt: Timestamp.fromMillis(0) });

    await run(fetcher({ p1: ok(-31.4, -64.2), p2: ok(-32, -65) }));

    const g = (await db().collection("gyms").doc("p1").get()).data()!;
    expect(g.lat).toBe(-31.4);
    expect((g.coordsFetchedAt as Timestamp).toMillis()).toBe(NOW.getTime());
    const u = (await db().collection("users").doc("t1").get()).data()!;
    expect(u.trainerLocations[0].lat).toBe(-32);
  });

  it("un lugar sin geohash no rompe la transacción", async () => {
    const bad: Record<string, unknown> = loc("l1", "p1", 26);
    delete bad.geohash;
    await seedTrainer("t1", [bad, loc("l2", "p2", 26)], {
      consent: true,
      minAge: 26,
    });

    await run(fetcher({ p1: { status: "transient" }, p2: ok(-31.4, -64.2) }));

    const u = (await db().collection("users").doc("t1").get()).data()!;
    expect(u.trainerLocations.find((l: any) => l.id === "l2").lat).toBe(-31.4);
    expect(u.trainerGeohashes).toEqual([geohash5(-31.4, -64.2)]);
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
    [
      400,
      { error: { status: "INVALID_ARGUMENT", message: "Invalid place_id" } },
      "not_found",
    ],
    [
      400,
      {
        error: {
          status: "INVALID_ARGUMENT",
          message: "Invalid place id",
          details: [{ reason: "API_KEY_INVALID" }],
        },
      },
      "transient",
    ],
    [
      400,
      { error: { status: "INVALID_ARGUMENT", message: "Bad field mask" } },
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
      (
        await fetchPlaceLocation(
          "K",
          jest.fn(async () => res(200, {})),
        )("x")
      ).status,
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
