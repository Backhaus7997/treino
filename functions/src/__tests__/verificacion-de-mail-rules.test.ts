/**
 * verificacion-de-mail-rules.test.ts — nadie se marca verificado sin el código.
 *
 * EMULADOR (Firestore). Corre como el job `functions-test`:
 *
 *   firebase emulators:exec --only firestore,auth,storage --project treino-dev \
 *     "npm --prefix functions test -- --runInBand verificacion-de-mail-rules"
 *
 * `users/{uid}.mailVerificadoAt` es la llave de la pantalla del código, y la
 * pantalla es la que obliga a abrir el mail que explica cómo se paga. Si el
 * dueño del documento pudiera escribirse ese campo, el código sería decorativo.
 * Y `verificaciones_de_mail` guarda el hash, los intentos y el vencimiento: leer
 * o escribir ahí es saltearse el mismo paso por otro lado.
 *
 * El host sale de `FIRESTORE_EMULATOR_HOST` —lo exporta `emulators:exec`, que
 * puede elegir otro puerto si el 8080 está tomado—, con 8080 de respaldo.
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
import firebase from "firebase/compat/app";
import "firebase/compat/firestore";

const PROJECT_ID = "treino-rules-test";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");
const [HOST, PUERTO] = (process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080").split(":");

const UID = "alumna-verificacion";
const MARCA = firebase.firestore.Timestamp.fromMillis(Date.parse("2026-10-01T12:00:00.000Z"));

/**
 * Un usuario como los que siembra `users-subscription-rules.test.ts`: las
 * reglas de update leen `email` y `createdAt`, y sin ellos el control positivo
 * fallaria por la semilla y no por el pin.
 */
const USUARIO = { uid: UID, role: "athlete", email: `${UID}@example.test`, createdAt: 0, displayName: "Ana" };

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  setLogLevel("error");
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: HOST,
      port: Number(PUERTO),
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

async function sembrar(col: string, id: string, data: Record<string, unknown>) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection(col).doc(id).set(data);
  });
}

const comoElDueno = () => testEnv.authenticatedContext(UID).firestore();

describe("users.mailVerificadoAt — lo escribe solo la Cloud Function", () => {
  it("el dueño NO puede crearse el documento ya verificado", async () => {
    await assertFails(
      comoElDueno().collection("users").doc(UID).set({
        uid: UID,
        role: "athlete",
        mailVerificadoAt: MARCA,
      }),
    );
  });

  it("control: el mismo alta sin el campo sí pasa (el rechazo de arriba es por el pin)", async () => {
    await assertSucceeds(
      comoElDueno().collection("users").doc(UID).set({ uid: UID, role: "athlete" }),
    );
  });

  it("el dueño NO puede marcarse verificado después", async () => {
    await sembrar("users", UID, USUARIO);

    await assertFails(
      comoElDueno().collection("users").doc(UID).update({ mailVerificadoAt: MARCA }),
    );
  });

  it("tampoco puede tocar la marca una vez puesta", async () => {
    await sembrar("users", UID, { ...USUARIO, mailVerificadoAt: MARCA });

    await assertFails(
      comoElDueno().collection("users").doc(UID).update({
        mailVerificadoAt: firebase.firestore.FieldValue.delete(),
      }),
    );
  });

  it("con la marca puesta sigue pudiendo editar su perfil", async () => {
    await sembrar("users", UID, { ...USUARIO, mailVerificadoAt: MARCA });

    await assertSucceeds(
      comoElDueno().collection("users").doc(UID).update({ displayName: "Anita" }),
    );
  });
});

describe("verificaciones_de_mail — cerrada entera", () => {
  it("el dueño no puede leer su código (ni el hash, ni los intentos)", async () => {
    await sembrar("verificaciones_de_mail", UID, { codigoHash: "x", intentos: 0, venceMs: 1 });

    await assertFails(comoElDueno().collection("verificaciones_de_mail").doc(UID).get());
  });

  it("ni escribirse uno propio", async () => {
    await assertFails(
      comoElDueno().collection("verificaciones_de_mail").doc(UID).set({
        codigoHash: "puesto-por-mi",
        intentos: 0,
        venceMs: Date.now() + 60_000,
      }),
    );
  });
});
