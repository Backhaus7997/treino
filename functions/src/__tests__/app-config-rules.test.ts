/**
 * app-config-rules.test.ts — el interruptor del gate del mail lo lee la app y
 * lo escribe solo el equipo.
 *
 * EMULADOR (Firestore). Corre como el job `functions-test`:
 *
 *   firebase emulators:exec --only firestore,auth,storage --project treino-dev \
 *     "npm --prefix functions test -- --runInBand app-config-rules"
 *
 * `app_config/email_gate` decide si la app obliga a confirmar el mail con el
 * código. Lo lee `emailGateEnabledProvider` con la sesión abierta. Si un cliente
 * pudiera escribirlo, cualquiera apagaría el gate para todos; si pudiera leerlo
 * sin sesión, la app lo abriría antes del login y recibiría un permission-denied
 * que el provider no reintenta (por eso depende del uid). La regla es ese
 * documento y nada más: listar `app_config` o leer otro documento queda cerrado,
 * para que lo que se guarde ahí mañana no nazca legible por todos.
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

const PROJECT_ID = "treino-rules-test";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");
const [HOST, PUERTO] = (process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080").split(":");

const UID = "alumna-interruptor";

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

const conSesion = () => testEnv.authenticatedContext(UID).firestore();
const sinSesion = () => testEnv.unauthenticatedContext().firestore();

describe("app_config/email_gate — lectura con sesión, escritura de nadie", () => {
  it("con sesión se puede leer el interruptor", async () => {
    await sembrar("app_config", "email_gate", { enabled: true });

    await assertSucceeds(conSesion().collection("app_config").doc("email_gate").get());
  });

  it("con sesión se puede ESCUCHAR el documento (es lo que hace la app)", async () => {
    await sembrar("app_config", "email_gate", { enabled: true });
    const ref = conSesion().collection("app_config").doc("email_gate");

    const datos = await new Promise<unknown>((resolve, reject) => {
      const baja = ref.onSnapshot(
        (snap) => {
          baja();
          resolve(snap.data());
        },
        (err) => {
          baja();
          reject(err);
        },
      );
    });

    expect(datos).toEqual({ enabled: true });
  });

  it("con sesión también se lee si el documento todavía no existe (gate apagado)", async () => {
    await assertSucceeds(conSesion().collection("app_config").doc("email_gate").get());
  });

  it("sin sesión NO se puede leer", async () => {
    await sembrar("app_config", "email_gate", { enabled: true });

    await assertFails(sinSesion().collection("app_config").doc("email_gate").get());
  });

  it("con sesión NO se puede listar la colección", async () => {
    await sembrar("app_config", "email_gate", { enabled: true });

    await assertFails(conSesion().collection("app_config").get());
  });

  it("con sesión NO se puede leer otro documento de app_config", async () => {
    await sembrar("app_config", "otro", { enabled: true });

    await assertFails(conSesion().collection("app_config").doc("otro").get());
  });

  it("ni escribir otro documento de app_config", async () => {
    await assertFails(conSesion().collection("app_config").doc("otro").set({ enabled: true }));
  });

  it("un cliente con sesión NO puede crearlo", async () => {
    await assertFails(
      conSesion().collection("app_config").doc("email_gate").set({ enabled: true }),
    );
  });

  it("ni cambiarlo", async () => {
    await sembrar("app_config", "email_gate", { enabled: true });

    await assertFails(
      conSesion().collection("app_config").doc("email_gate").update({ enabled: false }),
    );
  });

  it("ni borrarlo", async () => {
    await sembrar("app_config", "email_gate", { enabled: true });

    await assertFails(conSesion().collection("app_config").doc("email_gate").delete());
  });
});
