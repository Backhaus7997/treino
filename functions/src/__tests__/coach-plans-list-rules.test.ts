/**
 * Firestore security-rules tests for the Coach Hub assigned-routines list.
 *
 * POR QUE EXISTE ESTE ARCHIVO. Firestore authorises a `list` only when the
 * query is demonstrably a subset of an `allow read` branch. The athlete query
 * proves `request.auth.uid == assignedTo`; the trainer must additionally
 * constrain `assignedBy` to their own uid. Filtering that field afterwards in
 * Dart is too late because Firestore rejects the complete query first.
 *
 * Every legitimate query below has negative controls. They pin that adding
 * `assignedBy` fixes the Coach Hub without making another trainer's portfolio,
 * another athlete's plans, or the complete collection enumerable.
 */

import * as fs from "fs";
import * as path from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { setLogLevel } from "firebase/firestore";

const PROJECT_ID = "treino-rules-test";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const TRAINER = "trainer-uid";
const OTHER_TRAINER = "other-trainer-uid";
const ATHLETE = "athlete-uid";
const OUTSIDER = "outsider-uid";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  setLogLevel("error");
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

beforeEach(async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection("routines").doc("trainer-plan").set({
      name: "Plan del entrenador",
      assignedBy: TRAINER,
      assignedTo: ATHLETE,
      createdBy: TRAINER,
      source: "trainer-assigned",
      visibility: "private",
    });
    await db.collection("routines").doc("other-trainer-plan").set({
      name: "Plan de otro entrenador",
      assignedBy: OTHER_TRAINER,
      assignedTo: ATHLETE,
      createdBy: OTHER_TRAINER,
      source: "trainer-assigned",
      visibility: "private",
    });
  });
});

const dbFor = (uid: string): FirebaseFirestore.Firestore =>
  testEnv.authenticatedContext(uid).firestore() as unknown as FirebaseFirestore.Firestore;

describe("routines — list del Coach Hub", () => {
  it("el PF lista sólo sus planes para el alumno", async () => {
    const snap = await assertSucceeds(
      dbFor(TRAINER)
        .collection("routines")
        .where("assignedTo", "==", ATHLETE)
        .where("assignedBy", "==", TRAINER)
        .where("source", "==", "trainer-assigned")
        .get(),
    );
    expect(snap.docs.map((doc) => doc.id)).toEqual(["trainer-plan"]);
  });

  it("el alumno sigue listando sus planes asignados", async () => {
    const snap = await assertSucceeds(
      dbFor(ATHLETE)
        .collection("routines")
        .where("assignedTo", "==", ATHLETE)
        .where("source", "==", "trainer-assigned")
        .get(),
    );
    expect(snap.size).toBe(2);
  });

  it("la query vieja del PF sigue denegada sin assignedBy", async () => {
    await assertFails(
      dbFor(TRAINER)
        .collection("routines")
        .where("assignedTo", "==", ATHLETE)
        .where("source", "==", "trainer-assigned")
        .get(),
    );
  });

  it("un PF no puede listar la cartera de otro PF", async () => {
    await assertFails(
      dbFor(TRAINER)
        .collection("routines")
        .where("assignedTo", "==", ATHLETE)
        .where("assignedBy", "==", OTHER_TRAINER)
        .where("source", "==", "trainer-assigned")
        .get(),
    );
  });

  it("un tercero no puede listar los planes de un alumno ajeno", async () => {
    await assertFails(
      dbFor(OUTSIDER)
        .collection("routines")
        .where("assignedTo", "==", ATHLETE)
        .where("source", "==", "trainer-assigned")
        .get(),
    );
  });

  it("un tercero no puede listar la colección completa", async () => {
    await assertFails(dbFor(OUTSIDER).collection("routines").get());
  });
});
