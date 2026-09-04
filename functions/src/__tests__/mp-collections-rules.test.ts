/**
 * Reglas de las dos colecciones del cobro con Mercado Pago.
 *
 * `mp_checkouts` y `mp_preapprovals` las escribe SOLO el Admin SDK, desde
 * `createPreapproval` y `reconcileMpSubscriptions`. Ningún cliente las toca.
 *
 * ── ESTE ARCHIVO ES LA ÚNICA PROTECCIÓN REAL, y está medido ──
 *
 * El deny explícito de `firestore.rules` no protege: es documentación. Las dos
 * mutaciones que lo prueban:
 *
 *   - Sacando las dos reglas de `firestore.rules`, este archivo sigue en 12/12
 *     verde. El default-deny ya denegaba, porque ningún match comodín las
 *     alcanza. O sea que la regla no agrega enforcement.
 *   - Agregando `match /{x=**} { allow read: if request.auth != null }` CON las
 *     reglas puestas, caen 5 de estos tests. El `if false` NO lo frenó.
 *
 * Lo segundo es contraintuitivo y vale tenerlo claro: las reglas de Firestore
 * son UNIÓN PERMISIVA. Si algún match permite, se permite — un deny no le gana
 * a un allow. Escribir `if false` no blinda una colección contra un comodín
 * futuro.
 *
 * Por eso estos tests no son ceremonia sobre una regla que ya existe: son el
 * único mecanismo que avisa si alguien abre estas colecciones sin querer. Es
 * también la diferencia con `mail_queue`, que tiene la regla y no tiene test.
 *
 * ── Lo que está en juego, y no es lo mismo en las dos ──
 *
 * `mp_checkouts/{uid}` guarda el `init_point`: un LINK DE PAGO vivo. Leerlo
 * expone qué está comprando cada entrenador y la URL para completarlo.
 * ESCRIBIRLO es peor: la función reusa ese link dentro de su ventana de 30
 * minutos, así que plantar un `initPoint` propio manda al PF a pagarle a un
 * tercero desde nuestra app.
 *
 * `mp_preapprovals/{id}` es el mapeo suscripción → (PF, plan). El reconciliador
 * lee de acá para saber qué límite otorgar: un cliente con escritura se firma
 * `plan3` gratis.
 *
 * Corre contra el emulador de Firestore:
 *   firebase emulators:exec --only firestore,auth,storage \
 *     "npm --prefix functions test -- --runInBand mp-collections-rules"
 */

import * as fs from "fs";
import * as path from "path";
import {
  assertFails,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { setLogLevel } from "firebase/firestore";
import firebase from "firebase/compat/app";
import "firebase/compat/firestore";

const PROJECT_ID = "treino-rules-test";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const TRAINER = "trainer-mp";
const OTRO = "otro-pf";
const PREAPPROVAL = "2c938084";

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

beforeEach(async () => {
  await testEnv.clearFirestore();

  // Se siembra con el contexto privilegiado, que es exactamente lo que hace el
  // Admin SDK en produccion: saltea las reglas.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection("mp_checkouts").doc(TRAINER).set({
      preapprovalId: PREAPPROVAL,
      tier: "plan2",
      cycle: "monthly",
      initPoint: "https://www.mercadopago.com.ar/subscriptions/checkout?pref_id=x",
      createdAtMs: 1_000_000,
    });
    await db.collection("mp_preapprovals").doc(PREAPPROVAL).set({
      uid: TRAINER,
      tier: "plan2",
      cycle: "monthly",
    });
  });
});

const dbDe = (uid: string): firebase.firestore.Firestore =>
  testEnv.authenticatedContext(uid).firestore() as unknown as
    firebase.firestore.Firestore;

const anonimo = (): firebase.firestore.Firestore =>
  testEnv.unauthenticatedContext().firestore() as unknown as
    firebase.firestore.Firestore;

// ---------------------------------------------------------------------------

