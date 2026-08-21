/**
 * Firestore security-rules tests for `routines` — el `list` NO puede filtrarse.
 *
 * POR QUE EXISTE ESTE ARCHIVO. El `allow read` de routines tenia el disyunto
 * `!('visibility' in resource.data)` para cubrir docs legacy sin el campo. En
 * un `get` funcionaba bien. En un `list` abria la coleccion ENTERA:
 *
 *     get  de la rutina privada de otro alumno  -> DENEGADO   (parecia sano)
 *     list collection('routines').get()         -> PERMITIDO, devolvia todo
 *
 * Motivo: en una operacion de `list`, el motor de reglas NO evalua por
 * documento una prueba de EXISTENCIA de campo (`'x' in resource.data`); la
 * toma como posiblemente verdadera y permite la query completa. Se expone el
 * plan de entrenamiento de cualquiera y, peor, el grafo assignedBy/assignedTo
 * de toda la plataforma.
 *
 * El bug fue INVISIBLE durante toda su vida porque las unicas pruebas eran
 * `get`, y el `get` estaba bien. Lo encontro un control NEGATIVO —un
 * `assertFails` sobre un `list`— no una asercion positiva. De ahi la forma de
 * este archivo: cada caso legitimo viene con su contraparte denegada.
 *
 * REGLA QUE ESTE ARCHIVO DEFIENDE, y que vale para CUALQUIER `allow read`:
 *   una prueba de existencia de campo sobre `resource.data` en una clausula de
 *   lectura equivale a permitir el `list` de toda la coleccion. Si hace falta
 *   un default para docs legacy, va `.get(campo, default)`, que es total.
 *
 * Corre contra el emulador de Firestore. Recuerda que SI se puede correr local:
 *   export JAVA_HOME="C:\\Program Files\\Android\\Android Studio\\jbr"
 *   firebase emulators:exec --only firestore,auth,storage \
 *     "npm --prefix functions test -- --runInBand routines-list-leak"
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
const ATHLETE = "athlete-uid";
const OUTSIDER = "outsider-uid";

const PRIVATE_ID = "routine-private";
const LEGACY_ID = "routine-legacy-sin-visibility";
const PUBLIC_ID = "routine-public-system";
const SHARED_ID = "routine-shared";

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

    await db.collection("routines").doc(PRIVATE_ID).set({
      name: "Plan de fuerza — mesociclo 2",
      assignedBy: TRAINER,
      assignedTo: ATHLETE,
      createdBy: TRAINER,
      source: "trainer-assigned",
      visibility: "private",
    });

    // Doc legacy: SIN el campo `visibility`. Es el que motivaba el disyunto
    // roto, y el que ahora tiene que quedar privado por default.
    await db.collection("routines").doc(LEGACY_ID).set({
      name: "Rutina vieja sin campo visibility",
      assignedBy: TRAINER,
      assignedTo: ATHLETE,
      createdBy: TRAINER,
      source: "trainer-assigned",
    });

    await db.collection("routines").doc(PUBLIC_ID).set({
      name: "Full Body para principiantes",
      assignedBy: null,
      assignedTo: null,
      createdBy: "system",
      source: "system",
      visibility: "public",
    });

    await db.collection("routines").doc(SHARED_ID).set({
      name: "Plantilla compartida",
      assignedBy: TRAINER,
      assignedTo: null,
      createdBy: TRAINER,
      source: "trainer-template",
      visibility: "shared",
    });
  });
});

const dbFor = (uid: string): FirebaseFirestore.Firestore =>
  testEnv.authenticatedContext(uid).firestore() as unknown as FirebaseFirestore.Firestore;

describe("routines — el list no filtra nada a un tercero", () => {
  it("un tercero NO puede listar la coleccion entera", async () => {
    // ESTE es el assert que el bug hacia pasar. Sin el fix devolvia 4 docs.
    await assertFails(dbFor(OUTSIDER).collection("routines").get());
  });

  it("un tercero NO puede listar por assignedTo (apuntando a un alumno)", async () => {
    await assertFails(
      dbFor(OUTSIDER)
        .collection("routines")
        .where("assignedTo", "==", ATHLETE)
        .get(),
    );
  });

  it("un tercero NO puede listar por assignedBy (cosechando la cartera de un PF)", async () => {
    await assertFails(
      dbFor(OUTSIDER)
        .collection("routines")
        .where("assignedBy", "==", TRAINER)
        .get(),
    );
  });

  it("un tercero NO puede leer por id ni la privada ni la legacy", async () => {
    await assertFails(dbFor(OUTSIDER).collection("routines").doc(PRIVATE_ID).get());
    // La legacy es el unico cambio de comportamiento del fix: antes la leia
    // cualquiera por el disyunto de existencia de campo. Ahora falla cerrado.
    await assertFails(dbFor(OUTSIDER).collection("routines").doc(LEGACY_ID).get());
  });
});

describe("routines — lo legitimo sigue funcionando", () => {
  it("el alumno lee su rutina privada, y tambien la legacy", async () => {
    const priv = await assertSucceeds(
      dbFor(ATHLETE).collection("routines").doc(PRIVATE_ID).get(),
    );
    expect(priv.exists).toBe(true);
    expect(priv.data()?.name).toBe("Plan de fuerza — mesociclo 2");

    // Sin campo `visibility`, pero entra por la rama assignedTo: el fix no le
    // saca nada al dueño del dato.
    const legacy = await assertSucceeds(
      dbFor(ATHLETE).collection("routines").doc(LEGACY_ID).get(),
    );
    expect(legacy.exists).toBe(true);
  });

  it("el alumno lista SUS rutinas por assignedTo", async () => {
    const snap = await assertSucceeds(
      dbFor(ATHLETE)
        .collection("routines")
        .where("assignedTo", "==", ATHLETE)
        .get(),
    );
    expect(snap.docs.map((d) => d.id).sort()).toEqual(
      [LEGACY_ID, PRIVATE_ID].sort(),
    );
  });

  it("el PF lista las que asigno, por assignedBy", async () => {
    const snap = await assertSucceeds(
      dbFor(TRAINER)
        .collection("routines")
        .where("assignedBy", "==", TRAINER)
        .get(),
    );
    expect(snap.size).toBeGreaterThanOrEqual(2);
  });

  it("cualquiera lee el catalogo publico, con la query REAL de la app", async () => {
    // routine_repository.dart:34-37 — source == 'system' && visibility == 'public'.
    const snap = await assertSucceeds(
      dbFor(OUTSIDER)
        .collection("routines")
        .where("source", "==", "system")
        .where("visibility", "==", "public")
        .get(),
    );
    expect(snap.docs.map((d) => d.id)).toEqual([PUBLIC_ID]);
  });

  it("cualquiera lee una rutina 'shared' por id", async () => {
    await assertSucceeds(dbFor(OUTSIDER).collection("routines").doc(SHARED_ID).get());
  });
});

describe("routines — el guard de existencia sigue vivo", () => {
  it("un get sobre un id INEXISTENTE devuelve vacio en vez de explotar", async () => {
    // Regresion documentada en firestore.rules: sin el disyunto `resource ==
    // null`, getById() de una rutina borrada TIRA en vez de devolver null, y
    // eso dejaba en blanco los radares de distribucion muscular. El fix no
    // toca esa rama, pero si alguien la saca "de paso", esto se pone rojo.
    const snap = await assertSucceeds(
      dbFor(OUTSIDER).collection("routines").doc("no-existe-este-id").get(),
    );
    expect(snap.exists).toBe(false);
  });
});
