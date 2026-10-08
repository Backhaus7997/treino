/**
 * Reglas de `retention_notices` — el registro de la baja automática.
 *
 * `sweepInactiveAccounts` escribe acá a quién se le avisó a los 24 meses de
 * inactividad y cuándo. Vía Admin SDK, que saltea estas reglas; ningún cliente
 * la toca, ni para leer.
 *
 * ─── Por qué esto es un test y no una regla ─────────────────────────────────
 *
 * El `allow read, write: if false` de `firestore.rules` NO protege esta
 * colección: las reglas de Firestore son UNIÓN PERMISIVA, así que un `match`
 * comodín que alguien agregue mañana le gana al deny. Está medido sobre las
 * `mp_*` (ver el encabezado de `mp-collections-rules.test.ts`): sacando las
 * reglas los tests siguen verdes, y agregando un comodín con las reglas puestas
 * caen igual. El deny explícito es documentación. **Este archivo es la única
 * protección real.**
 *
 * ─── Qué está en juego, y por qué el `{uid}` del dueño no es una excepción ──
 *
 * `noticeSentAt` es lo ÚNICO que habilita borrar una cuenta a los 36 meses: el
 * barrido nunca borra sin un aviso previo REGISTRADO. Un cliente con escritura
 * sobre su propio documento se auto-antedataría el aviso y adelantaría su
 * propia baja sin haber recibido nada — y si el `{uid}` no estuviera cerrado,
 * la de cualquier otro. Es una escalada a borrado de cuenta ajena por una
 * escritura de dos campos.
 *
 * La lectura tampoco corresponde. El canal del aviso es el correo; un `list`
 * abierto sería el padrón de quién está por ser dado de baja.
 *
 * Corre contra el emulador de Firestore:
 *   firebase emulators:exec --only firestore,auth,storage \
 *     "npm --prefix functions test -- --runInBand retention-notices-rules"
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

const COL = "retention_notices";
/** El dueño del documento: la cuenta a la que se le avisó. */
const AVISADO = "atleta-avisado";
const OTRO = "otro-atleta";

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
  // Admin SDK en producción.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection(COL).doc(AVISADO).set({
      noticeSentAt: new Date("2026-09-14T08:00:00.000Z"),
      lastSeenAt: new Date("2024-09-14T08:00:00.000Z"),
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

describe("retention_notices — lectura", () => {
  it("EL PROPIO DUEÑO no puede leer su documento", async () => {
    // La aserción que hay que leer despacio. No es un tercero: es el uid del
    // documento. No existe ninguna pantalla que necesite esto — el aviso llega
    // por mail, no por Firestore.
    await assertFails(dbDe(AVISADO).collection(COL).doc(AVISADO).get());
  });

  it("otro atleta tampoco", async () => {
    await assertFails(dbDe(OTRO).collection(COL).doc(AVISADO).get());
  });

  it("un anónimo tampoco", async () => {
    await assertFails(anonimo().collection(COL).doc(AVISADO).get());
  });

  it("el LISTADO tampoco — sería el padrón de quién está por ser dado de baja", async () => {
    // El `get` y el `list` son permisos distintos y se escapan por caminos
    // distintos: el leak de rutinas (#717) salió justo por el que nadie probó.
    await assertFails(dbDe(AVISADO).collection(COL).get());
    await assertFails(anonimo().collection(COL).get());
  });
});

describe("retention_notices — escritura", () => {
  it("el dueño NO puede antedatarse el aviso", async () => {
    // El vector: `noticeSentAt` viejo + 36 meses de inactividad = baja. Si el
    // dueño pudiera escribir esto, podría adelantar su propia baja sin haber
    // recibido ningún aviso. Y con el `{uid}` abierto, la de cualquiera.
    await assertFails(
      dbDe(AVISADO).collection(COL).doc(AVISADO).update({
        noticeSentAt: new Date("2020-01-01T00:00:00.000Z"),
      }),
    );
  });

  it("tampoco por set, ni por merge", async () => {
    const col = dbDe(AVISADO).collection(COL);
    await assertFails(
      col.doc(AVISADO).set({ noticeSentAt: new Date("2020-01-01") }),
    );
    await assertFails(
      col.doc(AVISADO).set(
        { noticeSentAt: new Date("2020-01-01") },
        { merge: true },
      ),
    );
  });

  it("un tercero no puede plantarle un aviso a otro", async () => {
    await assertFails(
      dbDe(OTRO).collection(COL).doc(AVISADO).update({
        noticeSentAt: new Date("2020-01-01T00:00:00.000Z"),
      }),
    );
    await assertFails(
      dbDe(OTRO).collection(COL).doc("victima").set({
        noticeSentAt: new Date("2020-01-01T00:00:00.000Z"),
        lastSeenAt: new Date("2020-01-01T00:00:00.000Z"),
      }),
    );
  });

  it("nadie crea un documento nuevo, ni con su propio uid", async () => {
    await assertFails(
      dbDe(OTRO).collection(COL).doc(OTRO).set({
        noticeSentAt: new Date("2020-01-01T00:00:00.000Z"),
      }),
    );
    await assertFails(
      anonimo().collection(COL).doc("inventado").set({ noticeSentAt: new Date() }),
    );
  });

  it("BORRAR tampoco — sería borrar la prueba de que se avisó", async () => {
    // El otro lado del mismo vector, y el más fácil de pasar por alto: el
    // documento no sólo habilita la baja, también es el único registro de que
    // el aviso salió. Borrarlo no protege al usuario: lo devuelve a la cola de
    // avisos y le reinicia el plazo desde cero, que es ruido, no seguridad.
    await assertFails(dbDe(AVISADO).collection(COL).doc(AVISADO).delete());
    await assertFails(dbDe(OTRO).collection(COL).doc(AVISADO).delete());
  });
});