describe("mp_checkouts — el init_point es un link de pago vivo", () => {
  it("su propio dueño NO puede leerlo", async () => {
    // Ni siquiera el dueño: no hay ninguna pantalla que necesite leer esto —
    // el callable le devuelve el init_point en la respuesta, no por Firestore.
    await assertFails(
      dbDe(TRAINER).collection("mp_checkouts").doc(TRAINER).get(),
    );
  });

  it("otro entrenador tampoco — vería qué está comprando", async () => {
    await assertFails(
      dbDe(OTRO).collection("mp_checkouts").doc(TRAINER).get(),
    );
  });

  it("un anónimo tampoco", async () => {
    await assertFails(
      anonimo().collection("mp_checkouts").doc(TRAINER).get(),
    );
  });

  it("el LISTADO tampoco — sería el padrón de quién está pagando", async () => {
    // El leak de rutinas (#717) enseño que un `list` abierto se escapa por un
    // camino distinto que el `get`, y hay que probar los dos.
    await assertFails(dbDe(TRAINER).collection("mp_checkouts").get());
  });

  it("NADIE puede escribir un initPoint propio — es el vector más caro", async () => {
    // La función reusa el link guardado dentro de su ventana de 30 minutos.
    // Plantar uno mandaría al PF a pagarle a un tercero desde nuestra app.
    await assertFails(
      dbDe(TRAINER).collection("mp_checkouts").doc(TRAINER).set({
        preapprovalId: PREAPPROVAL,
        tier: "plan2",
        cycle: "monthly",
        initPoint: "https://atacante.com/cobrame",
        createdAtMs: 1_000_000,
      }),
    );
  });

  it("tampoco por update, ni por merge, ni creando uno nuevo", async () => {
    const col = dbDe(TRAINER).collection("mp_checkouts");
    await assertFails(
      col.doc(TRAINER).update({ initPoint: "https://atacante.com" }),
    );
    await assertFails(
      col.doc(TRAINER).set({ initPoint: "https://atacante.com" }, { merge: true }),
    );
    await assertFails(col.doc("inventado").set({ initPoint: "https://x" }));
    await assertFails(col.doc(TRAINER).delete());
  });
});

describe("mp_preapprovals — escribir acá es elegirse el plan", () => {
  it("nadie lo lee: ni el dueño, ni un tercero, ni un anónimo", async () => {
    const p = (db: firebase.firestore.Firestore) =>
      db.collection("mp_preapprovals").doc(PREAPPROVAL).get();
    await assertFails(p(dbDe(TRAINER)));
    await assertFails(p(dbDe(OTRO)));
    await assertFails(p(anonimo()));
  });

  it("el listado tampoco", async () => {
    await assertFails(dbDe(TRAINER).collection("mp_preapprovals").get());
  });

  it("nadie se puede firmar un plan3 gratis", async () => {
    // El reconciliador lee de acá para saber qué límite otorgar. Con escritura,
    // el tier lo elige el cliente.
    await assertFails(
      dbDe(TRAINER).collection("mp_preapprovals").doc(PREAPPROVAL).set({
        uid: TRAINER,
        tier: "plan3",
        cycle: "annual",
      }),
    );
  });

  it("ni robarle la suscripción a otro apuntándola a su propio uid", async () => {
    await assertFails(
      dbDe(OTRO).collection("mp_preapprovals").doc(PREAPPROVAL).update({
        uid: OTRO,
      }),
    );
  });

  it("ni crear un mapeo inventado, ni borrar el que existe", async () => {
    const col = dbDe(TRAINER).collection("mp_preapprovals");
    await assertFails(
      col.doc("inventado").set({ uid: TRAINER, tier: "plan3", cycle: "annual" }),
    );
    // Borrar el mapeo obliga al reconciliador a caer al fallback por monto, que
    // logea warn — ruido, y un paso más cerca de que no se pueda determinar el
    // plan.
    await assertFails(col.doc(PREAPPROVAL).delete());
  });
});

describe("el Admin SDK sí puede — si no, las Cloud Functions no andarían", () => {
  it("el contexto privilegiado escribe y lee las dos colecciones", async () => {
    // El complemento necesario de todo lo de arriba: un deny que también
    // bloquee al servidor rompería el cobro entero, y los tests de arriba no lo
    // notarían.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection("mp_checkouts").doc(TRAINER).set({ initPoint: "ok" });
      await db.collection("mp_preapprovals").doc(PREAPPROVAL).set({
        uid: TRAINER, tier: "plan1", cycle: "monthly",
      });
      const a = await db.collection("mp_checkouts").doc(TRAINER).get();
      const b = await db.collection("mp_preapprovals").doc(PREAPPROVAL).get();
      expect(a.exists).toBe(true);
      expect(b.data()?.tier).toBe("plan1");
    });
  });
});
