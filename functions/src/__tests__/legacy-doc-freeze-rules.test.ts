/**
 * #849 — un chequeo de RANGO o TIPO incondicional en un `update` congela el
 * documento.
 *
 * EL PATRON
 * ---------
 * Una funcion de forma compartida por `create` y `update` corre sobre
 * `request.resource.data`, que en un update es el documento RESULTANTE: el
 * merge de un `set(merge:true)`, o el modelo entero que el cliente rearmo
 * releyendo el doc en un `set()` completo. En los dos casos un valor legacy
 * fuera de rango se vuelve a presentar en CADA escritura posterior, asi que la
 * cota lo rechaza para siempre. Si ademas el bloque tiene
 * `allow delete: if false`, el documento queda imborrable.
 *
 * Es el mismo error que en `appointments` se cometio cuatro veces (#831), y
 * la doctrina esta en `docs/security.md` §1.8: los chequeos de FORMA
 * (`keys().hasOnly()`, `keys().hasAll()`) van incondicionales; los de RANGO y
 * TIPO van condicionados a que el campo CAMBIE.
 *
 * Las cotas de LARGO DE TEXTO no son chequeos de forma: dependen del valor
 * historico igual que las de rango, y congelan igual. En este PR quedaron
 * incondicionales igual, por un motivo distinto que esta escrito en
 * `measurementShapeOk` — la congelacion es diagnosticable y reparable por el
 * dueno. Es la parte de QA-SEC-017 que queda ABIERTA (§4.14).
 *
 * QUE MIDE ESTE ARCHIVO
 * ---------------------
 * Por cada coleccion arreglada, dos mitades que se necesitan mutuamente:
 *
 *   1. EL CASO LEGACY — un doc sembrado con `withSecurityRulesDisabled` con el
 *      valor fuera de rango tiene que poder actualizarse. Estos casos FALLAN
 *      contra el ruleset pre-fix: ahi la escritura se denegaba.
 *   2. LA CUSTODIA DEL GATE — una escritura que CAMBIA el valor a uno invalido
 *      tiene que seguir denegada, y el `create` no se afloja. Sin esta mitad,
 *      "arreglar" el bug seria indistinguible de borrar el gate.
 *
 * Y una tercera clase de fila, con una sola instancia:
 *
 *   3. EL TRADEOFF — una escritura que el fix ENTREGA. No es un caso legacy
 *      neutro ni una custodia: es superficie que antes estaba denegada y
 *      ahora no. Va con nombre propio para que nadie la lea como un ALLOW
 *      inocente. Ver "TRADEOFF: el opt-in false->true".
 *
 * MUTACION POR GATE (§1.8, punto 1)
 * ---------------------------------
 * Los negativos de la mitad 2 se validaron aflojando cada CONJUNTO del bloque
 * de a uno, no solo el disyunto que toca el fix. Ver el reporte del PR.
 *
 * Corre contra el emulador de Firestore (Java 21):
 *   npm --prefix functions run test:rules:emulator
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

const PROJECT_ID = "treino-rules-test-849";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const OWNER = "owner-849";
const TRAINER = "trainer-849";
const ATHLETE = "athlete-849";
const DOC = "doc-849";

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

function db(uid: string) {
  return testEnv.authenticatedContext(uid).firestore();
}

/** Siembra saltando las reglas: es la unica forma de fabricar un doc legacy. */
async function seed(
  collection: string,
  docId: string,
  data: Record<string, unknown>,
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection(collection).doc(docId).set(data);
  });
}

async function seedRole(uid: string, role: "trainer" | "athlete"): Promise<void> {
  await seed("users", uid, { uid, role });
}

