/**
 * Cuarentena de las etiquetas de `trainerLocations[].customLabel`.
 *
 * La etiqueta la escribe el PF y se espeja a `trainerPublicProfiles`, que lee
 * cualquier autenticado: mismo criterio que `trainerBio`. Vive dentro de un
 * array de maps, asi que se lee el array entero, se redacta adentro y se
 * reescribe (Firestore no actualiza un elemento por indice).
 *
 * Correr:
 *   firebase emulators:exec --only firestore --project demo-places \
 *     "npx jest --forceExit quarantine-trainer-locations"
 */

jest.mock("firebase-functions/v2/firestore", () => ({
  onDocumentWritten: (_opts: unknown, handler: unknown) => handler,
}));

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";

import {
  QUARANTINE_COLLECTION,
  quarantineTrainerLocationLabels,
  quarantineTrainerProfileName,
} from "../moderation/quarantine-vetted-content";

const VETADO = "sos un hijo de puta";
const REVIEW = "sos un pelotudo";

type TriggerHandler = (event: {
  data: { after: FirebaseFirestore.DocumentSnapshot };
  params: { uid: string };
}) => Promise<void>;

let app: App;
let db: Firestore;
let defaultApp: App;

beforeAll(() => {
  app = initializeApp({ projectId: "demo-places" }, "quarantine-locations");
  db = getFirestore(app);
  // El wrapper hace `getFirestore()` sin args: necesita la app default.
  defaultApp = initializeApp({ projectId: "demo-places" });
});

afterAll(async () => {
  await deleteApp(app);
  await deleteApp(defaultApp);
});

afterEach(async () => {
  for (const c of ["trainerPublicProfiles", "users", QUARANTINE_COLLECTION]) {
    const snap = await db.collection(c).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
});

const lugar = (id: string, customLabel: unknown) => ({
  id,
  type: "custom",
  customLabel,
  lat: -34.6,
  lng: -58.4,
});

describe("quarantineTrainerLocationLabels", () => {
  it("redacta SOLO la etiqueta vetada, deja el resto del array y registra el campo", async () => {
    const locations = [lugar("a", "Mi estudio"), lugar("b", VETADO)];
    await db.doc("trainerPublicProfiles/t1").set({ uid: "t1", trainerLocations: locations });

    const findings = await quarantineTrainerLocationLabels({
      db,
      path: "trainerPublicProfiles/t1",
      locations,
      authorUid: "t1",
    });

    expect(findings).toEqual([
      { field: "trainerLocations[1].customLabel", verdict: "block" },
    ]);
    const after = (await db.doc("trainerPublicProfiles/t1").get()).get(
      "trainerLocations",
    );
    expect(after[0]).toEqual(lugar("a", "Mi estudio"));
    expect(after[1]).toEqual(lugar("b", ""));

    const reg = await db
      .collection(QUARANTINE_COLLECTION)
      .doc("trainerPublicProfiles__t1__trainerLocations_1__customLabel")
      .get();
    expect(reg.get("verdict")).toBe("block");
    expect(reg.get("redacted")).toBe(true);
    expect(reg.get("kind")).toBe("profile");
  });

  it("review: registra pero NO redacta", async () => {
    const locations = [lugar("a", REVIEW)];
    await db.doc("trainerPublicProfiles/t2").set({ uid: "t2", trainerLocations: locations });

    const findings = await quarantineTrainerLocationLabels({
      db,
      path: "trainerPublicProfiles/t2",
      locations,
    });

    expect(findings).toEqual([
      { field: "trainerLocations[0].customLabel", verdict: "review" },
    ]);
    const after = (await db.doc("trainerPublicProfiles/t2").get()).get(
      "trainerLocations",
    );
    expect(after[0].customLabel).toBe(REVIEW);
  });

  it("limpias, nulas, vacias, gym legacy y basura no hacen nada ni lanzan", async () => {
    const locations = [lugar("a", "Mi estudio"), lugar("b", null), null, "x", { id: "g", type: "gym" }];
    await db.doc("trainerPublicProfiles/t3").set({ uid: "t3", trainerLocations: [] });

    const findings = await quarantineTrainerLocationLabels({
      db,
      path: "trainerPublicProfiles/t3",
      locations,
    });

    expect(findings).toEqual([]);
    expect((await db.collection(QUARANTINE_COLLECTION).get()).size).toBe(0);
  });

  it("locations ausente o no-array: no hace nada", async () => {
    expect(
      await quarantineTrainerLocationLabels({
        db,
        path: "trainerPublicProfiles/t4",
        locations: undefined,
      }),
    ).toEqual([]);
  });

  it("segunda pasada sobre el doc ya redactado no escribe nada (sin bucle)", async () => {
    const locations = [lugar("a", "")];
    await db.doc("trainerPublicProfiles/t5").set({ uid: "t5", trainerLocations: locations });
    const antes = (await db.doc("trainerPublicProfiles/t5").get()).updateTime;

    await quarantineTrainerLocationLabels({ db, path: "trainerPublicProfiles/t5", locations });

    expect((await db.doc("trainerPublicProfiles/t5").get()).updateTime).toEqual(antes);
  });
});

describe("quarantineTrainerProfileName (wrapper real) con etiquetas", () => {
  it("redacta la etiqueta vetada aunque bio y displayName tambien lo esten, en la primera pasada", async () => {
    await db.doc("users/abcdef123").set({ uid: "abcdef123", displayName: VETADO });
    await db.doc("trainerPublicProfiles/abcdef123").set({
      uid: "abcdef123",
      displayName: VETADO,
      trainerBio: VETADO,
      trainerLocations: [lugar("a", VETADO)],
    });
    const snap = await db.doc("trainerPublicProfiles/abcdef123").get();

    await (quarantineTrainerProfileName as unknown as TriggerHandler)({
      data: { after: snap },
      params: { uid: "abcdef123" },
    });

    const after = await db.doc("trainerPublicProfiles/abcdef123").get();
    expect(after.get("displayName")).toBe("usuario_abcdef");
    expect(after.get("trainerBio")).toBe("");
    expect(after.get("trainerLocations")[0].customLabel).toBe("");
  });
});
