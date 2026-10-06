/**
 * Cuarentena de `gyms/{id}.name`.
 *
 * El nombre lo tipea el primer usuario que vincula el gimnasio (politica de
 * Places, #1338) y el catalogo lo lee cualquier autenticado: la capa
 * del cliente se saltea con el SDK directo, esta no. Un nombre vetado vuelve el
 * gym a `nameNeeded: true` con un nombre neutro, para que el proximo usuario
 * lo nombre.
 *
 * Correr:
 *   firebase emulators:exec --only firestore --project demo-places \
 *     "npx jest --forceExit --runInBand quarantine-gym-name"
 */

jest.mock("firebase-functions/v2/firestore", () => ({
  onDocumentWritten: (_opts: unknown, handler: unknown) => handler,
}));

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";

import {
  GYM_NOMBRE_PENDIENTE,
  QUARANTINE_COLLECTION,
  quarantineGym,
  quarantineGymName,
} from "../moderation/quarantine-vetted-content";

const VETADO = "sos un hijo de puta";
const REVIEW = "sos un pelotudo";

type TriggerHandler = (event: {
  data: { after: FirebaseFirestore.DocumentSnapshot };
  params: { gymId: string };
}) => Promise<void>;

let app: App;
let db: Firestore;
let defaultApp: App;

beforeAll(() => {
  app = initializeApp({ projectId: "demo-places" }, "quarantine-gym");
  db = getFirestore(app);
  defaultApp = initializeApp({ projectId: "demo-places" });
});

afterAll(async () => {
  await deleteApp(app);
  await deleteApp(defaultApp);
});

afterEach(async () => {
  for (const c of ["gyms", QUARANTINE_COLLECTION]) {
    const snap = await db.collection(c).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
});

const gym = (name: unknown, extra: Record<string, unknown> = {}) => ({
  id: "g1",
  name,
  lat: -34.6,
  lng: -58.4,
  geohash: "6d6m7",
  source: "google-places",
  ...extra,
});

describe("quarantineGymName", () => {
  it("block: vuelve a nameNeeded con nombre neutro, no toca coords y registra", async () => {
    await db.doc("gyms/g1").set(gym(VETADO));
    const snap = await db.doc("gyms/g1").get();

    const verdict = await quarantineGymName({
      db,
      path: "gyms/g1",
      name: snap.get("name"),
      nameNeeded: snap.get("nameNeeded"),
      updateTime: snap.updateTime,
    });

    expect(verdict).toBe("block");
    const after = await db.doc("gyms/g1").get();
    expect(after.get("name")).toBe(GYM_NOMBRE_PENDIENTE);
    expect(after.get("nameNeeded")).toBe(true);
    expect(after.get("lat")).toBe(-34.6);
    const reg = await db
      .collection(QUARANTINE_COLLECTION)
      .doc("gyms__g1")
      .get();
    expect(reg.get("verdict")).toBe("block");
    expect(reg.get("redacted")).toBe(true);
    // El texto NO se guarda en el registro.
    expect(JSON.stringify(reg.data())).not.toContain("hijo");
  });

  it("review: registra pero NO toca el gym", async () => {
    await db.doc("gyms/g2").set(gym(REVIEW));
    const snap = await db.doc("gyms/g2").get();

    const verdict = await quarantineGymName({
      db,
      path: "gyms/g2",
      name: snap.get("name"),
      nameNeeded: undefined,
      updateTime: snap.updateTime,
    });

    expect(verdict).toBe("review");
    const after = await db.doc("gyms/g2").get();
    expect(after.get("name")).toBe(REVIEW);
    expect(after.get("nameNeeded")).toBeUndefined();
    expect(
      (await db.collection(QUARANTINE_COLLECTION).doc("gyms__g2").get()).get(
        "redacted",
      ),
    ).toBe(false);
  });

  it("nombre limpio, vacio o no-string: no hace nada", async () => {
    await db.doc("gyms/g3").set(gym("SportClub Belgrano"));
    for (const name of ["SportClub Belgrano", "", "   ", null, 42, undefined]) {
      expect(
        await quarantineGymName({
          db,
          path: "gyms/g3",
          name,
          nameNeeded: undefined,
        }),
      ).toBe("ok");
    }
    expect((await db.collection(QUARANTINE_COLLECTION).get()).size).toBe(0);
  });

  it("un gym ya marcado nameNeeded se saltea (su nombre no es de un usuario)", async () => {
    await db.doc("gyms/g4").set(gym(VETADO, { nameNeeded: true }));
    expect(
      await quarantineGymName({
        db,
        path: "gyms/g4",
        name: VETADO,
        nameNeeded: true,
      }),
    ).toBe("ok");
    expect((await db.doc("gyms/g4").get()).get("name")).toBe(VETADO);
  });

  it("el nombre de reemplazo no es vetado: la segunda pasada no escribe (sin bucle)", async () => {
    await db.doc("gyms/g5").set(gym(VETADO));
    const snap = await db.doc("gyms/g5").get();
    await quarantineGymName({
      db,
      path: "gyms/g5",
      name: snap.get("name"),
      nameNeeded: undefined,
      updateTime: snap.updateTime,
    });
    const tras = await db.doc("gyms/g5").get();
    expect(tras.get("name")).toBe(GYM_NOMBRE_PENDIENTE);

    // Segunda pasada: lo que dispararia el propio update de la funcion.
    const verdict = await quarantineGymName({
      db,
      path: "gyms/g5",
      name: tras.get("name"),
      nameNeeded: tras.get("nameNeeded"),
      updateTime: tras.updateTime,
    });
    expect(verdict).toBe("ok");
    expect((await db.doc("gyms/g5").get()).updateTime).toEqual(tras.updateTime);
  });

  it("si el doc cambio despues del evento no lo pisa (precondicion)", async () => {
    await db.doc("gyms/g6").set(gym(VETADO));
    const snap = await db.doc("gyms/g6").get();
    // Otro escritor corrige el nombre antes de que corra la funcion.
    await db.doc("gyms/g6").update({ name: "Gimnasio Limpio" });

    await quarantineGymName({
      db,
      path: "gyms/g6",
      name: snap.get("name"),
      nameNeeded: undefined,
      updateTime: snap.updateTime,
    });

    expect((await db.doc("gyms/g6").get()).get("name")).toBe("Gimnasio Limpio");
  });
});

describe("quarantineGym (wrapper real)", () => {
  it("redacta un nombre vetado desde el trigger", async () => {
    await db.doc("gyms/g7").set(gym(VETADO));
    const snap = await db.doc("gyms/g7").get();

    await (quarantineGym as unknown as TriggerHandler)({
      data: { after: snap },
      params: { gymId: "g7" },
    });

    const after = await db.doc("gyms/g7").get();
    expect(after.get("name")).toBe(GYM_NOMBRE_PENDIENTE);
    expect(after.get("nameNeeded")).toBe(true);
  });

  it("ignora un doc borrado", async () => {
    await db.doc("gyms/g8").set(gym("x"));
    const snap = await db.doc("gyms/g8").get();
    await db.doc("gyms/g8").delete();
    const gone = await db.doc("gyms/g8").get();
    expect(gone.exists).toBe(false);
    await expect(
      (quarantineGym as unknown as TriggerHandler)({
        data: { after: gone },
        params: { gymId: "g8" },
      }),
    ).resolves.toBeUndefined();
    void snap;
  });
});