// ─────────────────────────────────────────────────────────────────────────────
// userPublicProfiles — CRITICO: `allow delete: if false` + metricas PINEADAS.
// Un doc congelado aca no se puede reparar NI borrar: queda muerto para
// siempre. Los writers reales son todos `set(merge:true)` parciales
// (`user_public_profile_repository.dart:92,116,131,140,150,160,278`).
// ─────────────────────────────────────────────────────────────────────────────
describe("userPublicProfiles: un doc legacy fuera de rango sigue siendo editable", () => {
  /** El doc que `users/{uid}` necesita para el pin de gymId via getAfter(). */
  async function seedOwner(extra: Record<string, unknown>): Promise<void> {
    await seed("users", OWNER, { uid: OWNER });
    await seed("userPublicProfiles", OWNER, {
      uid: OWNER,
      displayName: "Antes",
      ...extra,
    });
  }

  // `bestSquatKg` sale de `familyMaxWeight` (ranking-aggregate.ts:95), que NO
  // acota, corre con Admin SDK (saltea estas reglas) y lee setLogs que no
  // tuvieron tope hasta `kMaxWeightKg = 500` (2026-07-20). Entre 2026-07-03 y
  // 2026-07-06 ademas lo escribia el cliente sin cota ninguna.
  it("bestSquatKg legacy por encima del tope no bloquea un cambio de displayName", async () => {
    await seedOwner({ bestSquatKg: 1200 });
    await assertSucceeds(
      db(OWNER)
        .collection("userPublicProfiles")
        .doc(OWNER)
        .set({ displayName: "Despues" }, { merge: true }),
    );
  });

  it("lifetimeVolumeKg legacy por encima del tope no bloquea un cambio de displayName", async () => {
    await seedOwner({ lifetimeVolumeKg: 999999999999 });
    await assertSucceeds(
      db(OWNER)
        .collection("userPublicProfiles")
        .doc(OWNER)
        .set({ displayName: "Despues" }, { merge: true }),
    );
  });

  // `isProfilePublic` existe en el modelo desde 2026-07-06 y el `is bool` de la
  // regla llego el 2026-07-24: 18 dias de ventana.
  it("isProfilePublic legacy mal tipado no bloquea un cambio de displayName", async () => {
    await seedOwner({ isProfilePublic: "si" });
    await assertSucceeds(
      db(OWNER)
        .collection("userPublicProfiles")
        .doc(OWNER)
        .set({ displayName: "Despues" }, { merge: true }),
    );
  });

  it("rachaUpdatedAt legacy mal tipado no bloquea un cambio de displayName", async () => {
    await seedOwner({ rachaUpdatedAt: "ayer" });
    await assertSucceeds(
      db(OWNER)
        .collection("userPublicProfiles")
        .doc(OWNER)
        .set({ displayName: "Despues" }, { merge: true }),
    );
  });

  it("rankingOptIn legacy mal tipado no bloquea un cambio de displayName", async () => {
    await seedOwner({ rankingOptIn: 1 });
    await assertSucceeds(
      db(OWNER)
        .collection("userPublicProfiles")
        .doc(OWNER)
        .set({ displayName: "Despues" }, { merge: true }),
    );
  });

  // El camino de reparacion que el pin ya contemplaba: apagar el opt-in resetea
  // la metrica al default. Sobre un doc legacy tenia que seguir funcionando.
  it("el disable de rankingOptIn resetea una metrica legacy al default", async () => {
    await seedOwner({ bestSquatKg: 1200, rankingOptIn: true });
    await assertSucceeds(
      db(OWNER)
        .collection("userPublicProfiles")
        .doc(OWNER)
        .set({ rankingOptIn: false, bestSquatKg: null }, { merge: true }),
    );
  });

  // ── EL TRADEOFF que este fix paga ─────────────────────────────────────────
  //
  // Esta fila NO es un caso legacy mas: documenta un bit que el fix ENTREGA.
  //
  // Con `bestSquatKg: 1200` guardado y el opt-in apagado, esta escritura vuelve
  // a poner el perfil DENTRO del ranking —la query filtra por
  // `rankingOptIn == true` (`user_public_profile_repository.dart:195`)— y el
  // valor fuera de rango viaja con el.
  //
  // Pre-fix la escritura estaba DENEGADA. Pero no por un gate: por la
  // congelacion. La cota de rango denegaba TODA escritura sobre el doc,
  // incluida la reparacion, asi que "no podias re-entrar al ranking" era el
  // mismo hecho que "no podias cambiarte el displayName". Descongelar el
  // documento y entregar este bit son el MISMO cambio.
  //
  // Lo que acota el tradeoff, y por eso se decidio pagarlo:
  //   - No es un camino de blanqueo. El pin sigue prohibiendo escribir
  //     cualquier OTRO valor: el dueno solo puede arrastrar el que ya estaba
  //     guardado, que no eligio el. La fila "forjar un bestSquatKg dentro de
  //     rango" de abajo es la que mide eso.
  //   - Ese valor lo escribio la CF con Admin SDK, que saltea estas reglas, y
  //     el propio flip dispara `rankingAggregateOnOptIn`, que recomputa desde
  //     `familyMaxWeight` (`ranking-aggregate.ts:95`) — que TAMPOCO acota. La
  //     regla de update nunca fue lo que mantenia ese valor afuera del ranking.
  //
  // Si algun dia se quiere cerrar de verdad, el lugar es la CF, no esta regla.
  it("TRADEOFF: el opt-in false->true arrastra al ranking una metrica legacy", async () => {
    await seedOwner({ bestSquatKg: 1200, rankingOptIn: false });
    await assertSucceeds(
      db(OWNER)
        .collection("userPublicProfiles")
        .doc(OWNER)
        .set({ rankingOptIn: true }, { merge: true }),
    );
  });

  // ── Custodia: el gate no se aflojo ────────────────────────────────────────
  it("DENY: escribir un bestSquatKg fresco fuera de rango sobre un doc limpio", async () => {
    await seedOwner({ bestSquatKg: null });
    await assertFails(
      db(OWNER)
        .collection("userPublicProfiles")
        .doc(OWNER)
        .set({ bestSquatKg: 1200 }, { merge: true }),
    );
  });

  // §1.8, punto 2 — un cero en la mutacion no prueba nada por si solo. Mutar el
  // PIN y mutar la COTA daban las dos 0 filas rojas porque 1200 y 1500 los
  // rechazan LOS DOS. Esta fila le tira al pin la escritura que SOLO el pin
  // custodia: una metrica forjada pero DENTRO de rango, que la cota deja pasar.
  it("DENY: forjar un bestSquatKg dentro de rango sobre un doc limpio (custodia del pin)", async () => {
    await seedOwner({ bestSquatKg: null });
    await assertFails(
      db(OWNER)
        .collection("userPublicProfiles")
        .doc(OWNER)
        .set({ bestSquatKg: 900 }, { merge: true }),
    );
  });

  it("DENY: CAMBIAR un bestSquatKg legacy a otro valor fuera de rango", async () => {
    await seedOwner({ bestSquatKg: 1200 });
    await assertFails(
      db(OWNER)
        .collection("userPublicProfiles")
        .doc(OWNER)
        .set({ bestSquatKg: 1500 }, { merge: true }),
    );
  });

  it("DENY: cambiar isProfilePublic a un valor mal tipado", async () => {
    await seedOwner({ isProfilePublic: true });
    await assertFails(
      db(OWNER)
        .collection("userPublicProfiles")
        .doc(OWNER)
        .set({ isProfilePublic: "si" }, { merge: true }),
    );
  });

  it("DENY: cambiar rachaUpdatedAt a un valor mal tipado", async () => {
    await seedOwner({});
    await assertFails(
      db(OWNER)
        .collection("userPublicProfiles")
        .doc(OWNER)
        .set({ rachaUpdatedAt: "ayer" }, { merge: true }),
    );
  });

  it("DENY: cambiar rankingOptIn a un valor mal tipado", async () => {
    await seedOwner({ rankingOptIn: true });
    await assertFails(
      db(OWNER)
        .collection("userPublicProfiles")
        .doc(OWNER)
        .set({ rankingOptIn: 1 }, { merge: true }),
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// performance_tests — `PerformanceTestRepository.update` hace `set(t.toJson())`
// del modelo COMPLETO, y `log_performance_test_screen.dart` prefillea cada
// campo con el valor guardado: el round-trip re-presenta el valor legacy.
// ─────────────────────────────────────────────────────────────────────────────
describe("performance_tests: un resultado legacy negativo sigue siendo editable", () => {
  const BASE = {
    id: DOC,
    athleteId: ATHLETE,
    recordedBy: TRAINER,
  };

  // `sitAndReachCm` NEGATIVO ES UN RESULTADO NORMAL: el test mide cuanto llegas
  // mas alla de la punta de los pies, y no llegar da negativo. La pantalla no
  // tuvo NINGUN validador hasta 2026-06-17 (737cb5f3 agrego `parsed <= 0`), y
  // la regla `optPositiveNum` llego el 2026-07-23. Entre 2026-06-02 y
  // 2026-06-17 un PF podia registrar -5 desde la app oficial.
  it("sitAndReachCm negativo legacy no bloquea editar las notas", async () => {
    await seedRole(TRAINER, "trainer");
    const recordedAt = new Date("2026-06-10T10:00:00Z");
    await seed("performance_tests", DOC, {
      ...BASE,
      recordedAt,
      sitAndReachCm: -5,
      notes: "antes",
    });
    await assertSucceeds(
      db(TRAINER)
        .collection("performance_tests")
        .doc(DOC)
        .set({ ...BASE, recordedAt, sitAndReachCm: -5, notes: "despues" }),
    );
  });

  it("recordedAt legacy mal tipado no bloquea editar las notas", async () => {
    await seedRole(TRAINER, "trainer");
    await seed("performance_tests", DOC, {
      ...BASE,
      recordedAt: "2026-06-10",
      notes: "antes",
    });
    await assertSucceeds(
      db(TRAINER)
        .collection("performance_tests")
        .doc(DOC)
        .set({ ...BASE, recordedAt: "2026-06-10", notes: "despues" }),
    );
  });

  // ── Custodia ──────────────────────────────────────────────────────────────
  it("DENY: crear un test con sitAndReachCm fuera de rango (el create no se aflojo)", async () => {
    await seedRole(TRAINER, "trainer");
    await assertFails(
      db(TRAINER)
        .collection("performance_tests")
        .doc(DOC)
        .set({ ...BASE, recordedAt: new Date(), sitAndReachCm: -5 }),
    );
  });

  it("DENY: crear un test sin recordedAt (la presencia obligatoria no se aflojo)", async () => {
    await seedRole(TRAINER, "trainer");
    await assertFails(
      db(TRAINER)
        .collection("performance_tests")
        .doc(DOC)
        .set({ ...BASE, cmjCm: 30 }),
    );
  });

  it("DENY: CAMBIAR un valor valido a uno fuera de rango", async () => {
    await seedRole(TRAINER, "trainer");
    const recordedAt = new Date("2026-06-10T10:00:00Z");
    await seed("performance_tests", DOC, { ...BASE, recordedAt, cmjCm: 30 });
    await assertFails(
      db(TRAINER)
        .collection("performance_tests")
        .doc(DOC)
        .set({ ...BASE, recordedAt, cmjCm: -5 }),
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// measurements — mismo writer de round-trip completo
// (`measurement_repository.dart:35`, `log_measurement_screen.dart:389`), misma
// ventana: sin validador hasta 2026-06-17, regla desde 2026-07-23.
// ─────────────────────────────────────────────────────────────────────────────
describe("measurements: una medida legacy fuera de rango sigue siendo editable", () => {
  const BASE = { id: DOC, athleteId: ATHLETE, recordedBy: TRAINER };

  it("weightKg legacy por encima del tope no bloquea editar las notas", async () => {
    await seedRole(TRAINER, "trainer");
    const recordedAt = new Date("2026-06-10T10:00:00Z");
    await seed("measurements", DOC, {
      ...BASE,
      recordedAt,
      weightKg: 501,
      notes: "antes",
    });
    await assertSucceeds(
      db(TRAINER)
        .collection("measurements")
        .doc(DOC)
        .set({ ...BASE, recordedAt, weightKg: 501, notes: "despues" }),
    );
  });

  it("waistCm legacy negativo no bloquea editar las notas", async () => {
    await seedRole(TRAINER, "trainer");
    const recordedAt = new Date("2026-06-10T10:00:00Z");
    await seed("measurements", DOC, {
      ...BASE,
      recordedAt,
      waistCm: -1,
      notes: "antes",
    });
    await assertSucceeds(
      db(TRAINER)
        .collection("measurements")
        .doc(DOC)
        .set({ ...BASE, recordedAt, waistCm: -1, notes: "despues" }),
    );
  });

  // ── Custodia ──────────────────────────────────────────────────────────────
  it("DENY: crear una medida con weightKg fuera de rango", async () => {
    await seedRole(TRAINER, "trainer");
    await assertFails(
      db(TRAINER)
        .collection("measurements")
        .doc(DOC)
        .set({ ...BASE, recordedAt: new Date(), weightKg: 501 }),
    );
  });

  it("DENY: crear una medida sin recordedAt", async () => {
    await seedRole(TRAINER, "trainer");
    await assertFails(
      db(TRAINER)
        .collection("measurements")
        .doc(DOC)
        .set({ ...BASE, weightKg: 80 }),
    );
  });

  // La mutacion de este gate daba 0 filas rojas: era un gate SIN CUSTODIA. Las
  // 20 metricas comparten `optNumInRange`, pero comparten la funcion, no el
  // conjunto — cada `&&` es su propio gate y necesita su propia fila.
  it("DENY: CAMBIAR waistCm a un valor fuera de rango", async () => {
    await seedRole(TRAINER, "trainer");
    const recordedAt = new Date("2026-06-10T10:00:00Z");
    await seed("measurements", DOC, { ...BASE, recordedAt, waistCm: 80 });
    await assertFails(
      db(TRAINER)
        .collection("measurements")
        .doc(DOC)
        .set({ ...BASE, recordedAt, waistCm: 501 }),
    );
  });

  it("DENY: CAMBIAR weightKg a un valor fuera de rango", async () => {
    await seedRole(TRAINER, "trainer");
    const recordedAt = new Date("2026-06-10T10:00:00Z");
    await seed("measurements", DOC, { ...BASE, recordedAt, weightKg: 80 });
    await assertFails(
      db(TRAINER)
        .collection("measurements")
        .doc(DOC)
        .set({ ...BASE, recordedAt, weightKg: 501 }),
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// athlete_billing — `setConfig` hace `set(merge:true)` con el modelo releido, y
// el dialogo prefillea el monto guardado (`athlete_detail_screen.dart:1243`).
// El monto es texto libre SIN tope en el cliente; la regla llego el 2026-07-21
// con el modelo desde el 2026-06-03.
// ─────────────────────────────────────────────────────────────────────────────
describe("athlete_billing: un monto legacy por encima del tope sigue siendo editable", () => {
  const ID = `${TRAINER}_${ATHLETE}`;

  it("amountArs legacy por encima del tope no bloquea cambiar la cadencia", async () => {
    await seed("athlete_billing", ID, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      amountArs: 999999999999,
      cadence: "mensual",
      updatedAt: new Date("2026-06-10T10:00:00Z"),
    });
    await assertSucceeds(
      db(TRAINER)
        .collection("athlete_billing")
        .doc(ID)
        .set(
          {
            amountArs: 999999999999,
            cadence: "semanal",
            updatedAt: new Date(),
          },
          { merge: true },
        ),
    );
  });

  // ── Custodia ──────────────────────────────────────────────────────────────
  it("DENY: CAMBIAR amountArs a un valor por encima del tope", async () => {
    await seed("athlete_billing", ID, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      amountArs: 50000,
      cadence: "mensual",
      updatedAt: new Date("2026-06-10T10:00:00Z"),
    });
    await assertFails(
      db(TRAINER)
        .collection("athlete_billing")
        .doc(ID)
        .set(
          { amountArs: 999999999999, updatedAt: new Date() },
          { merge: true },
        ),
    );
  });

  // La mutacion de `affectedKeys()` daba 0 filas rojas. Ese conjunto no custodia
  // el dinero —eso lo hace la cota— sino la INMUTABILIDAD de la identidad:
  // trainerId/athleteId no se reasignan por update.
  it("DENY: reasignar athleteId en un update (custodia de affectedKeys)", async () => {
    await seed("athlete_billing", ID, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      amountArs: 50000,
      cadence: "mensual",
      updatedAt: new Date("2026-06-10T10:00:00Z"),
    });
    await assertFails(
      db(TRAINER)
        .collection("athlete_billing")
        .doc(ID)
        .set({ athleteId: "otro-alumno", updatedAt: new Date() }, { merge: true }),
    );
  });

  it("DENY: crear un billing con amountArs por encima del tope", async () => {
    await seedRole(TRAINER, "trainer");
    await assertFails(
      db(TRAINER)
        .collection("athlete_billing")
        .doc(ID)
        .set({
          trainerId: TRAINER,
          athleteId: ATHLETE,
          amountArs: 999999999999,
          cadence: "mensual",
          updatedAt: new Date(),
        }),
    );
  });

  // `cadence` sale de un enum y `updatedAt` de `DateTime.now()`: nunca tuvieron
  // ventana legacy, asi que NO se condicionaron y siguen siendo incondicionales.
  it("DENY: un cadence invalido sigue denegado aunque no cambie el monto", async () => {
    await seed("athlete_billing", ID, {
      trainerId: TRAINER,
      athleteId: ATHLETE,
      amountArs: 50000,
      cadence: "mensual",
      updatedAt: new Date("2026-06-10T10:00:00Z"),
    });
    await assertFails(
      db(TRAINER)
        .collection("athlete_billing")
        .doc(ID)
        .set({ cadence: "trimestral", updatedAt: new Date() }, { merge: true }),
    );
  });
});
