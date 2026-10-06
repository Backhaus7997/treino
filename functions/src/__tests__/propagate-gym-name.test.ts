/**
 * Propagacion de `gyms/{id}.name` a `userPublicProfiles.gymName`.
 *
 * `gymName` es una copia denormalizada: la escribe el cliente al vincular el
 * gym (`UserRepository.update`). Cuando un gym migrado se nombra DESPUES de
 * tener usuarios vinculados (politica de Places, #1338), esos usuarios quedan
 * con `gymName` null para siempre. Y cuando la cuarentena revierte un nombre
 * vetado, las copias tendrian que volver a null.
 *
 * Correr:
 *   firebase emulators:exec --only firestore --project demo-places \
 *     "npx jest --forceExit --runInBand propagate-gym-name"
 */

jest.mock("firebase-functions/v2/firestore", () => ({
  onDocumentWritten: (_opts: unknown, handler: unknown) => handler,
}));

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";

import {
  propagateGymName,
  propagateGymNameToProfiles,
} from "../gyms/propagate-gym-name";

type Snap = FirebaseFirestore.DocumentSnapshot;
type TriggerHandler = (event: {
  data: { before: Snap; after: Snap };
  params: { gymId: string };
}) => Promise<void>;

let app: App;
let db: Firestore;
let defaultApp: App;

beforeAll(() => {
  app = initializeApp({ projectId: "demo-places" }, "propagate-gym");
  db = getFirestore(app);
  defaultApp = initializeApp({ projectId: "demo-places" });
});

afterAll(async () => {
  await deleteApp(app);
  await deleteApp(defaultApp);
});

afterEach(async () => {
  for (const c of ["gyms", "userPublicProfiles"]) {
    const snap = await db.collection(c).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
});

const gym = (extra: Record<string, unknown> = {}) => ({
  id: "g1",
  name: "Gimnasio",
  lat: -34.6,
  lng: -58.4,
  geohash: "6d6m7",
  source: "google-places",
  ...extra,
});

async function seedProfile(uid: string, gymId: string, gymName: unknown) {
  await db.doc(`userPublicProfiles/${uid}`).set({ uid, gymId, gymName });
}

describe("propagateGymName", () => {
  it("gym nombrado: copia el nombre a TODOS los vinculados y a nadie mas", async () => {
    await db.doc("gyms/g1").set(gym({ name: "Mi Gym" }));
    await seedProfile("u1", "g1", null);
    await seedProfile("u2", "g1", null);
    await seedProfile("u3", "g1", "Nombre viejo");
    await seedProfile("otro", "g2", null);

    const n = await propagateGymName({ db, gymId: "g1" });

    expect(n).toBe(3);
    for (const u of ["u1", "u2", "u3"]) {
      expect(
        (await db.doc(`userPublicProfiles/${u}`).get()).get("gymName"),
      ).toBe("Mi Gym");
    }
    expect(
      (await db.doc("userPublicProfiles/otro").get()).get("gymName"),
    ).toBeNull();
  });

  it("gym que vuelve a nameNeeded (reversion de la cuarentena): gymName pasa a null", async () => {
    await db.doc("gyms/g1").set(gym({ nameNeeded: true }));
    await seedProfile("u1", "g1", "sos un hijo de puta");

    await propagateGymName({ db, gymId: "g1" });

    expect(
      (await db.doc("userPublicProfiles/u1").get()).get("gymName"),
    ).toBeNull();
  });

  it("gym borrado: gymName pasa a null", async () => {
    await seedProfile("u1", "g1", "Mi Gym");
    await propagateGymName({ db, gymId: "g1" });
    expect(
      (await db.doc("userPublicProfiles/u1").get()).get("gymName"),
    ).toBeNull();
  });

  it("pagina: con mas docs que el tamano de pagina actualiza todos", async () => {
    await db.doc("gyms/g1").set(gym({ name: "Mi Gym" }));
    for (let i = 0; i < 7; i++) await seedProfile(`u${i}`, "g1", null);

    const n = await propagateGymName({ db, gymId: "g1", pageSize: 3 });

    expect(n).toBe(7);
    const snap = await db
      .collection("userPublicProfiles")
      .where("gymName", "==", "Mi Gym")
      .get();
    expect(snap.size).toBe(7);
  });

  it("idempotente: la segunda pasada no escribe nada (sin bucle)", async () => {
    await db.doc("gyms/g1").set(gym({ name: "Mi Gym" }));
    await seedProfile("u1", "g1", null);
    await propagateGymName({ db, gymId: "g1" });
    const antes = (await db.doc("userPublicProfiles/u1").get()).updateTime;

    const n = await propagateGymName({ db, gymId: "g1" });

    expect(n).toBe(0);
    expect((await db.doc("userPublicProfiles/u1").get()).updateTime).toEqual(
      antes,
    );
  });

  it("un nombre vetado NO se copia: lo revierte la cuarentena y ese evento propaga", async () => {
    await db.doc("gyms/g1").set(gym({ name: "sos un hijo de puta" }));
    await seedProfile("u1", "g1", null);

    const n = await propagateGymName({ db, gymId: "g1" });

    expect(n).toBe(0);
    expect(
      (await db.doc("userPublicProfiles/u1").get()).get("gymName"),
    ).toBeNull();
  });
});

describe("propagateGymNameToProfiles (wrapper real)", () => {
  const run = async (before: Snap, after: Snap) =>
    (propagateGymNameToProfiles as unknown as TriggerHandler)({
      data: { before, after },
      params: { gymId: "g1" },
    });

  it("el gym pasa de nameNeeded a nombrado: propaga", async () => {
    await db.doc("gyms/g1").set(gym({ nameNeeded: true }));
    const before = await db.doc("gyms/g1").get();
    await db.doc("gyms/g1").update({ name: "Mi Gym", nameNeeded: false });
    const after = await db.doc("gyms/g1").get();
    await seedProfile("u1", "g1", null);

    await run(before, after);

    expect((await db.doc("userPublicProfiles/u1").get()).get("gymName")).toBe(
      "Mi Gym",
    );
  });

  it("un cambio que no toca el nombre efectivo (coords) no hace nada", async () => {
    await db.doc("gyms/g1").set(gym({ name: "Mi Gym" }));
    const before = await db.doc("gyms/g1").get();
    await db.doc("gyms/g1").update({ lat: -34.7 });
    const after = await db.doc("gyms/g1").get();
    // Copia desactualizada a proposito: si el trigger corriera, la arreglaria.
    await seedProfile("u1", "g1", "Otro");

    await run(before, after);

    expect((await db.doc("userPublicProfiles/u1").get()).get("gymName")).toBe(
      "Otro",
    );
  });

  it("alta del gym con nombre (before inexistente): propaga", async () => {
    const before = await db.doc("gyms/g1").get();
    await db.doc("gyms/g1").set(gym({ name: "Mi Gym" }));
    const after = await db.doc("gyms/g1").get();
    await seedProfile("u1", "g1", null);

    await run(before, after);

    expect((await db.doc("userPublicProfiles/u1").get()).get("gymName")).toBe(
      "Mi Gym",
    );
  });

  it("gym borrado: pone null", async () => {
    await db.doc("gyms/g1").set(gym({ name: "Mi Gym" }));
    const before = await db.doc("gyms/g1").get();
    await db.doc("gyms/g1").delete();
    const after = await db.doc("gyms/g1").get();
    await seedProfile("u1", "g1", "Mi Gym");

    await run(before, after);

    expect(
      (await db.doc("userPublicProfiles/u1").get()).get("gymName"),
    ).toBeNull();
  });
});
